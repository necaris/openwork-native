import Foundation
import Testing
@testable import OpenWorkNative

@Test func decodesPermissionUpdatedEvent() throws {
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

    #expect(request?.id == "perm-1")
    #expect(request?.sessionID == "session-1")
    #expect(request?.action == "Run shell command")
    #expect(request?.target == "swift test")
    #expect(request?.reason == "reason: verify changes")
}

@Test func decodesTodoUpdatedEvent() throws {
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

    #expect(todos?.first?.title == "Write tests")
    #expect(todos?.first?.state == "completed")
    #expect(todos?.first?.detail == "high")
}
