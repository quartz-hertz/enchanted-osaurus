//
//  LanguageModelStore+Agents.swift
//  Enchanted
//
//  Created for Enchanted Fork - Add agents to model list
//

import Foundation
import SwiftUI

extension LanguageModelStore {
    /// Load both regular models and agents
    @MainActor
    func loadModelsAndAgents() async throws {
        // Load + persist Ollama models. This resets `self.models` to the
        // filtered set of Ollama models currently reported by the server.
        try await loadModels()
        
        // Load agents from Osaurus
        await AgentStore.shared.loadAgents()
        
        // Persist agent models and fetch them back as managed objects.
        let agentModels = await AgentStore.shared.agentsAsModels()
        
        // `loadModels()` already cleared `self.models` to Ollama-only, so
        // there are no stale transient agent wrappers to remove here; just
        // append the freshly-fetched managed agent rows.
        if !agentModels.isEmpty {
            self.models.append(contentsOf: agentModels)
        }
    }
    
    /// Check if current model is an agent
    @MainActor
    var isAgentSelected: Bool {
        selectedModel?.isAgent ?? false
    }
    
    /// Get agent for current selection
    @MainActor
    var selectedAgent: OsaurusAgent? {
        guard let model = selectedModel,
              model.isAgent,
              let address = model.agentAddress else {
            return nil
        }
        return AgentStore.shared.getAgent(address: address)
    }
}
