import AppKit
import ApplicationServices
import Foundation

@main
struct PinningProbe {
    static func main() {
        guard AXIsProcessTrusted() else {
            fputs("Accessibility permission is not granted to this probe host.\n", stderr)
            exit(2)
        }

        guard let application = NSWorkspace.shared.frontmostApplication else {
            fputs("No frontmost application.\n", stderr)
            exit(3)
        }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        var focusedValue: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedValue
        )
        guard focusedError == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            fputs("The frontmost application exposes no focused AX window (error \(focusedError.rawValue)).\n", stderr)
            exit(4)
        }

        let window = unsafeBitCast(focusedValue, to: AXUIElement.self)
        var attributesValue: CFArray?
        let attributesError = AXUIElementCopyAttributeNames(window, &attributesValue)
        let attributes = (attributesValue as? [String]) ?? []

        var actionsValue: CFArray?
        let actionsError = AXUIElementCopyActionNames(window, &actionsValue)
        let actions = (actionsValue as? [String]) ?? []

        let hypotheticalLevelAttribute = "AXWindowLevel" as CFString
        var levelSettable = DarwinBoolean(false)
        let levelError = AXUIElementIsAttributeSettable(
            window,
            hypotheticalLevelAttribute,
            &levelSettable
        )

        print("Application: \(application.localizedName ?? "Unknown")")
        print("PID: \(application.processIdentifier)")
        print("Attribute enumeration: \(attributesError.rawValue), count: \(attributes.count)")
        print("Action enumeration: \(actionsError.rawValue), actions: \(actions.sorted())")
        print("Public AXWindowLevel constant exists: false")
        print("Raw AXWindowLevel settable query: error \(levelError.rawValue), settable: \(levelSettable.boolValue)")
        print("AXRaise exposed: \(actions.contains(kAXRaiseAction as String))")
        print("Conclusion: no public Accessibility attribute can persistently change this foreign window's level.")

        if CommandLine.arguments.contains("--perform-raise") {
            let raiseError = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            print("One-shot AXRaise result: \(raiseError.rawValue) (not an always-on-top level change)")
        }
    }
}
