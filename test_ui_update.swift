import Foundation

class AppState: ObservableObject {
    @Published var messages: [[String]] = [[]]

    func update() {
        messages[0].append("Hello")
        messages[0][0] += " World"
    }
}
let a = AppState()
var cancels = [Any]()
cancels.append(a.objectWillChange.sink { _ in
    print("WILL CHANGE!")
})
a.update()
