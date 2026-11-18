import Foundation
import os

enum Log {
    private static let subsystem = "br.dinsights.iedge"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let edge = Logger(subsystem: subsystem, category: "edge")
    static let sidebar = Logger(subsystem: subsystem, category: "sidebar")
    static let actions = Logger(subsystem: subsystem, category: "actions")
    static let clipboard = Logger(subsystem: subsystem, category: "clipboard")
    static let settings = Logger(subsystem: subsystem, category: "settings")
    static let snapshot = Logger(subsystem: subsystem, category: "snapshot")
}
