//
//  ChatsStore.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 10/12/2023.
//

import Foundation
import SwiftData
import OllamaKit
import Combine
import SwiftUI

@Observable
final class ConversationStore: Sendable {
    static let shared = ConversationStore(swiftDataService: SwiftDataService.shared)
    
    private var swiftDataService: SwiftDataService
    private var generation: AnyCancellable?
    
    /// For some reason (SwiftUI bug / too frequent UI updates) updating UI for each stream message sometimes freezes the UI.
    /// Throttling UI updates seem to fix the issue.
    private var currentMessageBuffer: String = ""
#if os(macOS)
    private let throttler = Throttler(delay: 0.1)
#else
    private let throttler = Throttler(delay: 0.1)
#endif
    
    @MainActor var conversationState: ConversationState = .completed
    @MainActor var conversations: [ConversationSD] = []
    @MainActor var selectedConversation: ConversationSD?
    @MainActor var messages: [MessageSD] = []
    
    /// Messages created during the current `sendPrompt` call that have not yet
    /// been written to the database. They are persisted in
    /// `handleComplete`/`handleError` AFTER streaming finishes, so the assistant
    /// message is inserted with its final, fully-streamed content. Persisting
    /// them earlier would insert the assistant empty and then mutate it
    /// off-context, where SwiftData would never see the changes.
    @MainActor var pendingNewMessages: [MessageSD] = []
    
    init(swiftDataService: SwiftDataService) {
        self.swiftDataService = swiftDataService
    }
    
    func loadConversations() async throws {
        let fetchedConversations = try await swiftDataService.fetchConversations()
        await MainActor.run {
            self.conversations = fetchedConversations
        }
    }
    
    func deleteAllConversations() {
        Task {
            await MainActor.run { [weak self] in
                self?.messages = []
                self?.selectedConversation = nil
            }
            try? await swiftDataService.deleteConversations()
            try? await swiftDataService.deleteMessages()
            try? await loadConversations()
        }
    }
    
    func deleteDailyConversations(_ date: Date) {
        Task {
            await MainActor.run { [weak self] in
                self?.selectedConversation = nil
                self?.messages = []
            }
            // Use the date-scoped overload so we only delete conversations from that day.
            try? await swiftDataService.deleteConversations(date)
            try? await loadConversations()
        }
    }
    
    func create(_ conversation: ConversationSD) async throws {
        try await swiftDataService.createConversation(conversation)
    }
    
    func reloadConversation(_ conversation: ConversationSD) async throws {
        let (fetchedMessages, fetchedConversation) = try await (
            swiftDataService.fetchMessages(conversation.id),
            swiftDataService.getConversation(conversation.id)
        )
        await MainActor.run {
            self.messages = fetchedMessages
            self.selectedConversation = fetchedConversation
        }
    }
    
    func selectConversation(_ conversation: ConversationSD) async throws {
        try await reloadConversation(conversation)
    }
    
    func delete(_ conversation: ConversationSD) async throws {
        try await swiftDataService.deleteConversation(conversation)
        let fetchedConversations = try await swiftDataService.fetchConversations()
        await MainActor.run {
            self.selectedConversation = nil
            self.conversations = fetchedConversations
        }
    }
    
    @MainActor func stopGenerate() {
        generation?.cancel()
        handleComplete()
        withAnimation {
            conversationState = .completed
        }
    }
    
