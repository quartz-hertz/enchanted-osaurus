//
//  AgentService.swift
//  Enchanted
//
//  Enhanced with Osaurus Secure Channel support
//

import Foundation
import Combine

/// Service for interacting with Osaurus agents
class AgentService: @unchecked Sendable {
    static let shared = AgentService()
    
    private var serverConfig: OsaurusServerConfig?
    private let urlSession = URLSession.shared
    
    private init() {}
    
    /// Configure the service with Osaurus endpoint
    /// - Parameters:
    ///   - baseURL: Osaurus server base URL
    ///   - bearerToken: Optional bearer token for authentication
    ///   - pinnedAgentAddress: Server's Ethereum address (from relay settings, e.g. 0x5c8bb1...)
    func configure(baseURL: URL, bearerToken: String?, pinnedAgentAddress: String? = nil) {
        self.serverConfig = OsaurusServerConfig(
            baseURL: baseURL,
            bearerToken: bearerToken,
            pinnedAgentAddress: pinnedAgentAddress
        )
        
        if let addr = pinnedAgentAddress {
            print("🔐 Configured with server address: \(addr)")
        }
    }
    
    /// Fetch available agents from Osaurus
    func fetchAgents() async throws -> [OsaurusAgent] {
        guard let config = serverConfig else {
            throw AgentError.notConfigured
        }
        
        let url = config.baseURL.appendingPathComponent("/agents")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        if let token = config.bearerToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AgentError.networkError("Failed to fetch agents")
        }
        
        // Debug: Print raw JSON to see what fields are actually present
        if let jsonString = String(data: data, encoding: .utf8) {
            print("🔍 Raw /agents response:")
            print(jsonString)
        }
        
        let agentsResponse = try JSONDecoder().decode(AgentsResponse.self, from: data)
        
        // Debug: Print what we decoded
        for agent in agentsResponse.agents {
            print("🔍 Agent: id=\(agent.id), address=\(agent.address), ethAddr=\(agent.ethereumAddress ?? "none")")
        }
        
