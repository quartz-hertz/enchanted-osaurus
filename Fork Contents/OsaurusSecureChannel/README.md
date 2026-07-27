# Enchanted (Fork with LaTeX rendering & Osaurus agent support)

> **This is a fork.** It is based on [Enchanted](https://github.com/AugustinasK/Enchanted)
> by **Augustinas Malinauskas**, whose work this project builds on and is grateful
> for. This fork is **not** affiliated with or endorsed by the original author.
> All upstream credit belongs to them; the changes described below are the only
> parts authored by this fork's maintainer(s).

Enchanted is a SwiftUI app for chatting with local and remote language models
running on [Ollama](https://ollama.com). This fork adds two things on top of the
original app:

1. **LaTeX → Unicode rendering** so math notation like `$\text{H}_2\text{O}$`
   displays inline as `H₂O` without a full LaTeX renderer.
2. **Osaurus agent support**, including an end-to-end-encrypted
   [Secure Channel](https://github.com/osaurus-ai/osaurus) client (vendored,
   MIT) for talking to Osaurus agents that require E2EE.

---

## Table of contents

- [Credits & licensing](#credits--licensing)
- [What this fork changes](#what-this-fork-changes)
- [Requirements](#requirements)
- [Dependencies](#dependencies)
- [Getting started](#getting-started)
- [Features](#features)
- [LaTeX → Unicode](#latex--unicode)
- [Osaurus agents & secure channel](#osaurus-agents--secure-channel)
- [Export & import](#export--import)
- [Project layout](#project-layout)
- [Keeping the fork in sync with upstream](#keeping-the-fork-in-sync-with-upstream)
- [License](#license)

---

## Credits & licensing

| Work | Author / Source | License | Notes |
|---|---|---|---|
| **Enchanted** (the base app) | Augustinas Malinauskas | MIT | The overwhelming majority of this codebase. See `LICENSE`. |
| **Osaurus Secure Channel** (vendored) | `osaurus-ai/osaurus` | MIT | Client-side secure channel code in `OsaurusSecureChannel/`. See `OsaurusSecureChannel/LICENSE-osaurus`. |
| **swift-secp256k1 / P256K** | 21-DOT-DEV | MIT | Used to verify the server's handshake signature. |
| Fork-specific changes | This fork's maintainer(s) | MIT (same as upstream) | See [What this fork changes](#what-this-fork-changes). |

If you are the upstream author and anything here is misattributed, please open an
issue and it will be corrected immediately.

---

## What this fork changes

Everything **not** listed here is upstream Enchanted, unchanged.

**New features**

- **LaTeX → Unicode** (`LaTeXToUnicode.swift`): converts LaTeX math spans
  (`$...$`, `$$...$$`, `\(...\)`, `\[...\]`) into Unicode for display in
  `MarkdownUI`. Handles Greek letters, operators, arrows, set notation,
  sub/superscripts, `\frac`, `\sqrt` (incl. nth roots), `\text{...}`,
  `\hat`/`\vec`/`\overline`, and more.
- **Osaurus agents**: discover and run Osaurus agents alongside Ollama models.
  Agent runs stream over SSE and support tool-progress hints.
- **End-to-end encryption**: a vendored client for the Osaurus Secure Channel
  v1 wraps agent-run requests in an encrypted envelope when the server requires
  E2EE, with trust-on-first-use (TOFU) address pinning.

**New files (fork-authored)**

- `LaTeXToUnicode.swift` — LaTeX → Unicode converter + `String.latexToUnicode`.
- `AgentService.swift`, `AgentStore.swift`, `AgentModels.swift`,
  `OsaurusServerConfig.swift` — Osaurus agent client, state, models, and
  server config.
- `import_enchanted.py` — Python helper that normalizes Enchanted iOS exports
  into a knowledge-base schema.
- `SECURE_CHANNEL_INTEGRATION.md`, `QUICKSTART.md` — integration docs.

**Vendored files (from `osaurus-ai/osaurus`, MIT)**

- `OsaurusSecureChannel/SecureChannel.swift`
- `OsaurusSecureChannel/SecureChannelCrypto.swift`
- `OsaurusSecureChannel/SecureChannelClient.swift` — one adaptation:
  upstream's `RemoteProvider` is replaced by a `SecureChannelPeer` protocol
  so the app's server model can conform to it.
- `OsaurusSecureChannel/LICENSE-osaurus` — upstream MIT license, kept with the
  code as required.

**Modified upstream files**

- `ChatMessageView.swift` — message content and "think" blocks are passed
  through `.latexToUnicode` before rendering.
- `ConversationStore.swift` — added the agent streaming path
  (`sendAgentPrompt` / `handleAgentReceive`), OpenAI-format message conversion
  for vision, and deferred persistence of streamed assistant messages.
- Agent-related model plumbing (`LanguageModelSD` provider/`isAgent` fields,
  `SwiftDataService.fetchOrCreateAgentModel`) to surface agents as
  first-class models in the UI.

> If you re-sync with upstream, the files above are the ones most likely to
> conflict — diff them deliberately.

---

## Requirements

- **iOS 17.0+ / iPadOS 17.0+** and **macOS 14.0+** (SwiftData + SwiftUI).
  _Confirm against your project's deployment targets._
- Xcode 16+ (Swift 5.9+ toolchain).
- An [Ollama](https://ollama.com) server (local or remote), **or** an
  [Osaurus](https://github.com/osaurus-ai/osaurus) server for agents.

---

## Dependencies

| Package | Purpose |
|---|---|
| [OllamaKit](https://github.com/kevherro/OllamaKit) | Ollama API client (upstream) |
| [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) | Markdown rendering (upstream) |
| [Splash](https://github.com/JohnSundell/Splash) | Code syntax highlighting (upstream) |
| [ActivityIndicatorView](https://github.com/exyte/ActivityIndicatorView) | Loading indicator (upstream) |
| [swift-secp256k1](https://github.com/21-DOT-DEV/swift-secp256k1) (product **`P256K`**) | Signature verification for the secure channel (fork) |

See each package's own license for terms.

---

## Getting started

1. **Clone** this repository.
2. **Open** the Xcode project/workspace.
3. **Add the `P256K` package dependency**
   (File → Add Package Dependencies →
   `https://github.com/21-DOT-DEV/swift-secp256k1`, version `0.23.2` or newer,
   product **`P256K`**) and add it to the app target. This is required for the
   secure channel; without it the agent/E2EE code will not build.
4. **Build & run** on the iOS or macOS simulator/device.
5. In Settings, point the app at your Ollama **or** Osaurus server URL
   (and bearer token if your server uses one).

> New to the secure channel? Read `QUICKSTART.md` and
> `SECURE_CHANNEL_INTEGRATION.md` for a step-by-step walkthrough, or
> `OsaurusSecureChannel/README.md` for the vendored protocol overview and
> error map.

---

## Features

*Inherited from Enchanted (upstream):*

- Chat with any Ollama-hosted model
- Multiple conversations, SwiftData persistence
- Image (vision) messages
- macOS floating prompt panel & global keyboard shortcut
- Speech playback, code highlighting, markdown rendering

*Added by this fork:*

- Inline LaTeX math rendered as Unicode (no LaTeX engine needed)
- Discover and run Osaurus agents
- Optional end-to-end encryption for agent runs (Osaurus Secure Channel v1)
- TOFU pinning of agent addresses with mismatch detection
- Plaintext fallback when a server doesn't (yet) support E2EE
- Python export normalizer (`import_enchanted.py`)

---

## LaTeX → Unicode

`LaTeXToUnicode.swift` is a dependency-free, pure-Swift converter. It does
**not** invoke a LaTeX engine; it maps common math notation to Unicode
characters so expressions render in `MarkdownUI` without extra assets.

```swift
import Foundation // the extension is defined on String

"Water is $\\text{H}_2\\text{O}$".latexToUnicode
// → "Water is H₂O"

"$E = mc^2$".latexToUnicode          // → "E = mc²"
"$\\frac{a}{b}$".latexToUnicode      // → "(a)/(b)"
"$\\sqrt[3]{x}$".latexToUnicode      // → "³√x"
"$\\alpha + \\beta = \\gamma$".latexToUnicode  // → "α + β = γ"
