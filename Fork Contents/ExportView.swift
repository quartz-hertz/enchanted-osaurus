//
//  ExportView.swift
//  Enchanted
//
//  Created for Enchanted Fork - Export UI
//

import SwiftUI
import UniformTypeIdentifiers

struct ExportView: View {
    @Environment(\.dismiss) var dismiss
    @State private var isExporting = false
    @State private var exportComplete = false
    @State private var showShareSheet = false
    @State private var exportFileURL: URL?
    @State private var errorMessage: String?
    
    let conversations: [ConversationSD]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "arrow.up.doc")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                    .padding()
                
                Text("Export Conversations")
                    .font(.title2)
                    .bold()
                
                Text("Export all \(conversations.count) conversations to JSON format for Knowledge Base ingestion")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                
                if isExporting {
                    ProgressView("Exporting...")
                        .padding()
                }
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding()
                }
                
                if exportComplete {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Export complete!")
                    }
                    .font(.headline)
                }
                
                Spacer()
                
                Button {
                    Task {
                        await performExport()
                    }
                } label: {
                    Label("Export to Files", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting || conversations.isEmpty)
                .padding(.horizontal)
                
                Button("Cancel") {
                    dismiss()
                }
                .padding(.bottom)
            }
            .padding()
            .sheet(isPresented: $showShareSheet) {
                if let url = exportFileURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }
    
    @MainActor
    private func performExport() async {
        isExporting = true
        errorMessage = nil
        exportComplete = false
        
        do {
            // Fetch all messages for all conversations
            let messagesDict = try await ExportService.shared.fetchAllMessages(conversations: conversations)
            
            // Generate export JSON
            guard let exportData = ExportService.shared.exportAllConversations(
                conversations: conversations,
                messages: messagesDict
            ) else {
                errorMessage = "Failed to generate export data"
                isExporting = false
                return
            }
            
            // Create temporary file
            guard let fileURL = ExportService.shared.createExportFile(data: exportData) else {
                errorMessage = "Failed to create export file"
                isExporting = false
                return
            }
            
            exportFileURL = fileURL
            exportComplete = true
            isExporting = false
            
            // Show share sheet
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
            showShareSheet = true
            
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
            isExporting = false
        }
    }
}

// MARK: - Share Sheet for iOS
#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#elseif os(macOS)
struct ShareSheet: NSViewRepresentable {
    let items: [Any]
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        
        DispatchQueue.main.async {
            guard let url = items.first as? URL else { return }
            
            let picker = NSSavePanel()
            picker.allowedContentTypes = [.json]
            picker.nameFieldStringValue = url.lastPathComponent
            
            picker.begin { response in
                if response == .OK, let saveURL = picker.url {
                    try? FileManager.default.copyItem(at: url, to: saveURL)
                }
            }
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

#Preview {
    ExportView(conversations: [])
}
