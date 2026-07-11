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
}
