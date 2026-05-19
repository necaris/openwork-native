import Foundation
import Testing
@testable import OpenWorkNative

@Test func decodesPermissionAskedEvent() throws {
    let data = #"""
    {
      "type": "permission.asked",
      "properties": {
        "id": "per_1",
        "sessionID": "ses_1",
        "permission": "bash",
        "patterns": ["swift test", "swift build"],
        "metadata": { "reason": "verify changes" },
        "always": []
      }
    }
    """#.data(using: .utf8)!

    let event = try JSONDecoder().decode(OpenCodeEvent.self, from: data)
    let request = event.permissionRequest

    #expect(request?.id == "per_1")
    #expect(request?.sessionID == "ses_1")
    #expect(request?.action == "bash")
    #expect(request?.target == "swift test, swift build")
    #expect(request?.reason == "reason: verify changes")
}

@Test func permissionUpdatedEventIsNotDecoded() throws {
    let data = #"""
    {"type":"permission.updated","properties":{"id":"perm-1"}}
    """#.data(using: .utf8)!
    let event = try JSONDecoder().decode(OpenCodeEvent.self, from: data)
    #expect(event.permissionRequest == nil)
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
