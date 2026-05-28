import Foundation

@MainActor
class MockState {
    func run() async {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["opencode", "serve", "--port", "8774"]
        try! p.run()
        sleep(2)

        let url = URL(string: "http://localhost:8774/event")!
        var req = URLRequest(url: url)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        
        Task {
            let (bytes, _) = try! await URLSession.shared.bytes(for: req)
            var pendingLines = [String]()
            for try await line in bytes.lines {
                if line.isEmpty {
                    print("EVENT:", pendingLines)
                    pendingLines.removeAll()
                } else {
                    pendingLines.append(line)
                }
            }
        }
        
        sleep(1)
        var postReq = URLRequest(url: URL(string: "http://localhost:8774/session")!)
        postReq.httpMethod = "POST"
        postReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        postReq.httpBody = try! JSONEncoder().encode(["title": "Test"])
        let (data, _) = try! await URLSession.shared.data(for: postReq)
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let sessionID = json["id"] as! String

        sleep(1)
        var promptReq = URLRequest(url: URL(string: "http://localhost:8774/session/\(sessionID)/prompt_async")!)
        promptReq.httpMethod = "POST"
        promptReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        promptReq.httpBody = try! JSONEncoder().encode(["parts": [["type": "text", "text": "say 'ping' and nothing else"]]])
        let _ = try! await URLSession.shared.data(for: promptReq)
        
        sleep(3)
        p.terminate()
        exit(0)
    }
}
Task { @MainActor in
    await MockState().run()
}
RunLoop.main.run()
