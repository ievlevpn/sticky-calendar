import SwiftUI

/// One action in an `UnfurlMenu`.
struct UnfurlItem: Identifiable {
    let id: String
    let symbol: String
    var isActive = false
    /// Shows a spinner instead of the symbol (a refresh in progress).
    var isBusy = false
    let name: String
    var shortcut = ""
    let action: () -> Void
}

/// A ••• button that, on hover, grows a glass capsule leftwards with the actions appearing
/// one after another, nearest first ("Unfurl", design 1a). A label under it names the hovered
/// action and its shortcut; clicking ••• keeps it open. `isOpen` lets the header fade what
/// the capsule covers.
struct UnfurlMenu: View {
    let items: [UnfurlItem]
    /// The header's width, so the capsule fits a narrow window.
    let availableWidth: CGFloat
    @Binding var isOpen: Bool

    @State private var isLocked = false
    @State private var hovered: String?
    @State private var overButton = false
    @State private var overCapsule = false
    @State private var closing: Task<Void, Never>?

    private static let itemSize: CGFloat = 24

    /// Distance between icons: 26, tighter when the window is too narrow for the capsule.
    private var step: CGFloat {
        let room = availableWidth - 24 - 4 - 30 // side padding, the capsule's overhang, the ••• end
        return min(26, max(20, room / CGFloat(max(items.count, 1))))
    }

    private var capsuleWidth: CGFloat { 30 + step * CGFloat(items.count) }

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 13, weight: .bold))
            .rotationEffect(.degrees(isOpen ? 90 : 0))
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isOpen)
            .foregroundStyle(isLocked ? Color.accentColor : Color.primary)
            .frame(width: 22, height: 24)
            .contentShape(Rectangle())
            .onTapGesture { toggleLock() }
            .help(isLocked ? "Close the menu" : "Keep the menu open")
            .accessibilityElement()
            .accessibilityLabel("More")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { toggleLock() }
            .onHover { overButton = $0; pointerMoved() }
            .background(alignment: .trailing) { capsule }
            .overlay(alignment: .topTrailing) { label }
    }

    /// The glass capsule, growing left out of the ••• button, with the actions inside.
    private var capsule: some View {
        ZStack(alignment: .trailing) {
            Capsule()
                .fill(.regularMaterial)
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
                .shadow(color: .black.opacity(isOpen ? 0.25 : 0), radius: 8, y: 4)
                .frame(width: isOpen ? capsuleWidth : 28, height: 28)
                .opacity(isOpen ? 1 : 0)
                .animation(.spring(response: 0.42, dampingFraction: 0.68), value: isOpen)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                button(item, index: index)
                    // From the capsule's end: past the ••• end, then one step per icon.
                    .padding(.trailing, 30 + CGFloat(index) * step + (step - Self.itemSize) / 2)
            }
        }
        .frame(width: capsuleWidth, height: 28, alignment: .trailing)
        .offset(x: 4) // overhangs the ••• button a little, as in the design
        .allowsHitTesting(isOpen)
        .onHover { overCapsule = $0; pointerMoved() }
    }

    private func button(_ item: UnfurlItem, index: Int) -> some View {
        let delay = isOpen ? Double(index) * 0.028 : Double(items.count - 1 - index) * 0.012
        return Button(action: item.action) {
            Group {
                if item.isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: item.symbol).font(.system(size: 12.5, weight: .medium))
                }
            }
            .frame(width: Self.itemSize, height: Self.itemSize)
            .foregroundStyle(item.isActive ? Color.accentColor : Color.primary)
            .background(Circle().fill(Color.primary.opacity(hovered == item.id ? 0.12 : 0)))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // Out of the Tab order (like the stickies' other icon buttons), so keyboard
        // navigation never leaves a focus ring stuck on one, even while the menu is closed.
        .focusable(false)
        .accessibilityLabel(item.name)
        .onHover { inside in
            if inside { hovered = item.id } else if hovered == item.id { hovered = nil }
        }
        .opacity(isOpen ? 1 : 0)
        .blur(radius: isOpen ? 0 : 3)
        .scaleEffect(isOpen ? 1 : 0.5)
        .offset(x: isOpen ? 0 : 14)
        .animation(.spring(response: 0.42, dampingFraction: 0.68).delay(delay), value: isOpen)
    }

    /// The hovered action's name and shortcut, just under the capsule.
    private var label: some View {
        let item = items.first { $0.id == hovered }
        return HStack(spacing: 6) {
            Text(item?.name ?? "").fontWeight(.semibold)
            if let key = item?.shortcut, !key.isEmpty {
                Text(key).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Capsule().fill(.regularMaterial).shadow(color: .black.opacity(0.2), radius: 6, y: 3))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
        .opacity(isOpen && item != nil ? 1 : 0)
        .animation(.easeOut(duration: 0.15), value: hovered)
        .animation(.easeOut(duration: 0.15), value: isOpen)
        .offset(x: 4, y: 30)
        .allowsHitTesting(false)
    }

    /// Only the ••• button opens the menu. The capsule's area spans much of the header even
    /// while it's hidden, so it only keeps an open menu open.
    private var pointerInside: Bool { overButton || (isOpen && overCapsule) }

    /// Opens while the pointer is over the button (or the open capsule); closes shortly after
    /// it leaves both (unless locked open).
    private func pointerMoved() {
        closing?.cancel()
        if pointerInside {
            isOpen = true
        } else {
            closing = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(260))
                guard !Task.isCancelled, !pointerInside else { return }
                hovered = nil
                if !isLocked { isOpen = false }
            }
        }
    }

    private func toggleLock() {
        isLocked.toggle()
        isOpen = isLocked || pointerInside
    }
}

extension View {
    /// Fades and nudges a header's leading content away while its menu is unfurled.
    func fadedWhileMenuOpen(_ isOpen: Bool) -> some View {
        opacity(isOpen ? 0 : 1)
            .blur(radius: isOpen ? 2 : 0)
            .offset(x: isOpen ? -6 : 0)
            .animation(.easeOut(duration: 0.22), value: isOpen)
            .allowsHitTesting(!isOpen)
    }
}
