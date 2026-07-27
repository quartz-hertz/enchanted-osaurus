//
//  AgentAddressSettingsView.swift
//  Enchanted
//
//  UI for managing agent Ethereum addresses for E2EE
//

import SwiftUI

struct AgentAddressSettingsView: View {
    @State private var agentAddresses: [String: String] = [:]
    @State private var agents: [OsaurusAgent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        Form {
            Section {
                Text("Configure Ethereum addresses for each agent to enable end-to-end encryption (E2EE).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("You can find each agent's relay address in Osaurus → Agent Settings → Network → Relay.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading agents...")
                    }
                }
            } else if agents.isEmpty {
                Section {
                    Button("Load Agents") {
                        loadAgents()
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            } else {
                Section("Agent Ethereum Addresses") {
                    ForEach(agents) { (agent: OsaurusAgent) in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(agent.name)
                                .font(.headline)
                            
                            Text("UUID: \(agent.id)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                TextField("0x...", text: Binding(
                                    get: { agentAddresses[agent.id] ?? "" },
                                    set: { newValue in
                                        agentAddresses[agent.id] = newValue
                                        saveAddresses()
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .disableAutocorrection(true)
                                #if os(iOS)
                                .autocapitalization(.none)
                                .keyboardType(.asciiCapable)
                                #endif
                                
                                if let address = agentAddresses[agent.id], isValidEthereumAddress(address) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section {
                    Button("Clear All Addresses") {
                        agentAddresses.removeAll()
                        saveAddresses()
                    }
                    .foregroundColor(.red)
                }
            }
            
            Section("Instructions") {
                Text("1. Load agents from your Osaurus server")
                Text("2. For each agent, go to Osaurus → Agent → Network → Enable Relay")
                Text("3. Copy the relay address (0x...)")
                Text("4. Paste it here")
                Text("5. E2EE will automatically activate for agents with addresses")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .navigationTitle("Agent E2EE Settings")
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .onAppear {
            loadSavedAddresses()
        }
    }
    
    private func loadAgents() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // Configure service with current settings
                if let ollamaUri = UserDefaults.standard.string(forKey: "ollamaUri"),
                   let baseURL = URL(string: ollamaUri) {
                    let bearerToken = UserDefaults.standard.string(forKey: "ollamaBearerToken")
                    AgentService.shared.configure(baseURL: baseURL, bearerToken: bearerToken)
                }
                
                let fetchedAgents = try await AgentService.shared.fetchAgents()
                
                await MainActor.run {
                    self.agents = fetchedAgents
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func loadSavedAddresses() {
        if let saved = UserDefaults.standard.dictionary(forKey: "agentEthereumAddresses") as? [String: String] {
            agentAddresses = saved
        }
    }
    
    private func saveAddresses() {
        // Filter out empty addresses
        let filtered = agentAddresses.filter { !$0.value.isEmpty }
        UserDefaults.standard.set(filtered, forKey: "agentEthereumAddresses")
        
        // Trigger agent reload to pick up new addresses
        NotificationCenter.default.post(name: NSNotification.Name("AgentAddressesUpdated"), object: nil)
        
        print("💾 Saved \(filtered.count) agent address(es)")
    }
    
    private func isValidEthereumAddress(_ address: String) -> Bool {
        // Check format: 0x followed by 40 hex characters
        let pattern = "^0x[a-fA-F0-9]{40}$"
        return address.range(of: pattern, options: .regularExpression) != nil
    }
}

#Preview {
    NavigationStack {
        AgentAddressSettingsView()
    }
}
