import Testing
@testable import CNCKit

@Suite("Knowledge base")
struct KnowledgeBaseTests {
    let kb = KnowledgeBase(markdownFiles: [
        ("troubleshooting.md", """
        # Troubleshooting
        ## Chatter
        Vibration marks from too much stickout or depth of cut.
        ## Tool breakage
        Snapping bits from aggressive depth or slow feed.
        """),
        ("materials.md", """
        # Materials
        ## MDF
        Burn marks happen when the bit rubs; increase feed.
        """),
    ])

    @Test func parsesSections() {
        #expect(kb.sections.map(\.title) == ["Chatter", "Tool breakage", "MDF"])
    }

    @Test func ranksTheRelevantSectionFirst() {
        #expect(kb.search("why is my aluminum cut chattering").first?.title == "Chatter")
        #expect(kb.search("burn marks on MDF").first?.title == "MDF")
        #expect(kb.search("my bit keeps snapping").first?.title == "Tool breakage")
    }

    @Test func emptyQueryReturnsNothing() {
        #expect(kb.search("the and of").isEmpty)
    }
}
