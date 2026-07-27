//
//  ArtifactView.swift
//  Enchanted
//
//  Renders Claude-style artifacts extracted from assistant messages as
//  dedicated panels (header + syntax-highlighted body / rendered markdown).
//

import SwiftUI
import MarkdownUI
import Splash

/// Renders a single artifact in a card.
struct ArtifactView: View {
    @Environment(\.colorScheme) private var colorScheme
    let artifact: Artifact

    private var codeHighlightColorScheme: Splash.Theme {
        switch colorScheme {
        case .dark:
            return .wwdc17(withFont: .init(size: 16))
        default:
            return .sunset(withFont: .init(size: 16))
        }
    }

    private var syntaxHighlighter: CodeSyntaxHighlighter {
        .splash(theme: codeHighlightColorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            bodyContent
        }
        .background(MarkdownColours.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(MarkdownColours.border, lineWidth: 1)
        )
        .padding(.vertical, 4)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(artifact.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MarkdownColours.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(action: { Clipboard.shared.setString(artifact.content) }) {
                Image(systemName: "doc.on.doc")
                    .padding(7)
            }
            .buttonStyle(GrowingButton())
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var bodyContent: some View {
        if artifact.isMarkdown {
            Markdown(artifact.content.latexToUnicode)
                .markdownTheme(MarkdownColours.enchantedTheme)
                .markdownCodeSyntaxHighlighter(syntaxHighlighter)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if artifact.isCode {
            ScrollView(.horizontal, showsIndicators: false) {
                syntaxHighlighter
                    .highlightCode(artifact.content, language: artifact.highlightLanguage)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(artifact.content)
                    .font(.system(size: 13, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var icon: String {
        switch artifact.type?.lowercased() {
        case "image/svg+xml": return "photo"
        case "text/markdown": return "doc.richtext"
        case "text/html": return "globe"
        case "application/vnd.ant.mermaid": return "chart.line.uptrend.xyaxis"
        case "application/vnd.ant.code": return "curlybraces"
        default:
            return artifact.language != nil ? "curlybraces" : "doc"
        }
    }

    private var subtitle: String? {
        if let language = artifact.language, !language.isEmpty {
            return language
        }
        if let type = artifact.type, !type.isEmpty {
            return type
        }
        return nil
    }
}

/// Renders assistant message content, splitting it into prose (rendered as
/// markdown) and artifacts (rendered via `ArtifactView`). When there are no
/// artifacts this is equivalent to rendering the whole content as markdown.
struct MessageContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: String

    private var codeHighlightColorScheme: Splash.Theme {
        switch colorScheme {
        case .dark:
            return .wwdc17(withFont: .init(size: 16))
        default:
            return .sunset(withFont: .init(size: 16))
        }
    }

    var body: some View {
        let segments = ArtifactParser.parse(content)

        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .prose(let text):
                    Markdown(text.latexToUnicode)
                        #if os(macOS)
                        .textSelection(.enabled)
                        #endif
                        .markdownCodeSyntaxHighlighter(.splash(theme: codeHighlightColorScheme))
                        .markdownTheme(MarkdownColours.enchantedTheme)
                case .artifact(let artifact):
                    ArtifactView(artifact: artifact)
                }
            }
        }
    }
}
