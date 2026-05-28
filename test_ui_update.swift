import Foundation

class AppState: ObservableObject {
    @Published var messages: [[String]] = [[]]

    func update() {
        var copy = messages
        copy[0].append("Hello")
        messages = copy
    }
}
let a = AppState()
var cancels = [Any]()
cancels.append(a.objectWillChange.sink { _ in
    print("WILL CHANGE!")
})
a.update()
