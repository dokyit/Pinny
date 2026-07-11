import AppKit
import Foundation

enum ResourceLocator {
    static func menuBarImage(assetName: String, fallbackFileName: String, symbolName: String) -> NSImage {
        if let image = NSImage(named: NSImage.Name(assetName)) {
            return configuredTemplateImage(image)
        }

        for bundle in resourceBundles {
            let directURL = bundle.url(forResource: fallbackFileName, withExtension: "png")
            let copiedDirectoryURL = bundle.url(
                forResource: fallbackFileName,
                withExtension: "png",
                subdirectory: "RuntimeAssets"
            )
            if let url = directURL ?? copiedDirectoryURL, let image = NSImage(contentsOf: url) {
                return configuredTemplateImage(image)
            }
        }

        let fallback = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Pinny") ?? NSImage()
        return configuredTemplateImage(fallback)
    }

    private static var resourceBundles: [Bundle] {
        #if SWIFT_PACKAGE
        return [Bundle.module, Bundle.main]
        #else
        return [Bundle.main]
        #endif
    }

    private static func configuredTemplateImage(_ image: NSImage) -> NSImage {
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}
