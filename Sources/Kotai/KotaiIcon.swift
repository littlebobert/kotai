import AppKit
import SwiftUI

enum KotaiIcon {
    static let image: NSImage = {
        if let pngURL = Bundle.main.url(
            forResource: "KotaiIcon",
            withExtension: "png"
        ), let pngImage = NSImage(contentsOf: pngURL) {
            return pngImage
        }

        if let iconURL = Bundle.main.url(
            forResource: "Kotai",
            withExtension: "icns"
        ), let iconImage = NSImage(contentsOf: iconURL) {
            return iconImage
        }

        return NSImage(
            systemSymbolName: "signpost.right.and.left.circle",
            accessibilityDescription: String(localized: "Kotai")
        ) ?? NSImage(size: NSSize(width: 64, height: 64))
    }()

    static let dockImage: NSImage = {
        let canvasSize = NSSize(width: 1_024, height: 1_024)
        let artworkScale = 0.86
        let artworkSize = NSSize(
            width: canvasSize.width * artworkScale,
            height: canvasSize.height * artworkScale
        )
        let artworkOrigin = NSPoint(
            x: (canvasSize.width - artworkSize.width) / 2,
            y: (canvasSize.height - artworkSize.height) / 2
        )
        let dockImage = NSImage(size: canvasSize)

        dockImage.lockFocus()
        image.draw(
            in: NSRect(origin: artworkOrigin, size: artworkSize),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        dockImage.unlockFocus()

        return dockImage
    }()
}

struct KotaiIconView: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: KotaiIcon.image)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}
