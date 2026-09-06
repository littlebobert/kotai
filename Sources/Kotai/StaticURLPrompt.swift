import AppKit
import SwiftUI

enum StaticURLPrompt {
    static var fieldPrompt: Text {
        Text("Paste your ngrok static domain URL")
            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
    }

    static var example: Text {
        Text("Example: https://example.ngrok.app")
    }
}
