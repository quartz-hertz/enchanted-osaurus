//
//  ArtifactParser.swift
//  Enchanted
//
//  Parses Claude-style artifact tags from assistant message content so they
//  can be rendered as dedicated panels instead of raw markup.
//
//  Also supports heuristic detection of "document-like" markdown sections
//  (heading + table/code fence) for models that emit inline markdown with
//  no structured artifact tags (e.g. Gemma "composer" fine-tunes that use
//  <channel|> control tokens).
//

import Foundation

/// A single artifact extracted from message content.
struct Artifact: Identifiable, Hashable {
    let id: UUID
    let identifier: String?
    let type: String?
    let title: String?
    let language: String?
    let content: String

    init(
        identifier: String?,
        type: String?,
        title: String?,
        language: String?,
        content: String,
        id: UUID = UUID()
    ) {
        self.id = id
        self.identifier = identifier
        self.type = type
        self.title = title
        self.language = language
        self.content = content
    }

    /// Title to show in the artifact card header.
    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if let language, !language.isEmpty { return language.capitalized }
        if let type, !type.isEmpty {
            switch type.lowercased() {
            case "text/markdown": return "Markdown"
            case "text/html": return "HTML"
            case "image/svg+xml": return "SVG"
            case "application/vnd.ant.code": return "Code"
            case "application/vnd.ant.mermaid": return "Diagram"
            default: return type
            }
        }
        return "Artifact"
    }

    /// True for markdown artifacts that should render as rich text.
    var isMarkdown: Bool {
        type?.lowercased() == "text/markdown"
    }

    /// True for code-like artifacts (code, HTML, SVG, mermaid, or anything
    /// with an explicit language that isn't markdown).
    var isCode: Bool {
        guard let type = type?.lowercased() else { return language != nil }
        return type.contains("code")
            || type == "text/html"
            || type == "image/svg+xml"
            || type == "application/vnd.ant.mermaid"
            || (language != nil && type != "text/markdown")
    }

    /// Language hint to pass to the syntax highlighter for code artifacts.
    var highlightLanguage: String? {
        if let language, !language.isEmpty { return language }
        guard let type = type?.lowercased() else { return nil }
        switch type {
        case "text/html": return "html"
        case "image/svg+xml": return "xml"
        case "application/vnd.ant.mermaid": return "mermaid"
        default: return nil
        }
    }
}

/// A piece of parsed message content: either prose (markdown) or an artifact.
enum ContentSegment: Hashable {
    case prose(String)
    case artifact(Artifact)
}

enum ArtifactParser {
    /// Tag names we recognize as artifact containers. Ordered longest-first
    /// so the regex alternation prefers the more specific names.
    private static let tagNames = ["antml:artifact", "antArtifact", "artifact"]

    /// Model-specific control tokens that leak into streamed content and
    /// should be stripped before display. These are not artifact delimiters
    /// and should never be shown to the user.
    ///
    /// Two categories:
    /// 1. **Gemma "composer" fine-tune modality tokens** — `<channel|>`,
    ///    `<image|>`, `<audio|>`, `<video|>`, `<text|>`. These use the
    ///    `<word|>` pattern and are also caught by the regex pass below, but
    ///    are listed explicitly for documentation.
    /// 2. **Gemma chat-template tokens** — `<end_of_turn>`, `<start_of_turn>`.
    ///    These do NOT use the pipe pattern and must be listed explicitly.
    private static let controlTokens = [
        // Gemma composer modality tokens (also caught by regex, listed for clarity)
        "<channel|>", "<image|>", "<audio|>", "<video|>", "<text|>",
        // Gemma chat-template tokens (not pipe-pattern, must be explicit)
        "<end_of_turn>", "<start_of_turn>", "</channel>", "<channel>"
    ]

    /// Regex that matches the Gemma composer `<modality|>` token pattern:
    /// an opening angle bracket, one or more letters/underscores, a pipe,
    /// and a closing angle bracket. Catches future modality tokens from the
    /// same fine-tune family without needing to update the explicit list.
    private static let composerTokenPattern = #"<[a-zA-Z_]+\|>"#

    /// Strip model-specific control tokens from content. Public so callers
    /// can clean content before storage (e.g. in ConversationStore) to keep
    /// the database free of leaked model tokens.
    static func stripControlTokens(_ content: String) -> String {
        var result = content

        // 1. Strip explicit tokens (covers non-pipe patterns like
        //    <end_of_turn> that the regex won't catch)
        for token in controlTokens {
            result = result.replacingOccurrences(of: token, with: "")
        }

        // 2. Regex pass for any <word|> composer modality token. This is
        //    the robustness layer — catches tokens we haven't seen yet
        //    from the same fine-tune family.
        if let regex = try? NSRegularExpression(
            pattern: composerTokenPattern,
            options: [.caseInsensitive]
        ) {
            let nsResult = result as NSString
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(location: 0, length: nsResult.length),
                withTemplate: ""
            )
        }

