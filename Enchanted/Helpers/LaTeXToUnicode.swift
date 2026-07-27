// LaTeXToUnicode.swift

import Foundation

/// Converts common LaTeX math notation inside `$...$`, `$$...$$`, `\(...\)`,
/// and `\[...\]` spans into Unicode characters, so expressions like
/// `$\text{H}_2\text{O}$` render as `H₂O` without a full LaTeX renderer.
enum LaTeXToUnicode {
    
    // MARK: - Character Maps
    
    private static let subscriptMap: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
        "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ",
        "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ", "o": "ₒ",
        "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ", "u": "ᵤ",
        "v": "ᵥ", "x": "ₓ",
        "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎"
    ]
    
    private static let superscriptMap: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "a": "ᵃ", "b": "ᵇ", "c": "ᶜ", "d": "ᵈ", "e": "ᵉ",
        "f": "ᶠ", "g": "ᵍ", "h": "ʰ", "i": "ⁱ", "j": "ʲ",
        "k": "ᵏ", "l": "ˡ", "m": "ᵐ", "n": "ⁿ", "o": "ᵒ",
        "p": "ᵖ", "r": "ʳ", "s": "ˢ", "t": "ᵗ", "u": "ᵘ",
        "v": "ᵛ", "w": "ʷ", "x": "ˣ", "y": "ʸ", "z": "ᶻ",
        "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾"
    ]
    
    private static let symbolMap: [String: String] = [
        // Greek lowercase
        "\\alpha": "α", "\\beta": "β", "\\gamma": "γ", "\\delta": "δ",
        "\\epsilon": "ε", "\\varepsilon": "ε", "\\zeta": "ζ", "\\eta": "η",
        "\\theta": "θ", "\\vartheta": "ϑ", "\\iota": "ι", "\\kappa": "κ",
        "\\lambda": "λ", "\\mu": "μ", "\\nu": "ν", "\\xi": "ξ",
        "\\omicron": "ο", "\\pi": "π", "\\varpi": "ϖ", "\\rho": "ρ",
        "\\varrho": "ϱ", "\\sigma": "σ", "\\varsigma": "ς", "\\tau": "τ",
        "\\upsilon": "υ", "\\phi": "φ", "\\varphi": "ϕ", "\\chi": "χ",
        "\\psi": "ψ", "\\omega": "ω",
        // Greek uppercase
        "\\Gamma": "Γ", "\\Delta": "Δ", "\\Theta": "Θ", "\\Lambda": "Λ",
        "\\Xi": "Ξ", "\\Pi": "Π", "\\Sigma": "Σ", "\\Upsilon": "Υ",
        "\\Phi": "Φ", "\\Psi": "Ψ", "\\Omega": "Ω",
        // Operators & relations
        "\\times": "×", "\\cdot": "·", "\\div": "÷", "\\pm": "±",
        "\\mp": "∓", "\\approx": "≈", "\\neq": "≠", "\\leq": "≤",
        "\\geq": "≥", "\\le": "≤", "\\ge": "≥", "\\equiv": "≡",
        "\\sim": "∼", "\\cong": "≅", "\\simeq": "≃", "\\propto": "∝",
        // Arrows
        "\\rightarrow": "→", "\\to": "→", "\\Rightarrow": "⇒",
        "\\leftarrow": "←", "\\gets": "←", "\\Leftarrow": "⇐",
        "\\leftrightarrow": "↔", "\\Leftrightarrow": "⇔", "\\mapsto": "↦",
        // Calculus & sets
        "\\infty": "∞", "\\partial": "∂", "\\nabla": "∇",
        "\\sum": "∑", "\\prod": "∏", "\\int": "∫", "\\oint": "∮",
        "\\forall": "∀", "\\exists": "∃", "\\nexists": "∄",
        "\\in": "∈", "\\notin": "∉", "\\ni": "∋",
        "\\subset": "⊂", "\\supset": "⊃", "\\subseteq": "⊆", "\\supseteq": "⊇",
        "\\cup": "∪", "\\cap": "∩", "\\emptyset": "∅", "\\varnothing": "∅",
        // Geometry & misc
        "\\angle": "∠", "\\perp": "⊥", "\\parallel": "∥",
        "\\circ": "∘", "\\bullet": "•", "\\star": "⋆",
        "\\dagger": "†", "\\ddagger": "‡",
        "\\degree": "°",
        // Dots
        "\\cdots": "⋯", "\\ldots": "…", "\\dots": "…",
        "\\vdots": "⋮", "\\ddots": "⋱",
        // Special
        "\\hbar": "ℏ", "\\ell": "ℓ", "\\Re": "ℜ", "\\Im": "ℑ",
        "\\aleph": "ℵ", "\\prime": "′",
        "\\langle": "⟨", "\\rangle": "⟩",
        "\\lceil": "⌈", "\\rceil": "⌉", "\\lfloor": "⌊", "\\rfloor": "⌋",
    ]
    
    // MARK: - Public API
    
    /// Convert LaTeX math spans in a string to Unicode.
    static func convert(_ input: String) -> String {
        var result = input
        // Display math first ($$...$$ and \[...\]) so they don't get
        // partially consumed by the inline delimiters.
        result = processSpans(result, open: "$$", close: "$$", isDisplay: true)
        result = processSpans(result, open: "\\[", close: "\\]", isDisplay: true)
        result = processSpans(result, open: "$", close: "$", isDisplay: false)
        result = processSpans(result, open: "\\(", close: "\\)", isDisplay: false)
        return result
    }
    
    // MARK: - Span Extraction
    
    private static func processSpans(
        _ input: String,
        open: String,
        close: String,
        isDisplay: Bool
    ) -> String {
        var result = ""
        var remaining = Substring(input)
        
        while let openRange = remaining.range(of: open) {
            result += String(remaining[remaining.startIndex..<openRange.lowerBound])
            let afterOpen = openRange.upperBound
            
            guard let closeRange = remaining[afterOpen...].range(of: close) else {
                // No closing delimiter — append the rest unchanged.
                result += String(remaining[openRange.lowerBound...])
                return result
            }
            
            let mathBody = String(remaining[afterOpen..<closeRange.lowerBound])
            let converted = convertMathBody(mathBody)
            
            if isDisplay {
                result += "\n\n\(converted)\n\n"
            } else {
                result += converted
            }
            
            remaining = remaining[closeRange.upperBound...]
        }
        
        result += String(remaining)
        return result
    }
    
    // MARK: - Math Body Conversion
    
    private static func convertMathBody(_ body: String) -> String {
        var work = body
        
        // 1. \text{...}, \mathrm{...}, etc. → extract inner content
        for cmd in ["\\text", "\\mathrm", "\\mathit", "\\mathbf", "\\mathsf", "\\mathtt"] {
            work = replaceBracedCommand(work, command: cmd) { inner in inner }
        }
        
        // 2. \frac{a}{b} → (a)/(b)
        work = convertFrac(work)
        
        // 3. \sqrt{x} → √x, \sqrt[n]{x} → ⁿ√x
        work = convertSqrt(work)
        
        // 4. \overline{x} → x̄
        work = replaceBracedCommand(work, command: "\\overline") { inner in
            inner + "\u{0305}"
        }
        
        // 5. \hat{x} → x̂, \vec{x} → x⃗
        work = replaceBracedCommand(work, command: "\\hat") { inner in
            inner + "\u{0302}"
        }
        work = replaceBracedCommand(work, command: "\\vec") { inner in
            inner + "\u{20D7}"
        }
        
        // 6. Replace named symbols (longest first to avoid prefix collisions)
        for (latex, unicode) in symbolMap.sorted(by: { $0.key.count > $1.key.count }) {
            work = work.replacingOccurrences(of: latex, with: unicode)
        }
        
        // 7. Subscripts _{...} and _x
        work = convertScripts(work, marker: "_", map: subscriptMap)
        
        // 8. Superscripts ^{...} and ^x
        work = convertScripts(work, marker: "^", map: superscriptMap)
        
        // 9. Strip LaTeX spacing / sizing commands
        for spacing in ["\\,", "\\;", "\\:", "\\!", "\\quad", "\\qquad",
                        "\\left", "\\right", "\\displaystyle",
                        "\\scriptstyle", "\\textstyle", "\\,",
                        "\\thinspace", "\\medspace", "\\thickspace"] {
            work = work.replacingOccurrences(of: spacing, with: " ")
        }
        
        // 10. Collapse multiple spaces
        work = work.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        
        return work.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Braced Commands
    
    /// Replace all occurrences of `\command{...}` using `transform`.
    private static func replaceBracedCommand(
        _ input: String,
        command: String,
        transform: (String) -> String
    ) -> String {
        var result = ""
        var remaining = Substring(input)
        
        while let range = remaining.range(of: command) {
            result += String(remaining[remaining.startIndex..<range.lowerBound])
            var idx = range.upperBound
            
            // Skip optional whitespace between command and brace
            while idx < remaining.endIndex, remaining[idx].isWhitespace {
                idx = remaining.index(after: idx)
            }
            
            guard idx < remaining.endIndex, remaining[idx] == "{" else {
                result += String(remaining[range.lowerBound...])
                return result
            }
            
            guard let closeIdx = matchingBrace(remaining, at: idx) else {
                result += String(remaining[range.lowerBound...])
                return result
            }
            
            let inner = String(remaining[remaining.index(after: idx)..<closeIdx])
            result += transform(inner)
            remaining = remaining[remaining.index(after: closeIdx)...]
        }
        
        result += String(remaining)
        return result
    }
    
    /// Find the `}` matching the `{` at `index`.
    private static func matchingBrace(_ s: Substring, at index: String.Index) -> String.Index? {
        var depth = 0
        var i = index
        while i < s.endIndex {
            switch s[i] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return i }
            default: break
            }
            i = s.index(after: i)
        }
        return nil
    }
    
    // MARK: - \frac
    
    private static func convertFrac(_ input: String) -> String {
        var result = ""
        var remaining = Substring(input)
        
        while let range = remaining.range(of: "\\frac") {
            result += String(remaining[remaining.startIndex..<range.lowerBound])
            var idx = range.upperBound
            skipWhitespace(remaining, &idx)
            
            guard idx < remaining.endIndex, remaining[idx] == "{",
                  let numClose = matchingBrace(remaining, at: idx) else {
                result += String(remaining[range.lowerBound...])
                return result
            }
            let numerator = String(remaining[remaining.index(after: idx)..<numClose])
            
            var denomStart = remaining.index(after: numClose)
            skipWhitespace(remaining, &denomStart)
            
            guard denomStart < remaining.endIndex, remaining[denomStart] == "{",
                  let denomClose = matchingBrace(remaining, at: denomStart) else {
                result += "(\(numerator))"
                remaining = remaining[remaining.index(after: numClose)...]
                continue
            }
            
            let denominator = String(remaining[remaining.index(after: denomStart)..<denomClose])
            result += "(\(numerator))/(\(denominator))"
            remaining = remaining[remaining.index(after: denomClose)...]
        }
        
        result += String(remaining)
        return result
    }
    
    // MARK: - \sqrt
    
    private static func convertSqrt(_ input: String) -> String {
        var result = ""
        var remaining = Substring(input)
        
        while let range = remaining.range(of: "\\sqrt") {
            result += String(remaining[remaining.startIndex..<range.lowerBound])
            var idx = range.upperBound
            skipWhitespace(remaining, &idx)
            
            // Optional [n] root index
            var rootIndex = ""
            if idx < remaining.endIndex, remaining[idx] == "[",
               let bracketClose = remaining[idx...].firstIndex(of: "]") {
                rootIndex = String(remaining[remaining.index(after: idx)..<bracketClose])
                idx = remaining.index(after: bracketClose)
                skipWhitespace(remaining, &idx)
            }
            
            guard idx < remaining.endIndex, remaining[idx] == "{",
                  let braceClose = matchingBrace(remaining, at: idx) else {
                result += String(remaining[range.lowerBound...])
                return result
            }
            
            let inner = String(remaining[remaining.index(after: idx)..<braceClose])
            let needsParens = inner.count > 1 || inner.contains(where: { "+-*/^_= ".contains($0) })
            let formatted = needsParens ? "(\(inner))" : inner
            
            if rootIndex.isEmpty {
                result += "√\(formatted)"
            } else {
                let superIdx = rootIndex.compactMap { superscriptMap[$0] }.map { String($0) }.joined()
                if superIdx.count == rootIndex.count {
                    result += "\(superIdx)√\(formatted)"
                } else {
                    result += "(\(rootIndex))√\(formatted)"
                }
            }
            
            remaining = remaining[remaining.index(after: braceClose)...]
        }
        
        result += String(remaining)
        return result
    }
    
    // MARK: - Subscripts & Superscripts
    
    private static func convertScripts(
        _ input: String,
        marker: Character,
        map: [Character: Character]
    ) -> String {
        var result = ""
        var remaining = Substring(input)
        
        while let range = remaining.range(of: String(marker)) {
            result += String(remaining[remaining.startIndex..<range.lowerBound])
            let after = range.upperBound
            
            guard after < remaining.endIndex else {
                result.append(marker)
                return result
            }
            
            if remaining[after] == "{" {
                guard let closeIdx = matchingBrace(remaining, at: after) else {
                    result += String(remaining[range.lowerBound...])
                    return result
                }
                let inner = String(remaining[remaining.index(after: after)..<closeIdx])
                // Resolve any \text{...} inside the group first
                let resolved = resolveTextCommands(inner)
                for ch in resolved where !ch.isWhitespace {
                    result.append(map[ch] ?? ch)
                }
                remaining = remaining[remaining.index(after: closeIdx)...]
            } else {
                let ch = remaining[after]
                result.append(map[ch] ?? ch)
                remaining = remaining[remaining.index(after: after)...]
            }
        }
        
        result += String(remaining)
        return result
    }
    
    /// Quick pass to resolve \text{...} inside a script group.
    private static func resolveTextCommands(_ input: String) -> String {
        var work = input
        for cmd in ["\\text", "\\mathrm", "\\mathit", "\\mathbf"] {
            work = replaceBracedCommand(work, command: cmd) { $0 }
        }
        return work
    }
    
    // MARK: - Helpers
    
    private static func skipWhitespace(_ s: Substring, _ idx: inout String.Index) {
        while idx < s.endIndex, s[idx].isWhitespace {
            idx = s.index(after: idx)
        }
    }
}

// MARK: - String Extension

extension String {
    /// Convert LaTeX math spans to Unicode for display.
    var latexToUnicode: String { LaTeXToUnicode.convert(self) }
}
