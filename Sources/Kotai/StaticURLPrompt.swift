import AppKit
import SwiftUI

enum StaticURLPrompt {
    static var fieldPrompt: Text {
        Text("Paste your ngrok static domain or HTTPS URL")
            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
    }

    static var example: Text {
        Text("Example: example.ngrok.app or https://example.ngrok.app")
    }
}
