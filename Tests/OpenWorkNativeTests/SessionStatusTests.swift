import Foundation
import Testing
@testable import OpenWorkNative

@Test func decodesSessionWithCostTokensAndModel() throws {
    let data = #"""
    {
      "id": "ses_1",
      "title": "smoke",
      "cost": 0.0431,
      "tokens": { "input": 1024, "output": 256, "reasoning": 12, "cache": { "read": 4, "write": 1 } },
      "model": { "id": "mercury-edit-2", "providerID": "inception", "variant": "default" },
      "time": { "created": 1779152995626, "updated": 1779152995736 }
    }
    """#.data(using: .utf8)!

    let api = try JSONDecoder().decode(APISession.self, from: data)
    let session = api.appModel

    #expect(session.cost == 0.0431)
    #expect(session.tokens.input == 1024)
    #expect(session.tokens.output == 256)
    #expect(session.tokens.reasoning == 12)
    #expect(session.tokens.cacheRead == 4)
    #expect(session.tokens.cacheWrite == 1)
    #expect(session.model?.modelID == "mercury-edit-2")
    #expect(session.model?.providerID == "inception")
}

@Test func decodesUserMessageInfoWithNestedModel() throws {
    let data = #"""
    {
      "info": {
        "id": "msg_u",
        "role": "user",
        "time": { "created": 1779152995671 },
        "agent": "build",
        "model": { "providerID": "inception", "modelID": "mercury-edit-2" }
      },
      "parts": [{ "type": "text", "text": "Hi" }]
    }
    """#.data(using: .utf8)!

    let envelope = try JSONDecoder().decode(APIMessageEnvelope.self, from: data)
    let message = envelope.appModel

    #expect(message.role == .user)
    #expect(message.model?.modelID == "mercury-edit-2")
    #expect(message.model?.providerID == "inception")
    #expect(message.tokens == nil)
    #expect(message.cost == nil)
    #expect(message.errorMessage == nil)
}

@Test func decodesAssistantMessageInfoWithFlatModelAndError() throws {
    let data = #"""
    {
      "info": {
        "id": "msg_a",
        "role": "assistant",
        "time": { "created": 1779152995676, "completed": 1779152996202 },
        "cost": 0.0061,
        "tokens": { "input": 1204, "output": 318, "reasoning": 0, "cache": { "read": 0, "write": 0 } },
        "modelID": "mercury-edit-2",
        "providerID": "inception",
        "error": {
          "name": "APIError",
          "data": { "message": "Bad Request: Model must be one of the following" }
        }
      },
      "parts": [{ "type": "text", "text": "Sorry" }]
    }
    """#.data(using: .utf8)!

    let envelope = try JSONDecoder().decode(APIMessageEnvelope.self, from: data)
    let message = envelope.appModel

    #expect(message.role == .assistant)
    #expect(message.model?.modelID == "mercury-edit-2")
    #expect(message.model?.providerID == "inception")
    #expect(message.tokens?.input == 1204)
    #expect(message.tokens?.output == 318)
    #expect(message.cost == 0.0061)
    let expectedLatency: TimeInterval = (1779152996202 - 1779152995676) / 1000
    #expect(abs((message.latency ?? 0) - expectedLatency) < 0.001)
    #expect(message.errorMessage?.contains("Bad Request") == true)
}

@Test func sessionWithoutOptionalFieldsDecodes() throws {
    let data = #"""
    {
      "id": "ses_2",
      "title": "minimal",
      "time": { "created": 1710000000000 }
    }
    """#.data(using: .utf8)!

    let api = try JSONDecoder().decode(APISession.self, from: data)
    let session = api.appModel

    #expect(session.cost == 0)
    #expect(session.tokens == TokenUsage())
    #expect(session.model == nil)
}

@Test func countFormatterAbbreviates() {
    #expect(CountFormatter.abbreviated(0) == "0")
    #expect(CountFormatter.abbreviated(847) == "847")
    #expect(CountFormatter.abbreviated(1_000) == "1K")
    #expect(CountFormatter.abbreviated(1_234) == "1.2K")
    #expect(CountFormatter.abbreviated(34_567) == "34.6K")
    #expect(CountFormatter.abbreviated(120_000) == "120K")
    #expect(CountFormatter.abbreviated(2_000_000) == "2M")
    #expect(CountFormatter.abbreviated(1_440_000_000) == "1.4B")
    #expect(CountFormatter.abbreviated(1_450_000_000) == "1.5B")
}

@Test func countFormatterUsdSwitchesPrecisionAtPenny() {
    #expect(CountFormatter.usd(0) == "$0.00")
    #expect(CountFormatter.usd(0.0034) == "$0.0034")
    #expect(CountFormatter.usd(1.23) == "$1.23")
}

@Test func countFormatterLatencyChoosesUnit() {
    #expect(CountFormatter.latency(0.087) == "87ms")
    #expect(CountFormatter.latency(1.23) == "1.2s")
}
