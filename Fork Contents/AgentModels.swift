//
//  AgentModels.swift
//  Enchanted
//
//  Created for Enchanted Fork - Agent support
//

import Foundation

/// Agent from Osaurus /agents endpoint
struct OsaurusAgent: Codable, Identifiable, Hashable {
    let id: String  // UUID from Osaurus
    let name: String
    let description: String
    let avatar: String?
    let defaultModel: String
    let effectiveModel: String
    let supportsThinking: Bool
    let supportsVision: Bool
    let isBuiltIn: Bool
    let memoryEntryCount: Int
    let createdAt: String
    let updatedAt: String
    
    // Ethereum address for secure channel (0x... format)
    // This may be a separate field in newer Osaurus versions
    let agentAddress: String?
    
    /// Address/identifier for agent operations
    /// Prefers agentAddress (0x...) if available, falls back to id
    var address: String {
        agentAddress ?? id
    }
    
    /// Ethereum-style address for secure channel, if available
    var ethereumAddress: String? {
        // Check if address looks like an Ethereum address
        if let addr = agentAddress, addr.hasPrefix("0x") && addr.count == 42 {
            return addr
        }
        return nil
    }
    
    /// Model to display in UI
    var model: String? { effectiveModel }
    
    /// Display name for UI
    var displayName: String {
        name.isEmpty ? id : name
    }
    
    // Custom coding keys to match Osaurus API snake_case
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case avatar
        case defaultModel = "default_model"
        case effectiveModel = "effective_model"
        case supportsThinking = "supports_thinking"
        case supportsVision = "supports_vision"
        case isBuiltIn = "is_built_in"
        case memoryEntryCount = "memory_entry_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case agentAddress = "agent_address"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decode(String.self, forKey: .description)
        self.avatar = try? container.decode(String.self, forKey: .avatar)
        self.defaultModel = try container.decode(String.self, forKey: .defaultModel)
        self.effectiveModel = try container.decode(String.self, forKey: .effectiveModel)
        self.supportsThinking = try container.decode(Bool.self, forKey: .supportsThinking)
        self.supportsVision = try container.decode(Bool.self, forKey: .supportsVision)
        self.isBuiltIn = try container.decode(Bool.self, forKey: .isBuiltIn)
        self.memoryEntryCount = try container.decode(Int.self, forKey: .memoryEntryCount)
        self.createdAt = try container.decode(String.self, forKey: .createdAt)
        self.updatedAt = try container.decode(String.self, forKey: .updatedAt)
        // Try to decode agent_address, may not exist in older versions
        self.agentAddress = try? container.decode(String.self, forKey: .agentAddress)
    }
    
    // Standard init for creating instances
    init(
        id: String,
        name: String,
        description: String = "",
        avatar: String? = nil,
        defaultModel: String,
        effectiveModel: String,
        supportsThinking: Bool = false,
        supportsVision: Bool = false,
        isBuiltIn: Bool = false,
        memoryEntryCount: Int = 0,
        createdAt: String = "",
        updatedAt: String = "",
        agentAddress: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.avatar = avatar
        self.defaultModel = defaultModel
        self.effectiveModel = effectiveModel
        self.supportsThinking = supportsThinking
        self.supportsVision = supportsVision
        self.isBuiltIn = isBuiltIn
        self.memoryEntryCount = memoryEntryCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.agentAddress = agentAddress
    }
}

/// Response from GET /agents
struct AgentsResponse: Codable {
    let agents: [OsaurusAgent]
}

/// Request body for POST /agents/{address}/run
struct AgentRunRequest: Codable {
    let messages: [AgentMessage]
    let stream: Bool
}

/// Polymorphic message content: a plain string for text-only messages, or an
/// array of typed content parts (OpenAI Chat Completions multimodal format)
/// when images are attached. Both shapes are valid OpenAI `content` values, so
/// text-only messages stay compact while vision messages encode images as
/// `image_url` parts with data URIs.
///
/// We use this instead of the Ollama-style `images: [String]` field because
/// the Osaurus agent run endpoint speaks OpenAI format on the response side
/// (streaming `choices`/`delta`), and OpenAI vision requires the content-array
/// schema — a bare `images` field is silently ignored.
enum AgentContent: Codable, Equatable {
    case text(String)
    case parts([ContentPart])
    
