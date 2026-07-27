//
//  LaTeXToUnicodeTests.swift
//  Enchanted
//
/*
import Testing
@testable import Enchanted

@Suite("LaTeX to Unicode conversion")
struct LaTeXToUnicodeTests {

    @Test("Water formula: $\\text{H}_2\\text{O}$ → H₂O")
    func waterFormula() {
        let input = "The formula for water is $\\text{H}_2\\text{O}$."
        #expect(input.latexToUnicode == "The formula for water is H₂O.")
    }

    @Test("Einstein's equation: $E = mc^2$ → E = mc²")
    func einstein() {
        #expect("$E = mc^2$".latexToUnicode == "E = mc²")
    }

    @Test("Greek letters")
    func greekLetters() {
        #expect("$\\alpha + \\beta = \\gamma$".latexToUnicode == "α + β = γ")
    }

    @Test("Display math with $$...$$")
    func displayMath() {
        let result = "Here: $$x^2 + y^2 = r^2$$".latexToUnicode
        #expect(result.contains("x² + y² = r²"))
    }

    @Test("Fraction: $\\frac{a}{b}$ → (a)/(b)")
    func fraction() {
        #expect("$\\frac{a}{b}$".latexToUnicode == "(a)/(b)")
    }

    @Test("Square root variants")
    func sqrt() {
        #expect("$\\sqrt{x}$ and $\\sqrt{x+1}$".latexToUnicode == "√x and √(x+1)")
    }

    @Test("Nth root: $\\sqrt[3]{x}$ → ³√x")
    func nthRoot() {
        #expect("$\\sqrt[3]{x}$".latexToUnicode == "³√x")
    }

    @Test("Operators: $\\pi \\approx 3.14$")
    func operators() {
        #expect("$\\pi \\approx 3.14$".latexToUnicode == "π ≈ 3.14")
    }

    @Test("No math delimiters — unchanged")
    func noMath() {
        #expect("Just regular text.".latexToUnicode == "Just regular text.")
    }

    @Test("Unclosed $ preserved")
    func unclosedDelimiter() {
        #expect("Price is $5.".latexToUnicode == "Price is $5.")
    }

    @Test("Mixed markdown and math")
    func mixedMarkdown() {
        #expect("**Bold** and $\\pi r^2$".latexToUnicode == "**Bold** and π r²")
    }

    @Test("Parenthesized delimiters \\(...\\)")
    func parenDelimiters() {
        #expect("\\(\\text{H}_2\\text{O}\\)".latexToUnicode == "H₂O")
    }

    @Test("Subscript with brace group: $x_{ij}$")
    func subscriptGroup() {
        #expect("$x_{ij}$".latexToUnicode == "xᵢⱼ")
    }

    @Test("Multiplication: $2 \\times 3 = 6$")
    func multiplication() {
        #expect("$2 \\times 3 = 6$".latexToUnicode == "2 × 3 = 6")
    }
}

*/
