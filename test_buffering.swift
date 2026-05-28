import Foundation

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
p.arguments = ["opencode", "serve", "--port", "8772"]
try! p.run()
sleep(2)

let url = URL(string: "http://localhost:8772/event")!
var req = URLRequest(url: url)
req.setValue("application/json", forHTTPHeaderField: "Accept")

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
    let _ = try! await URLSession.shared.data(for: postReq)
}

RunLoop.main.run(until: Date(timeIntervalSinceNow: 5))
p.terminate()
