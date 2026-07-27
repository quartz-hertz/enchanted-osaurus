//
//  LanguageModel.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 12/05/2024.
//

import Foundation

struct LanguageModel {
    var name: String
    var provider: ModelProvider
    var imageSupport: Bool
}

enum ModelProvider: Codable {
    case ollama
    /// Osaurus agent exposed via the /agents endpoint. Agent models are
    /// persisted as first-class `LanguageModelSD` rows with this provider.
    case osaurus
}
