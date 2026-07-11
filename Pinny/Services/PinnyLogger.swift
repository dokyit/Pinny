import Foundation
import OSLog

enum PinnyLogger {
    private static let subsystem = "com.pinnyutility.Pinny"

    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let hotKey = Logger(subsystem: subsystem, category: "hotkey")
    static let accessibility = Logger(subsystem: subsystem, category: "accessibility")
    static let window = Logger(subsystem: subsystem, category: "window")
    static let loginItem = Logger(subsystem: subsystem, category: "login-item")
}
