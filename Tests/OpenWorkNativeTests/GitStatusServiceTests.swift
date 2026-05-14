import XCTest
@testable import OpenWorkNative

final class GitStatusServiceTests: XCTestCase {
    func testParsesPorcelainStatuses() {
        let files = GitStatusService.parsePorcelain("""
         M Sources/App.swift
        A  Sources/New.swift
        D  Sources/Old.swift
        ?? README.md
        R  Before.swift -> After.swift
        """)

        XCTAssertEqual(files, [
            ChangedFile(path: "Sources/App.swift", status: "modified"),
            ChangedFile(path: "Sources/New.swift", status: "added"),
            ChangedFile(path: "Sources/Old.swift", status: "deleted"),
            ChangedFile(path: "README.md", status: "untracked"),
            ChangedFile(path: "After.swift", status: "renamed")
        ])
    }
}
