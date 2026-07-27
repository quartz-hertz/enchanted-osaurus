# Osaurus 0.21.1 E2EE Compatibility Note

## Issue Discovered

**Osaurus 0.21.1 uses UUIDs for agent identifiers, not Ethereum addresses.**

### What We Expected (per Secure Channel spec)
- Agents have `0x...` Ethereum addresses (42-char hex strings)
- These addresses are derived from secp256k1 public keys
- The secure channel verifies the server's signature against this address

### What Osaurus 0.21.1 Actually Returns
```json
{
  "agents": [
    {
      "id": "048746B9-1167-4337-B05A-888A10ADC0A2",  // ← UUID, not 0x...
      "name": "Agent Name",
      ...
    }
  ]
}
```

The `id` field is a UUID, not an Ethereum address. The secure channel **cannot work** with UUIDs because:
1. The handshake signature is made with a secp256k1 key
2. Address recovery (ecrecover) produces a 0x... address
3. We need to match that address to verify the server's identity

## Current Behavior

With this fix:
- ✅ Agents load successfully
- ✅ Agents without `0x...` addresses fall back to **plaintext mode**
- ℹ️ E2EE is **not available** for UUID-based agents
- ⚠️ If server requires E2EE (426), it will fail until agents have proper addresses

Console output:
```
ℹ️ Agent AgentName has no Ethereum address (UUID: 048746B9-...) - E2EE not available
✅ Loaded 3 agents (0 support E2EE)
📡 No Ethereum addresses - E2EE not available (Osaurus 0.21.1 uses UUIDs)
📡 Using plaintext for agent 048746B9-...
🤖 HTTP Status: 426
```

## Solutions

### Option 1: Upgrade Osaurus (Recommended)
Check if a newer version of Osaurus includes `agent_address` in the API response:

```json
{
  "agents": [
    {
      "id": "048746B9-1167-4337-B05A-888A10ADC0A2",
      "agent_address": "0xdef456...",  // ← New field
      "name": "Agent Name",
      ...
    }
  ]
}
```

The code already looks for this field and will automatically use it if present.

### Option 2: Disable E2EE on Server
If you don't need E2EE (e.g., on a private Tailscale network):

**In Osaurus settings/config:**
- Disable the secure channel requirement
- Agents will work in plaintext mode
- WireGuard already encrypts the Tailscale tunnel

### Option 3: Manual Address Mapping (Not Recommended)
You could manually map UUIDs to Ethereum addresses, but this defeats the TOFU security model.

## Code Changes Made

### `AgentModels.swift`
Added support for optional `agent_address` field:
```swift
let agentAddress: String?  // Ethereum address (0x...)

var ethereumAddress: String? {
    if let addr = agentAddress, addr.hasPrefix("0x") && addr.count == 42 {
        return addr
    }
    return nil
}
```

### `AgentStore.swift`
Only pins Ethereum addresses:
```swift
func pinAgentAddress(_ address: String, forAgent agentId: String) {
    // Don't pin UUIDs - only Ethereum addresses
    guard address.hasPrefix("0x") && address.count == 42 else {
        print("⚠️ Skipping pin for non-Ethereum address: \(address)")
        return
    }
    // ... rest of pinning logic
}
```

Falls back to plaintext when no Ethereum addresses available:
```swift
if let firstAgentWithAddress = agents.first(where: { $0.ethereumAddress != nil }) {
    // Configure with E2EE
} else {
    // Configure without E2EE (plaintext fallback)
    print("📡 No Ethereum addresses - E2EE not available")
}
```

## Testing with Different Osaurus Versions

### Osaurus < 0.22 (UUID-based, like 0.21.1)
- ✅ Agent discovery works
- 📡 Agent calls use plaintext
- ⚠️ 426 error if E2EE required on server
- **Fix:** Disable E2EE requirement or upgrade Osaurus

### Osaurus >= 0.22 (hypothetical, with `agent_address`)
- ✅ Agent discovery works
- 🔐 Agent calls use E2EE automatically
- ✅ 426 requirement satisfied
- ✅ Full security guarantees

## Recommendations

1. **Check Osaurus upstream:** Look for a version that includes Ethereum addresses
2. **Disable E2EE for now:** Your Tailscale network already provides transport encryption
3. **File an issue:** If E2EE is important, ask Osaurus maintainers about the address field
4. **Document version:** Note in README which Osaurus version you're using

## When E2EE Actually Matters

**E2EE provides security even when:**
- Using Osaurus relay server (not on LAN)
- Don't trust the relay operator
- Want forward secrecy (old sessions can't be decrypted later)
- Want proof of agent identity via cryptographic signatures

**E2EE is less critical when:**
- Only using local network (Tailscale, LAN)
- WireGuard/TLS already encrypts transport
- Trust the relay operator
- Threat model doesn't include passive network monitoring

Your setup (Tailscale) already has transport encryption via WireGuard, so disabling E2EE is reasonable until Osaurus adds proper address support.

## Summary

**Current Status:**
- Code is ready for E2EE
- Osaurus 0.21.1 doesn't provide necessary data (Ethereum addresses)
- Gracefully falls back to plaintext
- Will automatically work when addresses are available

**Next Steps:**
1. Check for Osaurus updates
2. Disable E2EE requirement on server, OR
3. Wait for upstream to add `agent_address` field

The secure channel implementation is **correct and ready**—we just need the right data from the server!