    @MainActor
    func sendPrompt(userPrompt: String, model: LanguageModelSD, image: Image? = nil, systemPrompt: String = "", trimmingMessageId: String? = nil) {
        guard userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 else { return }
        
        let conversation = selectedConversation ?? ConversationSD(name: userPrompt)
        conversation.updatedAt = Date.now
        conversation.model = model
        
        // If this is a new conversation, set it as selected immediately AND clear old messages
        if selectedConversation == nil {
            selectedConversation = conversation
            messages = []
        }
        
        /// trim conversation if on edit mode
        if let trimmingMessageId = trimmingMessageId {
            messages = Array(
                messages
                    .sorted { $0.createdAt < $1.createdAt }
                    .prefix(while: { $0.id.uuidString != trimmingMessageId })
            )
        }
        
        // Track only the messages created in this call. They are persisted after
        // streaming completes (see handleComplete/handleError). We deliberately do
        // NOT persist them here, because the assistant placeholder is empty at
        // this point and would be mutated off-context during streaming.
        pendingNewMessages = []
        
        /// add system prompt to very first message in the conversation.
        /// IMPORTANT: append to `messages` (the in-memory source of truth) too,
        /// otherwise it never gets persisted and never gets sent to stateless agents.
        if !systemPrompt.isEmpty && messages.isEmpty {
            let systemMessage = MessageSD(content: systemPrompt, role: "system")
            systemMessage.conversation = conversation
            messages.append(systemMessage)
            pendingNewMessages.append(systemMessage)
        }
        
        /// construct new user message. `compressImageData()` now produces a
        /// high-fidelity JPEG (max 1568px longest side, q0.85) — the same image
        /// that gets stored on `MessageSD.image` and re-transmitted to stateless
        /// agents on follow-up turns, so the current turn and every later turn
        /// see the same high-quality image.
        let userMessage = MessageSD(content: userPrompt, role: "user", image: image?.render()?.compressImageData())
        userMessage.conversation = conversation
        messages.append(userMessage)
        pendingNewMessages.append(userMessage)
        
        /// construct assistant placeholder. It stays empty in memory until the
        /// stream fills it in; it is inserted into the database with its final
        /// content in handleComplete().
        let assistantMessage = MessageSD(content: "", role: "assistant")
        assistantMessage.conversation = conversation
        messages.append(assistantMessage)
        pendingNewMessages.append(assistantMessage)
        
        /// Build the outgoing history ONCE, from `messages`, EXCLUDING the empty
        /// assistant placeholder (the last element). This is the single source of
        /// truth used by both the Ollama and the agent paths, so they behave the
        /// same. For stateless (E2EE) agents this includes the system prompt and
        /// the full prior history every time — no DB reload required, because the
        /// in-memory `messages` array already has everything.
        ///
        /// Images are re-attached from `MessageSD.image` on every turn. This is
        /// required for stateless (E2EE) agents, which forget everything between
        /// calls — without re-transmission, a follow-up question about an image
        /// sent earlier would reach the agent with no image in context. It's
        /// also correct for Ollama's per-request `/api/chat`: each request is
        /// self-contained, so prior images must travel with their messages.
        ///
        /// The current turn's image is the same high-fidelity JPEG stored on the
        /// just-created user message (via `compressImageData()`), so there's no
        /// separate full-quality override — turn 1 and turn N see identical
        /// image bytes.
        let messageHistory: [OKChatRequestData.Message] = messages.dropLast()
            .sorted { $0.createdAt < $1.createdAt }
            .map { message in
                // `MessageSD.image` already holds the high-fidelity JPEG written
                // at creation time via `compressImageData()`. Base64-encode it for
                // the Ollama `images` field; `sendAgentPrompt` converts that into
                // OpenAI `image_url` data-URI parts for the agent path.
                let images: [String] = message.image.map { [$0.base64EncodedString()] } ?? []
                return OKChatRequestData.Message(
                    role: OKChatRequestData.Message.Role(rawValue: message.role) ?? .assistant,
                    content: message.content,
                    images: images
                )
            }
        
        conversationState = .loading
        
        let isAgent = model.isAgent
        let agentAddress = model.agentAddress
        let modelName = model.name
        
        Task {
            if isAgent, let agentAddress = agentAddress {
                await sendAgentPrompt(agentAddress: agentAddress, messageHistory: messageHistory)
            } else {
                if await OllamaService.shared.ollamaKit.reachable() {
                    DispatchQueue.global(qos: .background).async {
                        var request = OKChatRequestData(model: modelName, messages: messageHistory)
                        request.options = OKCompletionOptions(temperature: 0)
                        
                        self.generation = OllamaService.shared.ollamaKit.chat(data: request)
                            .sink(receiveCompletion: { [weak self] completion in
                                Task { @MainActor [weak self] in
                                    switch completion {
                                    case .finished:
                                        self?.handleComplete()
                                    case .failure(let error):
                                        self?.handleError(error.localizedDescription)
                                    }
                                }
                            }, receiveValue: { [weak self] response in
                                Task { @MainActor [weak self] in
                                    self?.handleReceive(response)
                                }
                            })
                    }
                } else {
                    self.handleError("Server unreachable")
                }
            }
        }
    }
    
    @MainActor
    private func handleReceive(_ response: OKChatResponse) {
        if messages.isEmpty { return }
        
        if let responseContent = response.message?.content {
            currentMessageBuffer = currentMessageBuffer + responseContent
            
            throttler.throttle { [weak self] in
                guard let self = self else { return }
                let lastIndex = self.messages.count - 1
                self.messages[lastIndex].content.append(currentMessageBuffer)
                currentMessageBuffer = ""
            }
        }
    }
    
