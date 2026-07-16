import Carbon.HIToolbox
import Foundation

struct HotKeyConfiguration: Codable, Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let displayName: String

    static let controlZ = HotKeyConfiguration(
        keyCode: UInt32(kVK_ANSI_Z),
        carbonModifiers: UInt32(controlKey),
        displayName: "⌃Z"
    )

    static let controlPeriod = HotKeyConfiguration(
        keyCode: UInt32(kVK_ANSI_Period),
        carbonModifiers: UInt32(controlKey),
        displayName: "⌃."
    )

    static let controlComma = HotKeyConfiguration(
        keyCode: UInt32(kVK_ANSI_Comma),
        carbonModifiers: UInt32(controlKey),
        displayName: "⌃,"
    )
}

enum PinnyHotKey: UInt32, CaseIterable {
    case togglePin = 1
    case hideWindow = 2
    case showWindow = 3
}
