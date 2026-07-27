//
//  ModelSD.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 10/12/2023.
//

import Foundation
import SwiftData

@Model
final class LanguageModelSD: Identifiable {
    @Attribute(.unique) var name: String
    var isAvailable: Bool = false
    var imageSupport: Bool = false
    @Attribute var modelProvider: ModelProvider? = ModelProvider.ollama
    
    /// Whether this row represents an Osaurus agent rather than an Ollama model.
    /// Persisted (NOT @Transient) so agent models are first-class managed
    /// objects, exactly like Ollama models, and `conversation.model` is always
    /// a managed object after a fetch. Adding a stored property with a default
    /// is a lightweight SwiftData migration, so existing Ollama rows get
    /// `isAgent == false` automatically.
    var isAgent: Bool = false
    
    /// Address used to run the agent (Osaurus `agent.address`, i.e. the 0x…
    /// Ethereum address when available, otherwise the agent UUID). Persisted
    /// — NOT @Transient — so it survives fetches and is available off-context
    /// (e.g. in `ConversationStore.sendPrompt` after a conversation reload).
    var agentAddress: String? = nil
    
    @Relationship(deleteRule: .cascade, inverse: \ConversationSD.model)
    var conversations: [ConversationSD]? = []
    
    
    init(name: String, imageSupport: Bool = false, modelProvider: ModelProvider, isAgent: Bool = false, agentAddress: String? = nil) {
        self.name = name
        self.imageSupport = imageSupport
        self.modelProvider = modelProvider
        self.isAgent = isAgent
        self.agentAddress = agentAddress
    }
    
    @Transient var isNotAvailable: Bool {
        isAvailable == false
    }
}

// MARK: - Helpers
extension LanguageModelSD {
    var prettyName: String {
        guard let modelName = name.components(separatedBy: ":").first else {
            return name
        }
        
        return modelName.capitalized
    }
    
    var prettyVersion: String {
        let components = name.components(separatedBy: ":")
        if components.count >= 2 {
            return components[1]
        }
        return ""
    }
    
    var supportsImages: Bool {
        if imageSupport {
            return true
        }
        
        /// older technique to detect image modality
        /// @deprecated
        let imageSupportedModels = ["llava"]
        for modelName in imageSupportedModels {
            if name.contains(modelName) {
                return true
            }
        }
        return false
    }
    
    static let sample: [LanguageModelSD] = [
        .init(name: "Llama:latest", modelProvider: .ollama),
        .init(name: "Mistral:latest", modelProvider: .ollama)
    ]
}


// MARK: - @unchecked Sendable
extension LanguageModelSD: @unchecked Sendable {
    /// We hide compiler warnings for concurency. We have to make sure to modify the data only via SwiftDataManager to ensure concurrent operations.
}
