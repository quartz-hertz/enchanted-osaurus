//
//  AgentStore.swift
//  Enchanted
//
//  Created for Enchanted Fork - Agent management
//

import Foundation
import SwiftUI

@Observable
final class AgentStore: Sendable {
    static let shared = AgentStore()
    
    @MainActor var agents: [OsaurusAgent] = []
    @MainActor var isLoading: Bool = false
    @MainActor var error: String?
    
    private init() {}
    
    @MainActor
    func setupAddressUpdateListener() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AgentAddressesUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("🔄 Agent addresses updated, reloading configuration")
            Task {
                await self?.loadAgents()
            }
        }
    }
    
    /// Load agents from Osaurus
    @MainActor
    func loadAgents() async {
        isLoading = true
        error = nil
        
        // Configure AgentService with current settings
        if let ollamaUri = UserDefaults.standard.string(forKey: "ollamaUri"),
           let baseURL = URL(string: ollamaUri) {
            let bearerToken = UserDefaults.standard.string(forKey: "ollamaBearerToken")
            
            // Get pinned agent address if we have agents already
            var pinnedAddress: String?
            if !agents.isEmpty, let firstAgent = agents.first {
                pinnedAddress = self.pinnedAddress(forAgent: firstAgent.id)
            }
            
            AgentService.shared.configure(
                baseURL: baseURL,
                bearerToken: bearerToken,
                pinnedAgentAddress: pinnedAddress
            )
        }
        
        do {
            let fetchedAgents = try await AgentService.shared.fetchAgents()
            
            // Pin agent addresses on first discovery (TOFU)
            var verifiedAgents: [OsaurusAgent] = []
            for agent in fetchedAgents {
                // Only pin if agent has an Ethereum address (0x...)
                if let ethAddress = agent.ethereumAddress {
                    if verifyAndPinAgent(agent) {
                        verifiedAgents.append(agent)
                    } else {
                        error = "⚠️ Agent identity mismatch detected for \(agent.name)"
                        print("🚨 Agent \(agent.name) failed verification")
                    }
                } else {
                    // Agent doesn't have Ethereum address yet - add it but don't pin
                    // This means E2EE is not available for this agent
                    verifiedAgents.append(agent)
                    print("ℹ️ Agent \(agent.name) has no Ethereum address (UUID: \(agent.id)) - E2EE not available")
                }
            }
            
            agents = verifiedAgents
            print("✅ Loaded \(agents.count) agents (\(agents.filter { $0.ethereumAddress != nil }.count) support E2EE)")
            
            // Update service config with server Ethereum address (if available)
            // For Osaurus 0.21.11, this is the relay address shown in Network settings
            if let ollamaUri = UserDefaults.standard.string(forKey: "ollamaUri"),
               let baseURL = URL(string: ollamaUri) {
                let bearerToken = UserDefaults.standard.string(forKey: "ollamaBearerToken")
                
                // Try to get server address from settings
                // TODO: Add UI field for this in settings
                let serverAddress = UserDefaults.standard.string(forKey: "osaurusServerAddress")
                
                AgentService.shared.configure(
                    baseURL: baseURL,
                    bearerToken: bearerToken,
                    pinnedAgentAddress: serverAddress
                )
                
                if let addr = serverAddress {
                    print("🔐 Secure channel configured with server address: \(addr)")
                } else {
                    print("📡 No server address configured - E2EE will fall back to plaintext")
                    print("💡 To enable E2EE: Add server address from Osaurus Network→Relay settings")
                }
            }
            
        } catch {
            self.error = error.localizedDescription
            print("Failed to load agents: \(error)")
        }
        
        isLoading = false
    }
    
    /// Get agent by address
    @MainActor
    func getAgent(address: String) -> OsaurusAgent? {
        agents.first { $0.address == address }
    }
    
    /// Convert agents to `LanguageModelSD` rows for UI consistency.
    ///
    /// Agents are persisted as first-class `LanguageModelSD` rows (provider
    /// `.osaurus`, `isAgent == true`, `agentAddress` stored) via
    /// `SwiftDataService.fetchOrCreateAgentModel`, and the fetched managed
    /// object is returned. This guarantees `conversation.model` is always a
    /// managed object living in the SwiftDataService context — never a
    /// transient wrapper that could collide with an existing managed row or
    /// fail to resolve after a conversation reload.
    @MainActor
    func agentsAsModels() async -> [LanguageModelSD] {
        var result: [LanguageModelSD] = []
        for agent in agents {
            // Unique, stable row key. Keep the "agent:{id}" scheme so
            // `displayName(for:)` can still look the agent up by name.
            let name = "agent:\(agent.id)"
            // Runtime address used by `AgentService.runAgent(address:)`.
            let address = agent.address
            let supportsVision = agent.supportsVision
            do {
                let model = try await SwiftDataService.shared.fetchOrCreateAgentModel(
                    name: name,
                    agentAddress: address,
                    imageSupport: supportsVision
                )
                result.append(model)
            } catch {
                print("❌ Failed to fetch/create agent model for \(agent.name): \(error)")
            }
        }
        return result
    }
    
    /// Get display name for an agent model
    @MainActor
    func displayName(for modelName: String) -> String {
        // Extract agent ID from "agent:{id}" format
        guard modelName.hasPrefix("agent:") else { return modelName }
        let agentId = String(modelName.dropFirst("agent:".count))
        
        // Find the agent and return its name
        if let agent = agents.first(where: { $0.id == agentId }) {
            return agent.name
        }
        
        return modelName
    }
    
    // MARK: - Agent Address Pinning (TOFU)
    
    private let pinnedAddressesKey = "pinnedAgentAddresses"
    
    /// Pin an agent address on first discovery (Trust On First Use)
    @MainActor
    func pinAgentAddress(_ address: String, forAgent agentId: String) {
        // Don't pin UUIDs - only Ethereum addresses
        guard address.hasPrefix("0x") && address.count == 42 else {
            print("⚠️ Skipping pin for non-Ethereum address: \(address)")
            return
        }
        
        var pinned = UserDefaults.standard.dictionary(forKey: pinnedAddressesKey) as? [String: String] ?? [:]
        
        // Only pin if not already pinned
        if pinned[agentId] == nil {
            pinned[agentId] = address.lowercased()
            UserDefaults.standard.set(pinned, forKey: pinnedAddressesKey)
            print("📌 Pinned agent \(agentId) to address \(address)")
        } else if let existing = pinned[agentId], existing.lowercased() != address.lowercased() {
            // CRITICAL: Address changed - security violation!
            print("🚨 SECURITY: Agent \(agentId) address changed from \(existing) to \(address)")
            // Don't auto-update - require user verification
        }
    }
    
    /// Get pinned address for an agent
    @MainActor
    func pinnedAddress(forAgent agentId: String) -> String? {
        let pinned = UserDefaults.standard.dictionary(forKey: pinnedAddressesKey) as? [String: String] ?? [:]
        return pinned[agentId]
    }
    
    /// Verify agent address matches pinned (or pin if first time)
    @MainActor
    func verifyAndPinAgent(_ agent: OsaurusAgent) -> Bool {
        guard let existingPin = pinnedAddress(forAgent: agent.id) else {
            // First time seeing this agent - pin it (TOFU)
            pinAgentAddress(agent.address, forAgent: agent.id)
            return true
        }
        
        // Check if address matches
        if existingPin.lowercased() == agent.address.lowercased() {
            return true
        }
        
        // Address mismatch - potential security issue
        print("🚨 Agent \(agent.id) address mismatch: pinned=\(existingPin), received=\(agent.address)")
        return false
    }
}
