import Foundation
import os

enum AppLog {
    static let subsystem = "com.openwork.native"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let state = Logger(subsystem: subsystem, category: "state")
    static let process = Logger(subsystem: subsystem, category: "process")
    static let client = Logger(subsystem: subsystem, category: "client")
    static let events = Logger(subsystem: subsystem, category: "events")
    static let git = Logger(subsystem: subsystem, category: "git")
}