        return agentsResponse.agents
    }
    
    /// Run an agent conversation (streaming) with secure channel support  
    func runAgent(
        address: String,
        messages: [AgentMessage]
    ) -> AnyPublisher<AgentRunResponse, Error> {
        guard let config = serverConfig else {
            print("🚨 AgentService not configured")
            return Fail(error: AgentError.notConfigured).eraseToAnyPublisher()
        }
        
        // Try secure channel first, fall back to plaintext if not supported
        // This handles servers with E2EE disabled or not yet configured
        print("🔐 Attempting secure channel for agent \(address)")
        
        return runAgentSecure(address: address, messages: messages, config: config)
            .catch { [weak self] error -> AnyPublisher<AgentRunResponse, Error> in
                guard let self = self else {
                    return Fail(error: AgentError.networkError("Service deallocated")).eraseToAnyPublisher()
                }
                
                // Check if error is "peer unsupported" (404 on /secure/session)
                if let agentError = error as? AgentError,
                   case .secureChannelError(let msg) = agentError,
                   msg.contains("does not support end-to-end encryption") {
                    print("📡 E2EE not enabled on server, using plaintext")
                    return self.runAgentPlaintext(address: address, messages: messages, config: config)
                }
                
                // For other errors (like 426 requiring E2EE), propagate them
                print("🚨 Secure channel failed with non-fallback error: \(error)")
                return Fail(error: error).eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Plaintext Path (fallback)
    
    private func runAgentPlaintext(
        address: String,
        messages: [AgentMessage],
        config: OsaurusServerConfig
    ) -> AnyPublisher<AgentRunResponse, Error> {
        let url = config.baseURL
            .appendingPathComponent("agents")
            .appendingPathComponent(address)
            .appendingPathComponent("run")
        print("🤖 Agent run URL (plaintext): \(url)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        
        if let token = config.bearerToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let requestBody = AgentRunRequest(messages: messages, stream: true)
        guard let bodyData = try? JSONEncoder().encode(requestBody) else {
            return Fail(error: AgentError.encodingError).eraseToAnyPublisher()
        }
        request.httpBody = bodyData
        
        return performStreamingRequest(request)
    }
    
    // MARK: - Secure Channel Path
    
    private func runAgentSecure(
        address: String,
        messages: [AgentMessage],
        config: OsaurusServerConfig
    ) -> AnyPublisher<AgentRunResponse, Error> {
        // Look up the agent's Ethereum address from the mapping
        let agentAddresses = UserDefaults.standard.dictionary(forKey: "agentEthereumAddresses") as? [String: String] ?? [:]
        let ethereumAddress = agentAddresses[address]
        
        if let ethAddr = ethereumAddress {
            print("🔐 Found Ethereum address for agent \(address): \(ethAddr)")
        } else {
            print("⚠️ No Ethereum address mapped for agent \(address) - handshake will likely fail")
        }
        
        // Use the agent's Ethereum address for signature verification
        var configWithAddress = config
        configWithAddress.pinnedAgentAddress = ethereumAddress ?? address  // Fall back to UUID
        
        return Future<(URLRequest, SecureResponseOpener), Error> { promise in
            Task {
                do {
                    // Build plaintext request (still uses UUID in path)
                    let url = config.baseURL
                        .appendingPathComponent("agents")
                        .appendingPathComponent(address)  // UUID
                        .appendingPathComponent("run")
                    
                    var plaintextRequest = URLRequest(url: url)
                    plaintextRequest.httpMethod = "POST"
                    plaintextRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    plaintextRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    
                    if let token = config.bearerToken, !token.isEmpty {
                        plaintextRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    }
                    
                    let requestBody = AgentRunRequest(messages: messages, stream: true)
                    plaintextRequest.httpBody = try JSONEncoder().encode(requestBody)
                    
                    print("🔐 Attempting handshake with Ethereum address: \(configWithAddress.pinnedAgentAddress ?? "none")")
                    
                    // Wrap in secure channel
                    let (wrappedRequest, opener) = try await SecureChannelClient.shared.wrappedRequest(
                        for: plaintextRequest,
                        provider: configWithAddress,
                        urlSession: self.urlSession
                    )
                    
                    print("🔐 Handshake successful! Agent run via secure channel to \(url)")
                    promise(.success((wrappedRequest, opener)))
                    
                } catch let error as SecureChannelClientError {
                    print("🚨 Secure channel error: \(error.localizedDescription ?? "Unknown")")
                    print("🚨 Error details: \(error)")
                    promise(.failure(AgentError.secureChannelError(error.localizedDescription ?? "Unknown error")))
                } catch {
                    print("🚨 Unexpected error: \(error)")
                    promise(.failure(error))
                }
            }
        }
        .flatMap { [weak self] wrappedRequest, opener -> AnyPublisher<AgentRunResponse, Error> in
            guard let self = self else {
                return Fail(error: AgentError.networkError("Service deallocated"))
                    .eraseToAnyPublisher()
            }
            
            // Perform the secure request with SSE decoding
            return self.performSecureStreamingRequest(wrappedRequest, opener: opener)
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Streaming Helpers
    
    /// Filter out the `data: [DONE]` SSE terminator, which is not valid JSON.
    /// OpenAI-compatible streams end with this marker; trying to decode it
    /// as an AgentRunResponse throws a decoding error on every response.
    private func filterSSDDataLines(_ lines: [String]) -> [String] {
        lines.filter {
            String($0.dropFirst("data: ".count)).trimmingCharacters(in: .whitespaces) != "[DONE]"
        }
    }
    
    private func performStreamingRequest(_ request: URLRequest) -> AnyPublisher<AgentRunResponse, Error> {
        return urlSession.dataTaskPublisher(for: request)
            .tryMap { data, response -> Data in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AgentError.networkError("Invalid response")
                }
                
                print("🤖 HTTP Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 426 {
                    // Secure channel required - this should trigger agent re-loading
                    throw AgentError.secureChannelRequired
                }
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw AgentError.networkError("Agent run failed: \(errorMessage)")
                }
                return data
            }
            .flatMap { data -> AnyPublisher<AgentRunResponse, Error> in
                // Parse streaming SSE responses
                let allLines = String(data: data, encoding: .utf8)?
                    .components(separatedBy: "\n")
                    .filter { !$0.isEmpty && $0.hasPrefix("data: ") } ?? []
                
                // Filter out [DONE] terminator
                let lines = self.filterSSDDataLines(allLines)
                
                print("🤖 Received \(lines.count) SSE lines (filtered \(allLines.count - lines.count) [DONE])")
                
                // DIAGNOSTIC: Log raw SSE JSON to discover artifact/tool_call
                // fields the model/server actually emits. Truncate to keep
                // output manageable; raise the prefix length if needed.
                for (i, line) in lines.prefix(10).enumerated() {
                    let raw = String(line.dropFirst("data: ".count))
                    print("🤖 Raw SSE[\(i)]: \(raw.prefix(800))")
                }
                
                let responses = lines.compactMap { line -> AgentRunResponse? in
                    let jsonStr = String(line.dropFirst("data: ".count))
                    guard let lineData = jsonStr.data(using: .utf8),
                          let response = try? JSONDecoder().decode(AgentRunResponse.self, from: lineData) else {
                        return nil
                    }
                    return response
                }
                
                print("🤖 Successfully decoded \(responses.count) responses")
                
                return Publishers.Sequence(sequence: responses)
                    .setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
    
    private func performSecureStreamingRequest(
        _ request: URLRequest,
        opener: SecureResponseOpener
    ) -> AnyPublisher<AgentRunResponse, Error> {
        return Future<(Data, HTTPURLResponse), Error> { promise in
            Task {
                do {
                    let (data, response) = try await self.urlSession.data(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AgentError.networkError("Invalid response")
                    }
                    
                    print("🔐 Secure call status: \(httpResponse.statusCode)")
                    
                    // Check for session-unknown error (server restarted)
                    if SecureChannelClient.isSessionUnknownError(statusCode: httpResponse.statusCode, body: data) {
                        print("🔄 Session expired, will retry")
                        throw AgentError.sessionExpired
                    }
                    
                    guard (200...299).contains(httpResponse.statusCode) else {
                        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                        throw AgentError.networkError("Secure call failed: \(errorMessage)")
                    }
                    
                    promise(.success((data, httpResponse)))
                    
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .flatMap { data, _ -> AnyPublisher<AgentRunResponse, Error> in
            // Decrypt the SSE stream
            let decoder = SecureFrameStreamDecoder(opener: opener)
            
            do {
                print("🔐 Received \(data.count) bytes from secure channel")
                let plaintext = try decoder.feed(data)
                print("🔐 Decrypted \(plaintext.count) bytes of plaintext")
                print("🔐 Decoder finished = \(decoder.finished)")
                
                // DIAGNOSTIC: Check if fin frame was received BEFORE calling verifyCompleted
                // This helps identify Suspect #2 (fin frame missing)
                if !decoder.finished {
                    print("⚠️ WARNING: Decoder not finished - no fin frame received!")
                    print("⚠️ This indicates:")
                    print("   - Server did not send authenticated fin frame")
                    print("   - Or network/proxy truncated the response")
                    print("   - Next line will throw .streamTruncated error")
                }
                
                try decoder.verifyCompleted()
                print("✅ Stream completed with authenticated fin frame")
                
                // Debug: Print decrypted data
                if let decryptedString = String(data: plaintext, encoding: .utf8) {
                    let preview = decryptedString.prefix(500)
                    print("🔍 Decrypted content preview (first 500 chars):")
                    print(preview)
                }
                
                // Parse decrypted SSE
                let allLines = String(data: plaintext, encoding: .utf8)?
                    .components(separatedBy: "\n")
                    .filter { !$0.isEmpty && $0.hasPrefix("data: ") } ?? []
                
                // Filter out [DONE] terminator
                let lines = self.filterSSDDataLines(allLines)
                
                print("🔐 Found \(lines.count) SSE data lines (filtered \(allLines.count - lines.count) [DONE])")
                
                // DIAGNOSTIC: Log raw SSE JSON to discover artifact/tool_call
                // fields the model/server actually emits. This is the critical
                // diagnostic — it shows whether `share_artifact` arrives as
                // `tool_calls`, as a dedicated field, or purely as inline
                // `content` with `<channel|>` markers.
                for (i, line) in lines.prefix(10).enumerated() {
                    let raw = String(line.dropFirst("data: ".count))
                    print("🔐 Raw SSE[\(i)]: \(raw.prefix(800))")
                }
                
                let responses = lines.compactMap { line -> AgentRunResponse? in
                    let jsonStr = String(line.dropFirst("data: ".count))
                    guard let lineData = jsonStr.data(using: .utf8) else {
                        print("⚠️ Failed to convert line to UTF-8")
                        return nil
                    }
                    
                    do {
                        let response = try JSONDecoder().decode(AgentRunResponse.self, from: lineData)
                        
                        // DIAGNOSTIC: Surface tool calls so we can see if
                        // share_artifact is being streamed.
                        if let toolCalls = response.toolCalls, !toolCalls.isEmpty {
                            for tc in toolCalls {
                                print("🔧 Tool call: name=\(tc.function?.name ?? "?"), args=\(tc.function?.arguments ?? "?")")
                            }
                        }
                        
                        return response
                    } catch {
                        print("⚠️ Failed to decode AgentRunResponse")
                        print("   Line: \(jsonStr.prefix(200))")
                        print("   Error: \(error)")
                        return nil
                    }
                }
                
                print("🔐 Successfully decoded \(responses.count) secure responses")
                
                return Publishers.Sequence(sequence: responses)
                    .setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
                
            } catch let error as SecureChannelClientError {
                print("🚨 SecureChannelClientError caught during decryption!")
                print("🚨 Error: \(error)")
                print("🚨 Description: \(error.errorDescription ?? "none")")
                
                // Specifically identify streamTruncated (Suspect #2)
                if error == .streamTruncated {
                    print("🚨 CONFIRMED: Suspect #2 - Missing fin frame!")
                    print("🚨 The encrypted response was truncated before completion.")
                    print("🚨 This may be causing conversation to appear to restart.")
                }
                
                return Fail(error: AgentError.decryptionError(error.localizedDescription ?? "Unknown")).eraseToAnyPublisher()
            } catch {
                print("🚨 Unexpected decryption error: \(error)")
                return Fail(error: AgentError.decryptionError(error.localizedDescription)).eraseToAnyPublisher()
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// Check if agents are available
    func agentsAvailable() async -> Bool {
        guard serverConfig != nil else { return false }
        
        do {
            let agents = try await fetchAgents()
            return !agents.isEmpty
        } catch {
            return false
        }
    }
}

// MARK: - Errors

enum AgentError: LocalizedError {
    case notConfigured
    case networkError(String)
    case encodingError
    case decodingError
    case secureChannelRequired
    case secureChannelError(String)
    case sessionExpired
    case decryptionError(String)
    case identityMismatch
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Agent service not configured"
        case .networkError(let message):
            return message
        case .encodingError:
            return "Failed to encode request"
        case .decodingError:
            return "Failed to decode response"
        case .secureChannelRequired:
            return """
            🔐 This Osaurus server requires end-to-end encryption.
            
            Reload agents to enable secure channel, then try again.
            """
        case .secureChannelError(let message):
            return "Secure channel error: \(message)"
        case .sessionExpired:
            return "Secure session expired - will retry automatically"
        case .decryptionError(let message):
            return "Decryption failed: \(message)"
        case .identityMismatch:
            return """
            ⚠️ Agent identity verification failed!
            
            The agent's address doesn't match the pinned address.
            This could indicate:
            • Server was re-installed
            • Man-in-the-middle attack
            
            Re-verify the agent before continuing.
            """
        }
    }
}
