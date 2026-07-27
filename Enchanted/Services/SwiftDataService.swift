//
//  SwiftDataService.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 10/12/2023.
//

import Foundation
import SwiftData

final actor SwiftDataService: ModelActor {
    let modelContainer: ModelContainer
    let modelExecutor: ModelExecutor
    private let modelContext: ModelContext
    
    static let shared = SwiftDataService()
    
    init() {
        let sharedModelContainer: ModelContainer = {
            let schema = Schema([
                LanguageModelSD.self,
                ConversationSD.self,
                MessageSD.self,
                CompletionInstructionSD.self
            ])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }()
        
        self.modelContext = ModelContext(sharedModelContainer)
        self.modelContext.autosaveEnabled = false
        modelContainer = sharedModelContainer
        modelExecutor = DefaultSerialModelExecutor(modelContext: modelContext)
    }
}

// MARK: - Language Models
extension SwiftDataService {
    func fetchModels() throws -> [LanguageModelSD] {
        let sortDescriptor = SortDescriptor(\LanguageModelSD.name)
        let fetchDescriptor = FetchDescriptor<LanguageModelSD>(sortBy: [sortDescriptor])
        let models = try modelContext.fetch(fetchDescriptor)
        
        return models
    }
    
    func saveModels(models: [LanguageModelSD]) throws {
        for model in models {
            modelContext.insert(model)
        }
        
        try modelContext.saveChanges()
    }
    
    func deleteModels() throws {
        try modelContext.delete(model: LanguageModelSD.self)
        try modelContext.saveChanges()
    }
}

// MARK: - Agent Models
extension SwiftDataService {
    /// Fetch-or-create guard for agent `LanguageModelSD` rows.
    ///
    /// Agents are persisted as first-class `LanguageModelSD` rows with
    /// `modelProvider == .osaurus`, `isAgent == true`, and a stored
    /// `agentAddress`. This method always returns a managed object that lives
    /// in this `ModelContext`, so a transient wrapper can never collide with
    /// an existing managed row. If a row with the same unique `name` already
    /// exists, its mutable fields are refreshed in place; otherwise a new row
    /// is inserted. This mirrors the "save then fetch back" Ollama path, but
    /// with an explicit existence check so repeated loads never produce a
    /// duplicate / unique-constraint collision.
    func fetchOrCreateAgentModel(name: String, agentAddress: String, imageSupport: Bool) throws -> LanguageModelSD {
        let nameToFind = name
        let predicate = #Predicate<LanguageModelSD> { $0.name == nameToFind }
        let fetchDescriptor = FetchDescriptor<LanguageModelSD>(predicate: predicate)
        
        if let existing = try modelContext.fetch(fetchDescriptor).first {
            // Refresh mutable fields in case the agent's address or vision
            // support changed since the last run (e.g. an Ethereum address was
            // added, or the agent was reconfigured).
            existing.agentAddress = agentAddress
            existing.imageSupport = imageSupport
            existing.isAgent = true
            existing.modelProvider = .osaurus
            try modelContext.saveChanges()
            return existing
        }
        
        let model = LanguageModelSD(
            name: name,
            imageSupport: imageSupport,
            modelProvider: .osaurus,
            isAgent: true,
            agentAddress: agentAddress
        )
        modelContext.insert(model)
        try modelContext.saveChanges()
        return model
    }
    
    /// Delete all agent models (rows where `isAgent == true`). Ollama rows
    /// are left untouched. Useful for purging agents that no longer appear in
    /// the Osaurus /agents list.
    func deleteAgentModels() throws {
        let predicate = #Predicate<LanguageModelSD> { $0.isAgent == true }
        try modelContext.delete(model: LanguageModelSD.self, where: predicate)
        try modelContext.saveChanges()
    }
}

// MARK: - Conversations
extension SwiftDataService {
    func createConversation(_ conversation: ConversationSD) throws {
        self.modelContext.insert(conversation)
        try modelContext.saveChanges()
    }
    
    func renameConversation(_ conversation: ConversationSD) throws {
        try modelContext.saveChanges()
    }
    
    func deleteConversation(_ conversation: ConversationSD) throws {
        self.modelContext.delete(conversation)
        try modelContext.saveChanges()
    }
    
    func updateConversation(_ conversation: ConversationSD) throws {
        // The conversation object passed in might be from a different context,
        // so fetch the one that lives in THIS context and update it by id.
        let convId = conversation.id
        
        let predicate = #Predicate<ConversationSD>{ conv in
            conv.id == convId
        }
        let fetchDescriptor = FetchDescriptor<ConversationSD>(predicate: predicate)
        
