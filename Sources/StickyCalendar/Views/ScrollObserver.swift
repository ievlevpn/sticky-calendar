import AppKit
import SwiftUI

/// Reports what part of the enclosing `NSScrollView`'s document is visible whenever it
/// scrolls or resizes: the top offset and height, excluding the scroll view's top inset
/// (SwiftUI extends the scroll view under the header and insets it by the header height).
/// SwiftUI's own preference-based offset tracking doesn't update during scrolling on macOS 14.
struct ScrollObserver: NSViewRepresentable {
    let onChange: (_ offset: CGFloat, _ height: CGFloat) -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        nsView.onChange = onChange
    }

    final class ObserverView: NSView {
        var onChange: ((CGFloat, CGFloat) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let scrollView = enclosingScrollView else { return }
            let clip = scrollView.contentView
            clip.postsBoundsChangedNotifications = true
            for name in [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: clip, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.report() }
                })
            }
            DispatchQueue.main.async { [weak self] in self?.report() }
        }

        private func report() {
            guard let scrollView = enclosingScrollView else { return }
            let visible = scrollView.contentView.documentVisibleRect
            let topInset = scrollView.contentInsets.top
            onChange?(visible.minY + topInset, visible.height - topInset)
        }
    }
}
