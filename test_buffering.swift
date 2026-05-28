import Foundation

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
p.arguments = ["opencode", "serve", "--port", "8772"]
try! p.run()
sleep(2)

let url = URL(string: "http://localhost:8772/event")!
var req = URLRequest(url: url)
req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

Task {
    do {
        let (bytes, _) = try await URLSession.shared.bytes(for: req)
        for try await line in bytes.lines {
            print("LINE:", line)
        }
    } catch {
        print("ERR:", error)
    }
}

// Trigger an event to see if it arrives!
Task {
    sleep(1)
    var postReq = URLRequest(url: URL(string: "http://localhost:8772/session")!)
    postReq.httpMethod = "POST"
    postReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
    postReq.httpBody = try! JSONEncoder().encode(["title": "Test"])
    let (data, _) = try! await URLSession.shared.data(for: postReq)
    let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    let sessionID = json["id"] as! String

    sleep(1)
    var promptReq = URLRequest(url: URL(string: "http://localhost:8772/session/\(sessionID)/prompt_async")!)
    promptReq.httpMethod = "POST"
    promptReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
    promptReq.httpBody = try! JSONEncoder().encode(["parts": [["type": "text", "text": "hi"]]])
    let _ = try! await URLSession.shared.data(for: promptReq)
}

RunLoop.main.run(until: Date(timeIntervalSinceNow: 5))
p.terminate()