        guard let contextConversation = try modelContext.fetch(fetchDescriptor).first else {
            return
        }
        
        contextConversation.updatedAt = .now
        try modelContext.saveChanges()
    }
    
    func updateConversationById(_ conversationId: UUID, model: LanguageModelSD?) throws {
        let convId = conversationId
        let predicate = #Predicate<ConversationSD>{ conv in
            conv.id == convId
        }
        let fetchDescriptor = FetchDescriptor<ConversationSD>(predicate: predicate)
        
        guard let conversation = try modelContext.fetch(fetchDescriptor).first else {
            return
        }
        
        conversation.updatedAt = .now
        if let model = model {
            conversation.model = model
        }
        
        try modelContext.saveChanges()
    }
    
    func fetchConversations() throws -> [ConversationSD] {
        let sortDescriptor = SortDescriptor(\ConversationSD.updatedAt, order: .reverse)
        let fetchDescriptor = FetchDescriptor<ConversationSD>(sortBy: [sortDescriptor])
        return try modelContext.fetch(fetchDescriptor)
    }
    
    func getConversation(_ conversationId: UUID) throws -> ConversationSD? {
        let idToFind = conversationId
        let predicate = #Predicate<ConversationSD>{ conversation in
            conversation.id == idToFind
        }
        let fetchDescriptor = FetchDescriptor<ConversationSD>(predicate: predicate)
        return try modelContext.fetch(fetchDescriptor).first
    }
    
    func deleteConversations() throws {
        try modelContext.delete(model: ConversationSD.self)
        try modelContext.saveChanges()
    }
    
    func deleteMessages() throws {
        try modelContext.delete(model: MessageSD.self)
        try modelContext.saveChanges()
    }
    
    /// Delete conversations created on the given calendar day.
    func deleteConversations(_ date: Date) throws {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        let start = startOfDay
        let end = endOfDay
        let predicate = #Predicate<ConversationSD>{ conversation in
            conversation.createdAt >= start && conversation.createdAt < end
        }
        try modelContext.delete(model: ConversationSD.self, where: predicate)
        try modelContext.saveChanges()
    }
}


// MARK: - Messages
extension SwiftDataService {
    func fetchMessages(_ conversationId: UUID) throws -> [MessageSD] {
        let idToFind = conversationId
        let predicate = #Predicate<MessageSD>{ message in
            message.conversation?.id == idToFind
        }
        let sortDescriptor = SortDescriptor(\MessageSD.createdAt)
        let fetchDescriptor = FetchDescriptor<MessageSD>(predicate: predicate, sortBy: [sortDescriptor])
        let messages = try modelContext.fetch(fetchDescriptor)
        
        return messages
    }
    
    func updateMessage(_ message: MessageSD) throws {
        try modelContext.saveChanges()
    }
    
    func createMessage(_ message: MessageSD) throws {
        // Ensure the message's conversation points at the copy that lives in
        // THIS context so the relationship wires up correctly on insert.
        if let conv = message.conversation {
            let convId = conv.id
            let predicate = #Predicate<ConversationSD>{ conversation in
                conversation.id == convId
            }
            let fetchDescriptor = FetchDescriptor<ConversationSD>(predicate: predicate)
            if let contextConversation = try modelContext.fetch(fetchDescriptor).first {
                message.conversation = contextConversation
            }
        }
        
        self.modelContext.insert(message)
        try modelContext.saveChanges()
    }
}

// MARK: - CompletionInstruction
extension SwiftDataService {
    func fetchCompletionInstructions() throws -> [CompletionInstructionSD] {
        let sortDescriptor = SortDescriptor(\CompletionInstructionSD.order, order: .forward)
        let fetchDescriptor = FetchDescriptor<CompletionInstructionSD>(sortBy: [sortDescriptor])
        return try modelContext.fetch(fetchDescriptor)
    }
    
    func updateCompletionInstructions(_ instructions: [CompletionInstructionSD]) throws {
        for index in instructions.indices {
            instructions[index].order = index
            modelContext.insert(instructions[index])
        }
        try modelContext.saveChanges()
    }
    
    func deleteCompletionInstruction(_ instruction: CompletionInstructionSD) throws {
        self.modelContext.delete(instruction)
        try modelContext.saveChanges()
    }
}

// MARK: - General
extension SwiftDataService {
    func deleteEverything() throws {
        try modelContext.delete(model: ConversationSD.self)
        try modelContext.delete(model: LanguageModelSD.self)
        try modelContext.delete(model: MessageSD.self)
        try modelContext.delete(model: CompletionInstructionSD.self)
        try modelContext.saveChanges()
    }
}
