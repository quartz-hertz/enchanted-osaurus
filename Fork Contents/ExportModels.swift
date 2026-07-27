//
//  ExportModels.swift
//  Enchanted
//
//  Created for Enchanted Fork - Export feature
//

import Foundation

/// Root structure for exporting all conversations
struct ConversationExport: Codable {
    let exportDate: String // ISO8601
    let exportVersion: String
    let conversations: [ExportedConversation]
}

/// Individual conversation export format
struct ExportedConversation: Codable {
    let platformId: String  // UUID as string
    let title: String?
    let createdAt: String   // ISO8601
    let updatedAt: String   // ISO8601
    let model: String?
    let agentId: String?    // For agent conversations
    let messageCount: Int
    let messages: [ExportedMessage]
}

/// Message export format
struct ExportedMessage: Codable {
    let role: String
    let content: String
    let timestamp: String?  // ISO8601, can be null
    let hasImage: Bool
}
