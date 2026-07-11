import Testing
@testable import OpenWorkNative

// Covers MessageContentParser.parse, the linear scanner in TranscriptView.swift that
// splits assistant/user message text into plain-markdown and <details> parts so the
// latter can render as native SwiftUI DisclosureGroups.

@Test func plainMarkdownWithNoDetailsTagStaysAsSingleMarkdownPart() {
    let parts = MessageContentParser.parse("Just a **plain** markdown message.")
    #expect(parts.count == 1)
    #expect(parts[0].kind == .markdown("Just a **plain** markdown message."))
}

@Test func simpleDetailsBlockParsesSummaryAndContent() {
    let text = "<details><summary>Click me</summary>Hidden content</details>"
    let parts = MessageContentParser.parse(text)
    #expect(parts.count == 1)
    #expect(parts[0].kind == .details(summary: "Click me", content: "Hidden content"))
}

@Test func detailsBlockWithoutSummaryFallsBackToDefaultLabel() {
    let text = "<details>No summary tag here</details>"
    let parts = MessageContentParser.parse(text)
    #expect(parts.count == 1)
    #expect(parts[0].kind == .details(summary: "Details", content: "No summary tag here"))
}

@Test func textBeforeAndAfterDetailsBlockIsSplitIntoSeparateMarkdownParts() {
    let text = "Before text.\n\n<details><summary>Toggle</summary>Body</details>\n\nAfter text."
    let parts = MessageContentParser.parse(text)
    #expect(parts.count == 3)
    #expect(parts[0].kind == .markdown("Before text.\n\n"))
    #expect(parts[1].kind == .details(summary: "Toggle", content: "Body"))
    #expect(parts[2].kind == .markdown("\n\nAfter text."))
}

@Test func multipleSiblingDetailsBlocksEachParseIndependently() {
    let text = "<details><summary>One</summary>First</details><details><summary>Two</summary>Second</details>"
    let parts = MessageContentParser.parse(text)
    #expect(parts.count == 2)
    #expect(parts[0].kind == .details(summary: "One", content: "First"))
    #expect(parts[1].kind == .details(summary: "Two", content: "Second"))
}

@Test func nestedDetailsBlocksAreCapturedWholeInsideOuterContent() {
    let text = "<details><summary>Outer</summary>before <details><summary>Inner</summary>inner body</details> after</details>"
    let parts = MessageContentParser.parse(text)
    #expect(parts.count == 1)
    #expect(parts[0].kind == .details(
        summary: "Outer",
        content: "before <details><summary>Inner</summary>inner body</details> after"
    ))
}

@Test func unclosedDetailsTagFallsBackToPlainMarkdown() {
    let text = "Intro text.\n\n<details><summary>Never closes</summary>dangling content"
    let parts = MessageContentParser.parse(text)
    #expect(parts.count == 2)
    #expect(parts[0].kind == .markdown("Intro text.\n\n"))
    #expect(parts[1].kind == .markdown("<details><summary>Never closes</summary>dangling content"))
}

// Regression test for the exact message reported in the bug: a real assistant reply that
// *explains* <details>/<summary> tags using inline code (`<details>`) before emitting an
// actual, real <details> block. The parser's naive substring search used to treat the
// inline-code mention as the opening tag, mismatch its depth-tracking against the real
// closing tag, and swallow the whole message (including the real block) into one
// .markdown part — which rendered as literal, uncollapsed "<details>" text on screen.
@Test func detailsTagMentionedInInlineCodeDoesNotConfuseRealDetailsBlock() {
    let text = """
    Here is an example of a collapsible section using the `<details>` and `<summary>` HTML tags, which work great in Markdown:

    <details>
    <summary>👉 Click here to reveal the hidden content!</summary>

    **Surprise!** 🎉

    You can put all sorts of standard Markdown inside a collapsible section, including:

    - **Bold** and *italic* text
    - Lists and bullet points
    - Code blocks:

    ```python
    def hello_world():
        print("I was hidden!")
    ```

    - Even tables!

    *Note: Make sure to leave a blank line after the `<summary>` tag so the Markdown inside renders correctly.*

    </details>

    Let me know if you need help formatting anything else!
    """

    let parts = MessageContentParser.parse(text)

    #expect(parts.count == 3, "expected intro markdown, one details block, and trailing markdown, got \(parts.count): \(parts.map(\.kind))")

    guard parts.count == 3 else { return }

    guard case .markdown(let intro) = parts[0].kind else {
        Issue.record("expected first part to be markdown, got \(parts[0].kind)")
        return
    }
    #expect(intro.contains("using the `<details>` and `<summary>` HTML tags"))

    guard case .details(let summary, let content) = parts[1].kind else {
        Issue.record("expected second part to be a details block, got \(parts[1].kind)")
        return
    }
    #expect(summary == "👉 Click here to reveal the hidden content!")
    #expect(content.contains("**Surprise!** 🎉"))
    #expect(content.contains("def hello_world():"))
    #expect(content.contains("Even tables!"))

    guard case .markdown(let outro) = parts[2].kind else {
        Issue.record("expected third part to be markdown, got \(parts[2].kind)")
        return
    }
    #expect(outro.trimmingCharacters(in: .whitespacesAndNewlines) == "Let me know if you need help formatting anything else!")
}

@Test func caseInsensitiveTagsAreRecognized() {
    let text = "<DETAILS><SUMMARY>Shout</SUMMARY>content</DETAILS>"
    let parts = MessageContentParser.parse(text)
    #expect(parts.count == 1)
    #expect(parts[0].kind == .details(summary: "Shout", content: "content"))
}

@Test func emptyStringProducesSingleEmptyMarkdownPart() {
    let parts = MessageContentParser.parse("")
    #expect(parts.count == 1)
    #expect(parts[0].kind == .markdown(""))
}
