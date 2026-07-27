//
//  ExportButton.swift
//  Enchanted
//
//  Created for Enchanted Fork - Export button for Settings/Menu
//

import SwiftUI

/// Button to trigger conversation export
struct ExportButton: View {
    let conversations: [ConversationSD]
    @State private var showExport = false
    
    var body: some View {
        Button {
            showExport = true
        } label: {
            Label("Export Conversations", systemImage: "square.and.arrow.up")
        }
        .sheet(isPresented: $showExport) {
            ExportView(conversations: conversations)
        }
    }
}

/// For use in toolbar/navigation
struct ExportToolbarButton: View {
    let conversations: [ConversationSD]
    @State private var showExport = false
    
    var body: some View {
        Button {
            showExport = true
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .sheet(isPresented: $showExport) {
            ExportView(conversations: conversations)
        }
    }
}