    @MainActor
    private func sendAgentPrompt(agentAddress: String, messageHistory: [OKChatRequestData.Message]) async {
        if let ollamaUri = UserDefaults.standard.string(forKey: "ollamaUri"),
           let baseURL = URL(string: ollamaUri) {
            let bearerToken = UserDefaults.standard.string(forKey: "ollamaBearerToken")
            AgentService.shared.configure(baseURL: baseURL, bearerToken: bearerToken)
        }
        
        // Convert Ollama-style messages to OpenAI Chat Completions format.
        // Text-only messages get a plain string `content`; messages with images
        // get an OpenAI content array with `text` and `image_url` parts. The
        // Osaurus agent run endpoint speaks OpenAI format (its streaming
        // responses use `choices`/`delta`), so images must travel as
        // `image_url` data URIs — not the Ollama `images` field, which the
        // endpoint silently ignores.
        let agentMessages = messageHistory.map { msg in
            AgentMessage(role: msg.role.rawValue, text: msg.content, images: msg.images)
        }
        
        let imageCount = messageHistory.reduce(0) { $0 + ($1.images.count) }
        if imageCount > 0 {
            print("🖼️ Sending \(imageCount) image(s) to agent as OpenAI image_url content parts (incl. re-transmitted history)")
        }
        
        currentMessageBuffer = ""
        
        self.generation = AgentService.shared.runAgent(address: agentAddress, messages: agentMessages)
            .sink(receiveCompletion: { [weak self] completion in
                Task { @MainActor [weak self] in
                    switch completion {
                    case .finished:
                        self?.handleComplete()
                    case .failure(let error):
                        self?.handleError(error.localizedDescription)
                    }
                }
            }, receiveValue: { [weak self] response in
                Task { @MainActor [weak self] in
                    self?.handleAgentReceive(response)
                }
            })
    }
    
    @MainActor
    private func handleAgentReceive(_ response: AgentRunResponse) {
        if messages.isEmpty { return }
        
        // Handle content from either format (Osaurus or OpenAI)
        if let content = response.content, !content.isEmpty {
            currentMessageBuffer = currentMessageBuffer + content
            
            throttler.throttle { [weak self] in
                guard let self = self else { return }
                guard !self.messages.isEmpty else { return }
                let lastIndex = self.messages.count - 1
                self.messages[lastIndex].content = self.currentMessageBuffer
            }
        }
        
        // Handle tool progress hints (Osaurus format only)
        if let toolProgress = response.message?.toolProgress {
            let annotation = "[tool call: \(toolProgress)]"
            
            throttler.throttle { [weak self] in
                guard let self = self else { return }
                guard !self.messages.isEmpty else { return }
                let lastIndex = self.messages.count - 1
                if !self.messages[lastIndex].content.contains(annotation) {
                    self.messages[lastIndex].content.append("\n\(annotation)")
                }
            }
        }
    }
    
    /// Persist the conversation (if new) and any messages created during the
    /// current `sendPrompt` call. Called from `handleComplete` and `handleError`
    /// after streaming has finished, so the assistant message is inserted with
    /// its final content.
    @MainActor
    private func persistPendingMessages() {
        let conversationToSave = selectedConversation
        let messagesToSave = pendingNewMessages
        
        // Clear now (synchronously, on MainActor) so a subsequent sendPrompt can't
        // race with the background save below. The Task captures messagesToSave.
        pendingNewMessages = []
        
        Task(priority: .background) {
            do {
                if let conv = conversationToSave {
                    let existsInDb = try await self.swiftDataService.getConversation(conv.id) != nil
                    if !existsInDb {
                        try await self.swiftDataService.createConversation(conv)
                    }
                    for message in messagesToSave {
                        try await self.swiftDataService.createMessage(message)
                    }
                    try await self.swiftDataService.updateConversation(conv)
                }
            } catch {
                print("❌ Error persisting messages: \(error)")
            }
            
            // Refresh the sidebar so the new/updated conversation appears.
            try? await self.loadConversations()
        }
    }
    
    @MainActor
    private func handleError(_ errorMessage: String) {
        guard let lastMessage = messages.last else {
            withAnimation {
                conversationState = .error(message: errorMessage)
            }
            return
        }
        
        lastMessage.error = true
        lastMessage.done = false
        
        // Even on error, persist what we have so the conversation + user message
        // (and any partial assistant reply) aren't lost.
        persistPendingMessages()
        
        withAnimation {
            conversationState = .error(message: errorMessage)
        }
    }
    
    @MainActor
    private func handleComplete() {
        guard let lastMessage = messages.last else {
            withAnimation {
                conversationState = .completed
            }
            return
        }
        
        // Finalize the assistant message. It was created empty in sendPrompt and
        // filled during streaming; persistPendingMessages() inserts it (and any
        // other new messages) now, capturing its final content at insert time.
        lastMessage.error = false
        lastMessage.done = true
        
        persistPendingMessages()
        
        withAnimation {
            conversationState = .completed
        }
    }
}
