import Foundation
import XCTest
@testable import OpenWorkNative

final class OpenCodeEventTests: XCTestCase {
    func testDecodesPermissionUpdatedEvent() throws {
        let data = #"""
        {
          "type": "permission.updated",
          "properties": {
            "id": "perm-1",
            "sessionID": "session-1",
            "type": "bash",
            "title": "Run shell command",
            "pattern": "swift test",
            "metadata": { "reason": "verify changes" }
          }
        }
        """#.data(using: .utf8)!

        let event = try JSONDecoder().decode(OpenCodeEvent.self, from: data)
        let request = event.permissionRequest

        XCTAssertEqual(request?.id, "perm-1")
        XCTAssertEqual(request?.sessionID, "session-1")
        XCTAssertEqual(request?.action, "Run shell command")
        XCTAssertEqual(request?.target, "swift test")
        XCTAssertEqual(request?.reason, "reason: verify changes")
    }

    func testDecodesTodoUpdatedEvent() throws {
        let data = #"""
        {
          "type": "todo.updated",
          "properties": {
            "sessionID": "session-1",
            "todos": [
              { "id": "todo-1", "content": "Write tests", "status": "completed", "priority": "high" }
            ]
          }
        }
        """#.data(using: .utf8)!

        let event = try JSONDecoder().decode(OpenCodeEvent.self, from: data)
        let todos = event.todos

        XCTAssertEqual(todos?.first?.title, "Write tests")
        XCTAssertEqual(todos?.first?.state, "completed")
        XCTAssertEqual(todos?.first?.detail, "high")
    }
}
