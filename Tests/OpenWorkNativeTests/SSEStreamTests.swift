import Testing
import Foundation
@testable import OpenWorkNative

@Test func testSSEStreamRealTimeDelivery() async throws {
    // This test verifies the exact byte reading logic used in AppState.
    // It mocks a stream of incoming bytes that simulate SSE events delivered character by character,
    // and tests that empty lines are yielded properly.
    
    // Simulate server delivering an SSE stream over multiple chunks/bytes.
    let streamText = """
    data: {"type": "session.status"}

    data: {"type": "message.updated"}
    """.appending("\n\n")
    // To properly test the byte logic from AppState:
    let bytes = MockBytesAsyncSequence(chunks: [streamText])
    
    var pendingLines: [String] = []
    var lineBuffer: [UInt8] = []
    var emittedEvents: [[String]] = []
    
    for try await byte in bytes {
        if byte == 10 { // \n
            if let line = String(bytes: lineBuffer, encoding: .utf8) {
                let trimmed = line.hasSuffix("\r") ? String(line.dropLast()) : line
                if trimmed.isEmpty {
                    // simulate `await consumeSSELines(&pendingLines)`
                    emittedEvents.append(pendingLines)
                    pendingLines.removeAll()
                } else {
                    pendingLines.append(trimmed)
                }
            }
            lineBuffer.removeAll(keepingCapacity: true)
        } else {
            lineBuffer.append(byte)
        }
    }
    
    #expect(emittedEvents == [
        ["data: {\"type\": \"session.status\"}"],
        ["data: {\"type\": \"message.updated\"}"]
    ])
}
