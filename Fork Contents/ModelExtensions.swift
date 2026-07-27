//
//  ModelExtensions.swift
//  Enchanted
//
//  Created for Enchanted Fork - Add agent support to models
//

import Foundation
import SwiftData

// MARK: - ConversationSD Extension
// Add agent support to conversations
extension ConversationSD {
    /// Agent ID for agent-based conversations
    /// This should be added to the @Model as: @Attribute var agentId: String?
    /// For now, we'll store it in UserDefaults as a workaround until we can modify the model
    var agentId: String? {
        get {
            UserDefaults.standard.string(forKey: "conversation_agent_\(id.uuidString)")
        }
        set {
            if let value = newValue {
                UserDefaults.standard.set(value, forKey: "conversation_agent_\(id.uuidString)")
            } else {
                UserDefaults.standard.removeObject(forKey: "conversation_agent_\(id.uuidString)")
            }
        }
    }
    
    /// Whether this conversation is with an agent
    var isAgentConversation: Bool {
        agentId != nil
    }
}

// MARK: - LanguageModelSD Extension
//
// `isAgent` and `agentAddress` are now first-class STORED properties on the
// @Model (see LanguageModelSD.swift), so agent rows are persisted and fetched
// back exactly like Ollama models. They must NOT be redeclared here as
// computed/@Transient — that was the old workaround that produced transient
// wrappers which collided with (or were never found by) managed rows.
extension LanguageModelSD {
    /// Get user-friendly display name (shows agent name instead of the
    /// "agent:{id}" row key). Looks the agent up via `AgentStore` by parsing
    /// the `name`, which still encodes the stable Osaurus agent id.
    @MainActor
    var displayName: String {
        if isAgent {
            // Look up the agent's actual name
            return AgentStore.shared.displayName(for: name)
        }
        return name
    }
}
