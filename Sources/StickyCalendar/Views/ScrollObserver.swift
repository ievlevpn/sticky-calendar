import AppKit
import SwiftUI

/// A handle on the timeline's underlying `NSScrollView`, used to scroll it programmatically.
/// (`ScrollViewReader.scrollTo` on macOS 14 measured the whole content instead of the
/// target marker, so every jump landed at the anchor fraction of the full range.)
@MainActor
final class ScrollBridge {
    fileprivate weak var scrollView: NSScrollView?
    private var pending: ((Double) -> Double)?

    /// Scrolls so the offset returned for the viewport height is at the top of the visible
    /// area. Runs on the next runloop turn, after the layout triggered by the same update
    /// (e.g. the all-day strip appearing on a new day resizes the scroll view and would
    /// otherwise reset the position). Deferred until the scroll view exists.
    func scroll(animated: Bool, to offset: @escaping (_ viewportHeight: Double) -> Double) {
        DispatchQueue.main.async { self.apply(animated: animated, offset: offset) }
    }

    private func apply(animated: Bool, offset: @escaping (Double) -> Double) {
        guard let scrollView else {
            pending = offset
            return
        }
        let clip = scrollView.contentView
        let topInset = scrollView.contentInsets.top
        let origin = NSPoint(x: 0, y: offset(Double(clip.bounds.height - topInset)) - topInset)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                clip.animator().setBoundsOrigin(origin)
            } completionHandler: {
                MainActor.assumeIsolated { scrollView.reflectScrolledClipView(clip) }
            }
        } else {
            clip.setBoundsOrigin(origin)
            scrollView.reflectScrolledClipView(clip)
        }
    }

    fileprivate func attach(_ scrollView: NSScrollView) {
        self.scrollView = scrollView
        guard let offset = pending else { return }
        pending = nil
        scroll(animated: false, to: offset)
    }
}

/// Connects a `ScrollBridge` to the enclosing `NSScrollView` and reports what part of the
/// document is visible whenever it scrolls or resizes: the top offset and height, excluding
/// the scroll view's top inset (SwiftUI extends the scroll view under the header and insets
/// it by the header height). SwiftUI's preference-based offset tracking doesn't update
/// during scrolling on macOS 14.
struct ScrollObserver: NSViewRepresentable {
    let bridge: ScrollBridge
    let onChange: (_ offset: CGFloat, _ height: CGFloat) -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.bridge = bridge
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        nsView.bridge = bridge
        nsView.onChange = onChange
    }

    final class ObserverView: NSView {
        var bridge: ScrollBridge?
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
            bridge?.attach(scrollView)
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
