import Foundation

var properties: [String: Any] = [
    "info": [
        "time": [
            "completed": 123456
        ]
    ]
]
let info = properties["info"] as? [String: Any]
let completed = info?["time"] as? [String: Any]
print(completed?["completed"] != nil)
