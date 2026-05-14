import Foundation

struct SSEParser {
    static func events(from lines: [String]) -> [String] {
        var events: [String] = []
        var dataLines: [String] = []

        for line in lines {
            if line.isEmpty {
                if !dataLines.isEmpty {
                    events.append(dataLines.joined(separator: "\n"))
                    dataLines.removeAll()
                }
                continue
            }

            if line.hasPrefix("data:") {
                let start = line.index(line.startIndex, offsetBy: 5)
                var value = String(line[start...])
                if value.hasPrefix(" ") {
                    value.removeFirst()
                }
                dataLines.append(value)
            }
        }

        if !dataLines.isEmpty {
            events.append(dataLines.joined(separator: "\n"))
        }

        return events
    }
}
