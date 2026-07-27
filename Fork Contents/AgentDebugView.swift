//
//  AgentDebugView.swift
//  Enchanted
//
//  Created for Enchanted Fork - Debug/testing view for agents
//

import SwiftUI

/// Debug view to inspect agent state and test connectivity
struct AgentDebugView: View {
    @State private var agentStore = AgentStore.shared
    @State private var isLoading = false
    @State private var testResult: String?
    
    var body: some View {
        NavigationStack {
            List {
                Section("Configuration") {
                    HStack {
                        Text("Endpoint")
                        Spacer()
                        Text(UserDefaults.standard.string(forKey: "ollamaUri") ?? "Not set")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    
                    HStack {
                        Text("Bearer Token")
                        Spacer()
                        if let token = UserDefaults.standard.string(forKey: "ollamaBearerToken"),
                           !token.isEmpty {
                            Text("Set (\(token.prefix(8))...)")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else {
                            Text("Not set")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                }
                
                Section("Loaded Agents") {
                    if agentStore.agents.isEmpty {
                        Text("No agents loaded")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(agentStore.agents) { agent in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    // Show avatar color if available
                                    if let avatar = agent.avatar {
                                        Circle()
                                            .fill(Color(avatarColor: avatar))
                                            .frame(width: 12, height: 12)
                                    }
                                    AgentIcon()
                                    Text(agent.name)
                                        .font(.headline)
                                    
                                    if agent.isBuiltIn {
                                        Text("Built-in")
                                            .font(.caption2)
                                            .foregroundStyle(.blue)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.1))
                                            .clipShape(Capsule())
                                    }
                                }
                                
                                Text("ID: \(agent.id)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                if !agent.description.isEmpty {
                                    Text(agent.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                HStack {
                                    if agent.supportsVision {
                                        Label("Vision", systemImage: "eye.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                    }
                                    if agent.supportsThinking {
                                        Label("Thinking", systemImage: "brain")
                                            .font(.caption2)
                                            .foregroundStyle(.purple)
                                    }
                                    if agent.memoryEntryCount > 0 {
                                        Label("\(agent.memoryEntryCount) memories", systemImage: "memories")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                }
                                
                                Text("Model: \(agent.effectiveModel)")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                Section {
                    Button {
                        Task {
                            await testAgentDiscovery()
                        }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text("Test Agent Discovery")
                        }
                    }
                    .disabled(isLoading)
                    
                    if let result = testResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(result.contains("✅") ? .green : .red)
                    }
                }
            }
            .navigationTitle("Agent Debug")
            .toolbar {
                Button("Refresh") {
                    Task {
                        await agentStore.loadAgents()
                    }
                }
            }
        }
        .task {
            await agentStore.loadAgents()
        }
    }
    
    @MainActor
    private func testAgentDiscovery() async {
        isLoading = true
        testResult = nil
        
        // Configure service
        if let ollamaUri = UserDefaults.standard.string(forKey: "ollamaUri"),
           let baseURL = URL(string: ollamaUri) {
            let bearerToken = UserDefaults.standard.string(forKey: "ollamaBearerToken")
            AgentService.shared.configure(baseURL: baseURL, bearerToken: bearerToken)
            
            do {
                let agents = try await AgentService.shared.fetchAgents()
                testResult = "✅ Found \(agents.count) agent(s)"
                agentStore.agents = agents
            } catch {
                testResult = "❌ Error: \(error.localizedDescription)"
            }
        } else {
            testResult = "❌ Endpoint not configured"
        }
        
        isLoading = false
    }
}

/// Quick inspector for current conversation
struct ConversationDebugView: View {
    let conversation: ConversationSD?
    
    var body: some View {
        Group {
            if let conversation = conversation {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Conversation Debug")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    
                    DebugRow(label: "ID", value: conversation.id.uuidString)
                    DebugRow(label: "Name", value: conversation.name)
                    DebugRow(label: "Model", value: conversation.model?.name ?? "nil")
                    DebugRow(label: "Agent ID", value: conversation.agentId ?? "nil")
                    DebugRow(label: "Is Agent", value: conversation.isAgentConversation ? "Yes" : "No")
                    DebugRow(label: "Messages", value: "\(conversation.messages.count)")
                    DebugRow(label: "Created", value: conversation.createdAt.formatted())
                    DebugRow(label: "Updated", value: conversation.updatedAt.formatted())
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .font(.caption)
            }
        }
    }
}

struct DebugRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .fontWeight(.semibold)
            Text(value)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - Color Extension for Avatar
extension Color {
    init(avatarColor: String) {
        switch avatarColor.lowercased() {
        case "blue":
            self = .blue
        case "yellow":
            self = .yellow
        case "red":
            self = .red
        case "green":
            self = .green
        case "purple":
            self = .purple
        case "orange":
            self = .orange
        case "pink":
            self = .pink
        default:
            self = .gray
        }
    }
}

#Preview("Agent Debug") {
    AgentDebugView()
}

#Preview("Conversation Debug") {
    ConversationDebugView(conversation: nil)
}