    /// Build from a text string and optional base64 image attachments.
    /// If `images` is nil or empty, produces `.text(text)`. Otherwise produces
    /// `.parts` with a leading text part (if non-empty) followed by one
    /// `image_url` part per image, each as a `data:image/jpeg;base64,…` URI.
    init(text: String, images: [String]?) {
        guard let images = images, !images.isEmpty else {
            self = .text(text)
            return
        }
        var parts: [ContentPart] = []
        if !text.isEmpty {
            parts.append(.text(text))
        }
        for image in images {
            parts.append(.image(dataURI: "data:image/jpeg;base64,\(image)"))
        }
        self = .parts(parts)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .text(s)
        } else if let parts = try? container.decode([ContentPart].self) {
            self = .parts(parts)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected content as String or [ContentPart]"
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let s):
            try container.encode(s)
        case .parts(let p):
            try container.encode(p)
        }
    }
}

/// One part of an OpenAI multimodal `content` array.
struct ContentPart: Codable, Equatable {
    let type: String
    let text: String?
    let imageURL: ImageURL?
    
    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }
    
    static func text(_ s: String) -> ContentPart {
        ContentPart(type: "text", text: s, imageURL: nil)
    }
    
    static func image(dataURI: String) -> ContentPart {
        ContentPart(type: "image_url", text: nil, imageURL: ImageURL(url: dataURI))
    }
}

/// The `image_url` object inside an `image_url` content part.
struct ImageURL: Codable, Equatable {
    let url: String
}

struct AgentMessage: Codable {
    let role: String
    let content: AgentContent
    
    /// Convenience init from Ollama-style fields. If `images` is present and
    /// non-empty, produces an OpenAI content array (text + image_url parts);
    /// otherwise a plain string content. Both are valid OpenAI Chat
    /// Completions format.
    init(role: String, text: String, images: [String]? = nil) {
        self.role = role
        self.content = AgentContent(text: text, images: images)
    }
}

/// Streaming response from agent run (supports both formats)
struct AgentRunResponse: Codable {
    // Osaurus agent format
    let message: AgentResponseMessage?
    let done: Bool?
    
    // OpenAI streaming format (used when E2EE is enabled)
    let id: String?
    let object: String?
    let created: Int?
    let model: String?
    let choices: [ChatChoice]?
    
    /// Extract content from either format
    var content: String? {
        // Try Osaurus format first
        if let msg = message?.content {
            return msg
        }
        // Try OpenAI format
        if let choice = choices?.first, let delta = choice.delta?.content {
            return delta
        }
        return nil
    }
    
    /// Tool calls from the OpenAI streaming format (e.g. `share_artifact`).
    /// These arrive as `choices[].delta.tool_calls` and were previously
    /// silently dropped because `ChatDelta` did not decode them.
    var toolCalls: [ChatToolCall]? {
        choices?.first?.delta?.toolCalls
    }
    
    /// Check if this is the final message
    var isComplete: Bool {
        // Osaurus format
        if let done = done {
            return done
        }
        // OpenAI format
        if let choice = choices?.first, choice.finishReason != nil {
            return true
        }
        return false
    }
}

struct AgentResponseMessage: Codable {
    let role: String?
    let content: String?
    let toolProgress: String?  // Tool execution progress hint
    
    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolProgress = "tool_progress"
    }
}

// OpenAI streaming format structures
struct ChatChoice: Codable {
    let index: Int
    let delta: ChatDelta?
    let finishReason: String?
    
    enum CodingKeys: String, CodingKey {
        case index
        case delta
        case finishReason = "finish_reason"
    }
}

struct ChatDelta: Codable {
    let role: String?
    let content: String?
    /// Tool calls streamed by the model (OpenAI format). For streaming,
    /// `function.arguments` arrives as a JSON-string fragment that must be
    /// accumulated across deltas by `index` before it can be parsed.
    let toolCalls: [ChatToolCall]?
    
    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
    }
}

/// One streamed tool call entry from `choices[].delta.tool_calls`.
struct ChatToolCall: Codable {
    /// Identifies which tool call this fragment belongs to when multiple
    /// calls are streamed concurrently.
    let index: Int
    let id: String?
    let type: String?
    let function: ChatToolCallFunction?
}

/// The `function` object inside a streamed tool call.
struct ChatToolCallFunction: Codable {
    let name: String?
    /// JSON-encoded arguments string. In streaming this arrives in
    /// fragments; concatenate by `index` before decoding.
    let arguments: String?
}
