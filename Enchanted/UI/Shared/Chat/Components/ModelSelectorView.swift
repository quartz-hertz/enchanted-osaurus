//
//  ModelSelector.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 11/12/2023.
//

import SwiftUI

struct ModelSelectorView: View {
    var modelsList: [LanguageModelSD]
    var selectedModel: LanguageModelSD?
    var onSelectModel: @MainActor (_ model: LanguageModelSD?) -> ()
    var showChevron = true
    
    var body: some View {
        Menu {
            ForEach(modelsList, id: \.self) { model in
                Button(action: {
                    withAnimation(.easeOut) {    
                        onSelectModel(model)
                    }
                }) {
                    HStack {
                        // Show agent icon if this is an agent
                        if model.isAgent {
                            Image(systemName: "person.badge.key.fill")
                                .foregroundStyle(.blue)
                        }
                        Text(model.displayName)
                            .font(.body)
                    }
                    .tag(model.name)
                }
            }
        } label: {
            HStack(alignment: .center) {
                if let selectedModel = selectedModel {
                    HStack(alignment: .bottom, spacing: 5) {
                        
                        // Show agent icon if selected model is an agent
                        if selectedModel.isAgent {
                            Image(systemName: "person.badge.key.fill")
                                .foregroundStyle(.blue)
                                .font(.caption)
                        }
                        
                        #if os(macOS) || os(visionOS)
                        Text(selectedModel.displayName)
                            .font(.body)
                        #elseif os(iOS)
                        // For agents, show full name; for models, show pretty name
                        if selectedModel.isAgent {
                            Text(selectedModel.displayName)
                                .font(.body)
                                .foregroundColor(Color.labelCustom)
                        } else {
                            Text(selectedModel.prettyName)
                                .font(.body)
                                .foregroundColor(Color.labelCustom)
                            
                            Text(selectedModel.prettyVersion)
                                .font(.subheadline)
                                .foregroundColor(Color.gray3Custom)
                        }
                        #endif
                    }
                }
                
                Image(systemName: "chevron.down")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 10)
                    .foregroundColor(Color(.label))
                    .showIf(showChevron)
            }
        }
    }
}

#Preview {
    ModelSelectorView(
        modelsList: LanguageModelSD.sample,
        selectedModel: LanguageModelSD.sample[0], 
        onSelectModel: {_ in},
        showChevron: false
    )
}
