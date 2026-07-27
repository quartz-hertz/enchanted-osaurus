//
//  ExportService.swift
//  Enchanted
//
//  Created for Enchanted Fork - Export feature
//

import Foundation
import SwiftUI

/// Service for exporting conversations to KB-compatible JSON format
@MainActor
class ExportService {
    static let shared = ExportService()
    
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    private init() {}
    
    /// Export all conversations to JSON format
    func exportAllConversations(conversations: [ConversationSD], messages: [UUID: [MessageSD]]) -> Data? {
        let exportedConversations = conversations.compactMap { conversation -> ExportedConversation? in
            guard let conversationMessages = messages[conversation.id] else {
                return nil
            }
            
            return ExportedConversation(
                platformId: conversation.id.uuidString,
                title: conversation.name,
                createdAt: dateFormatter.string(from: conversation.createdAt),
                updatedAt: dateFormatter.string(from: conversation.updatedAt),
                model: conversation.model?.name,
                agentId: conversation.agentId,  // Will be nil for non-agent conversations
                messageCount: conversationMessages.count,
                messages: conversationMessages.map { message in
                    ExportedMessage(
                        role: message.role,
                        content: message.content,
                        timestamp: dateFormatter.string(from: message.createdAt),
                        hasImage: message.image != nil
                    )
                }
            )
        }
        
        let export = ConversationExport(
            exportDate: dateFormatter.string(from: Date()),
            exportVersion: "1.0",
            conversations: exportedConversations
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        
        return try? encoder.encode(export)
    }
    
    /// Get all messages for all conversations (helper for export)
    func fetchAllMessages(conversations: [ConversationSD]) async throws -> [UUID: [MessageSD]] {
        var messagesDict: [UUID: [MessageSD]] = [:]
        
        for conversation in conversations {
            let messages = try await SwiftDataService.shared.fetchMessages(conversation.id)
            messagesDict[conversation.id] = messages
        }
        
        return messagesDict
    }
    
    /// Create a shareable file URL for the export
    func createExportFile(data: Data) -> URL? {
        let timestamp = Date().timeIntervalSince1970
        let filename = "enchanted-export-\(Int(timestamp)).json"
        
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
        let fileURL = temporaryDirectoryURL.appendingPathComponent(filename)
        
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("Failed to write export file: \(error)")
            return nil
        }
    }
}