        // 3. Collapse triple+ blank lines left behind by token removal
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        // 4. Trim trailing whitespace that often follows a stripped token
        //    at the end of a message (e.g. "proved to be the<image|>" →
        //    "proved to be the")
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }

    /// Split message content into prose and artifact segments, preserving
    /// order. Strips leaked control tokens first, then tries structured
    /// tag-based parsing; if no tag-based artifacts are found, falls back
    /// to heuristic detection of document-like markdown blocks.
    static func parse(_ content: String) -> [ContentSegment] {
        // 1. Strip leaked control tokens
        let cleaned = stripControlTokens(content)

        // 2. Try structured tag-based parsing (Claude-style <artifact> tags)
        let tagBased = parseTagBased(cleaned)
        if tagBased.contains(where: { segment in
            if case .artifact = segment { return true }
            return false
        }) {
            return tagBased
        }

        // 3. Fall back to heuristic detection for inline-markdown models
        return parseHeuristic(cleaned)
    }

    // MARK: - Tag-Based Parsing (Claude-style)

    /// Parse Claude-style <artifact> tags. This is the original parser,
    /// extracted into its own method so `parse()` can try it first and
    /// fall back to heuristic detection.
    private static func parseTagBased(_ content: String) -> [ContentSegment] {
        let alternation = tagNames.joined(separator: "|")
        // Lookahead after the tag name ensures we don't match `<artifacts>`
        // or similar; the backreference makes the closing tag match the
        // opening tag name exactly.
        let pattern = #"<(\#(alternation))(?=[\s/>])([^>]*)>([\s\S]*?)</\1>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return [.prose(content)]
        }

        let nsContent = content as NSString
        let matches = regex.matches(
            in: content,
            range: NSRange(location: 0, length: nsContent.length)
        )

        guard !matches.isEmpty else {
            // No complete artifacts. Check for an in-progress one before
            // returning the whole thing as prose.
            return proseWithInProgressPlaceholder(content)
        }

        var segments: [ContentSegment] = []
        var lastEnd = 0

        for match in matches {
            if match.range.location > lastEnd {
                let prose = nsContent.substring(
                    with: NSRange(location: lastEnd, length: match.range.location - lastEnd)
                )
                if !prose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.prose(prose))
                }
            }

            let attrs = nsContent.substring(with: match.range(at: 2))
            let body = nsContent.substring(with: match.range(at: 3))

            segments.append(.artifact(parseAttributes(attrs: attrs, body: body)))
            lastEnd = match.range.location + match.range.length
        }

        // Trailing content after the last artifact.
        if lastEnd < nsContent.length {
            let trailing = nsContent.substring(from: lastEnd)
            segments.append(contentsOf: proseWithInProgressPlaceholder(trailing))
        }

        return segments
    }

    /// If `text` contains an unclosed artifact opening tag, returns the prose
    /// before it plus a "Generating artifact…" placeholder. Otherwise returns
    /// the text as a single prose segment (or nothing if it's blank).
    private static func proseWithInProgressPlaceholder(_ text: String) -> [ContentSegment] {
        let alternation = tagNames.joined(separator: "|")
        let openPattern = #"<(\#(alternation))(?=[\s/>])"#

        guard let openRegex = try? NSRegularExpression(pattern: openPattern, options: [.caseInsensitive]) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? []
                : [.prose(text)]
        }

        let nsText = text as NSString
        if let openMatch = openRegex.firstMatch(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ) {
            var result: [ContentSegment] = []
            if openMatch.range.location > 0 {
                let before = nsText.substring(to: openMatch.range.location)
                if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result.append(.prose(before))
                }
            }
            result.append(.prose("_Generating artifact…_"))
            return result
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? []
            : [.prose(text)]
    }

    private static func parseAttributes(attrs: String, body: String) -> Artifact {
        var type: String?
        var title: String?
        var language: String?
        var identifier: String?

        let attrPattern = #"(\w+)\s*=\s*["']([^"']*)["']"#
        if let attrRegex = try? NSRegularExpression(pattern: attrPattern, options: []) {
            let nsAttrs = attrs as NSString
            let attrMatches = attrRegex.matches(
                in: attrs,
                range: NSRange(location: 0, length: nsAttrs.length)
            )
            for m in attrMatches {
                let key = nsAttrs.substring(with: m.range(at: 1)).lowercased()
                let value = nsAttrs.substring(with: m.range(at: 2))
                switch key {
                case "type": type = value
                case "title": title = value
                case "language": language = value
                case "identifier", "id": identifier = value
                default: break
                }
            }
        }

        return Artifact(
            identifier: identifier,
            type: type,
            title: title,
            language: language,
            content: body.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    // MARK: - Heuristic Parsing (inline markdown models)

    /// Heuristically detect "document-like" markdown sections and wrap them
    /// as markdown artifacts. Used for models that emit artifacts as inline
    /// markdown (e.g. Gemma "composer" fine-tunes) rather than structured
    /// tags.
    ///
    /// A document section starts at a markdown heading (`#`–`######`) that
    /// is followed by structured content (a table or code fence). The
    /// section extends through adjacent document-like blocks (tables, code
    /// fences, bold-label paragraphs) until a conversational prose block is
    /// encountered.
    ///
    /// This is inherently conservative: if no heading + structured-content
    /// pattern is found, the entire content is returned as a single prose
    /// segment and renders as normal markdown.
    private static func parseHeuristic(_ content: String) -> [ContentSegment] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Split into blocks separated by blank lines
        let blocks = trimmed.components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard blocks.count > 1 else {
            return [.prose(content)]
        }

        // Only engage if there's structured content (tables or code fences)
        let hasStructured = blocks.contains { isMarkdownTable($0) || isCodeFence($0) }
        guard hasStructured else {
            return [.prose(content)]
        }

        var segments: [ContentSegment] = []
        var artifactBlocks: [String] = []
        var inDocument = false
        var sawStructured = false

        func flushArtifact() {
            guard !artifactBlocks.isEmpty else {
                inDocument = false
                sawStructured = false
                return
            }
            if sawStructured {
                let artContent = artifactBlocks.joined(separator: "\n\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !artContent.isEmpty {
                    segments.append(.artifact(makeMarkdownArtifact(content: artContent)))
                }
            } else {
                // Heading was never followed by structured content — treat
                // the accumulated blocks as prose
                segments.append(.prose(artifactBlocks.joined(separator: "\n\n")))
            }
            artifactBlocks = []
            inDocument = false
            sawStructured = false
        }

        for block in blocks {
            let blockTrimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            let isHeading = blockTrimmed.hasPrefix("#")
            let isTable = isMarkdownTable(blockTrimmed)
            let isCode = isCodeFence(blockTrimmed)
            let isBoldLabel = blockTrimmed.hasPrefix("**") &&
                (blockTrimmed.contains(":**") || blockTrimmed.contains("**:"))

            if isHeading {
                // A heading starts (or restarts) a document section
                if inDocument {
                    flushArtifact()
                }
                inDocument = true
                sawStructured = false
                artifactBlocks.append(block)
            } else if inDocument {
                if isTable || isCode {
                    sawStructured = true
                    artifactBlocks.append(block)
                } else if isBoldLabel {
                    // Bold-label paragraphs like "**Verdict:** ..." are part
                    // of the document
                    artifactBlocks.append(block)
                } else if isConversational(blockTrimmed) {
                    // Back to conversational prose — end the artifact
                    flushArtifact()
                    segments.append(.prose(block))
                } else {
                    // Ambiguous — include in document; if structured content
                    // follows, this becomes part of the artifact; if not,
                    // flushArtifact will emit it as prose
                    artifactBlocks.append(block)
                }
            } else {
                segments.append(.prose(block))
            }
        }

        flushArtifact()

        // If no artifacts were produced, return the whole thing as prose
        if segments.contains(where: { segment in
            if case .artifact = segment { return true }
            return false
        }) {
            return segments
        } else {
            return [.prose(content)]
        }
    }

    /// Check if a block contains a markdown table (header + separator row).
    /// Matches the `|---|` separator line that distinguishes a table from
    /// plain pipe-delimited text.
    private static func isMarkdownTable(_ text: String) -> Bool {
        text.range(of: #"\|[\s:]*-{2,}[\s:]*\|"#, options: .regularExpression) != nil
    }

    /// Check if a block starts with a code fence.
    private static func isCodeFence(_ text: String) -> Bool {
        text.hasPrefix("```")
    }

    /// Heuristic: does this block look like conversational prose rather than
    /// document content? Conservative — only matches clear first-person /
    /// meta-commentary starters so we don't accidentally split documents.
    private static func isConversational(_ text: String) -> Bool {
        let lower = text.lowercased()
        let starters: [String] = [
            "i'll", "i'm", "i've", "i'd", "i ",
            "let me", "let's",
            "sharing ", "one more",
            "hopefully", "sorry", "actually",
            "here's", "here is",
            "originally", "using "
        ]
        return starters.contains { lower.hasPrefix($0) }
    }

    /// Build a markdown artifact from extracted content, deriving a title
    /// from the first heading if present.
    private static func makeMarkdownArtifact(content: String) -> Artifact {
        var title: String?
        if let firstLine = content.components(separatedBy: "\n").first,
           firstLine.hasPrefix("#") {
            title = firstLine.replacingOccurrences(
                of: #"^#+\s+"#,
                with: "",
                options: .regularExpression
            )
        }
        return Artifact(
            identifier: nil,
            type: "text/markdown",
            title: title,
            language: nil,
            content: content
        )
    }
}
