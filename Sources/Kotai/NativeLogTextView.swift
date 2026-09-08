import AppKit
import SwiftUI

struct NativeLogTextView: NSViewRepresentable {
    let text: String
    @Binding var followsLatestEntry: Bool
    let scrollToLatestRequest: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(followsLatestEntry: $followsLatestEntry)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindPanel = true
        textView.isIncrementalSearchingEnabled = true
        textView.allowsUndo = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.autoresizingMask = [.width]
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        scrollView.documentView = textView

        context.coordinator.connect(scrollView: scrollView, textView: textView)
        context.coordinator.update(
            text: text,
            followsLatestEntry: followsLatestEntry,
            scrollToLatestRequest: scrollToLatestRequest
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(
            text: text,
            followsLatestEntry: followsLatestEntry,
            scrollToLatestRequest: scrollToLatestRequest
        )
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.disconnect()
    }

    @MainActor
    final class Coordinator: NSObject {
        private let followsLatestEntry: Binding<Bool>
        private weak var scrollView: NSScrollView?
        private weak var textView: NSTextView?
        private var boundsObserver: NSObjectProtocol?
        private var scrollWheelMonitor: Any?
        private var lastText = ""
        private var lastScrollToLatestRequest = 0
        private var isProgrammaticScroll = false

        init(followsLatestEntry: Binding<Bool>) {
            self.followsLatestEntry = followsLatestEntry
        }

        func connect(scrollView: NSScrollView, textView: NSTextView) {
            self.scrollView = scrollView
            self.textView = textView
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.visibleBoundsDidChange()
                }
            }
            scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(
                matching: .scrollWheel
            ) { [weak self] event in
                var handledEvent: NSEvent?
                MainActor.assumeIsolated {
                    handledEvent = self?.handleScrollWheelDuringSelection(event) ?? event
                }
                return handledEvent
            }
        }

        func disconnect() {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            if let scrollWheelMonitor {
                NSEvent.removeMonitor(scrollWheelMonitor)
            }
            boundsObserver = nil
            scrollWheelMonitor = nil
        }

        func update(
            text: String,
            followsLatestEntry: Bool,
            scrollToLatestRequest: Int
        ) {
            guard let textView else {
                return
            }

            let textChanged = text != lastText
            if textChanged {
                textView.string = text
                lastText = text
            }

            let explicitlyRequested = scrollToLatestRequest != lastScrollToLatestRequest
            lastScrollToLatestRequest = scrollToLatestRequest
            if explicitlyRequested || (textChanged && followsLatestEntry) {
                scrollToLatest()
            }
        }

        private func handleScrollWheelDuringSelection(_ event: NSEvent) -> NSEvent? {
            guard NSEvent.pressedMouseButtons & 1 == 1,
                  let scrollView,
                  let textView,
                  event.window === textView.window
            else {
                return event
            }

            let clipView = scrollView.contentView
            let documentHeight = scrollView.documentView?.bounds.height ?? 0
            let maximumY = max(0, documentHeight - clipView.bounds.height)
            let proposedY = clipView.bounds.origin.y - event.scrollingDeltaY
            let constrainedY = min(maximumY, max(0, proposedY))
            clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: constrainedY))
            scrollView.reflectScrolledClipView(clipView)
            return nil
        }

        private func visibleBoundsDidChange() {
            guard !isProgrammaticScroll else {
                return
            }
            let shouldFollow = isAtBottom
            if followsLatestEntry.wrappedValue != shouldFollow {
                followsLatestEntry.wrappedValue = shouldFollow
            }
        }

        private var isAtBottom: Bool {
            guard let scrollView, let documentView = scrollView.documentView else {
                return true
            }
            let visibleBottom = NSMaxY(scrollView.contentView.bounds)
            let documentBottom = NSMaxY(documentView.bounds)
            return documentBottom - visibleBottom <= 4
        }

        private func scrollToLatest() {
            guard let textView else {
                return
            }
            isProgrammaticScroll = true
            textView.scrollToEndOfDocument(nil)
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.isProgrammaticScroll = false
                self.followsLatestEntry.wrappedValue = true
            }
        }
    }
}
