//
//  OsaurusServerConfig.swift
//  Enchanted
//
//  Server configuration with SecureChannelPeer conformance
//

import Foundation

/// Server connection configuration
struct OsaurusServerConfig: Codable, Identifiable, Sendable {
    let id: UUID
    let baseURL: URL
    let bearerToken: String?
    
    /// Pinned agent address for TOFU (Trust On First Use)
    /// Set when we first discover the agent's 0x… address from GET /agents
    var pinnedAgentAddress: String?
    
    init(id: UUID = UUID(), baseURL: URL, bearerToken: String?, pinnedAgentAddress: String? = nil) {
        self.id = id
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        self.pinnedAgentAddress = pinnedAgentAddress
    }
}

// MARK: - SecureChannelPeer Conformance

extension OsaurusServerConfig: SecureChannelPeer {
    var remoteAgentAddress: String? {
        pinnedAgentAddress
    }
    
    func url(for path: String) -> URL? {
        URL(string: path, relativeTo: baseURL)?.absoluteURL
    }
}
