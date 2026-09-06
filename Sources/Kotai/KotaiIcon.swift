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
