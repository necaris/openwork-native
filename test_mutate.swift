import Foundation

struct Part: Equatable { let id: String; var text: String }
struct Msg: Equatable { let id: String; var parts: [Part] }
struct Sess: Equatable { let id: String; var msgs: [Msg] }

var sessions = [Sess(id: "1", msgs: [Msg(id: "m1", parts: [Part(id: "p1", text: "A")])])]

func upsert(delta: String) {
    var session = sessions[0]
    defer { sessions[0] = session }
    
    session.msgs[0].parts[0].text += delta
}

upsert(delta: " B")
print(sessions[0].msgs[0].parts[0].text)
