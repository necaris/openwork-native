import Foundation
import Combine

struct Msg: Equatable {
    var content: String
}
struct Sess: Equatable {
    var msgs: [Msg]
}

class AppState: ObservableObject {
    @Published var sessions: [Sess] = [Sess(msgs: [Msg(content: "A")])]

    func update() {
        var session = sessions[0]
        defer { sessions[0] = session }
        session.msgs[0].content += " B"
    }
}
let a = AppState()
var cancels = [Any]()
cancels.append(a.objectWillChange.sink { _ in
    print("WILL CHANGE!")
})
a.update()
