//
//  AgentBadge.swift
//  Enchanted
//
//  Created for Enchanted Fork - Visual distinction for agents
//

import SwiftUI

/// Badge to show when a model is actually an agent
struct AgentBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.badge.key.fill")
            Text("Agent")
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundStyle(.blue)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.blue.opacity(0.1))
        .clipShape(Capsule())
    }
}

/// Small inline icon for agents
struct AgentIcon: View {
    var body: some View {
        Image(systemName: "person.badge.key.fill")
            .foregroundStyle(.blue)
            .imageScale(.small)
    }
}

/// Display name for a model, with agent indication
struct ModelDisplayName: View {
    let model: LanguageModelSD
    
    var body: some View {
        HStack(spacing: 8) {
            if model.isAgent {
                AgentIcon()
            }
            
            Text(displayName)
                .lineLimit(1)
            
            if model.isAgent {
                Spacer()
                AgentBadge()
            }
        }
    }
    
    @MainActor
    private var displayName: String {
        // Use the extension's displayName property which handles agents properly
        model.displayName
    }
}

/// Row for displaying a model in a list/picker
struct ModelRow: View {
    let model: LanguageModelSD
    let isSelected: Bool
    
    var body: some View {
        HStack {
            ModelDisplayName(model: model)
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Tool progress indicator for agent conversations
struct ToolProgressView: View {
    let progress: String
    
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            
            Text(progress)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Previews

#Preview("Agent Badge") {
    AgentBadge()
}

#Preview("Model Display Name - Regular") {
    ModelDisplayName(model: LanguageModelSD(
        name: "llama3.2",
        imageSupport: false, modelProvider: .ollama
    ))
}

#Preview("Model Display Name - Agent") {
    ModelDisplayName(model: LanguageModelSD(
        name: "agent:research-assistant",
        imageSupport: false, modelProvider: .osaurus,
        isAgent: true,
        agentAddress: "research-assistant"
    ))
}

#Preview("Model Row") {
    VStack {
        ModelRow(
            model: LanguageModelSD(
                name: "llama3.2",
                imageSupport: false, modelProvider: .ollama
            ),
            isSelected: false
        )
        
        ModelRow(
            model: LanguageModelSD(
                name: "agent:research-assistant",
                imageSupport: false, modelProvider: .osaurus,
                isAgent: true,
                agentAddress: "research-assistant"
            ),
            isSelected: true
        )
    }
    .padding()
}

#Preview("Tool Progress") {
    ToolProgressView(progress: "Searching documentation...")
}
