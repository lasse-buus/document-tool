import AppKit
import SwiftUI

/// State shared between the AppKit drop view and the SwiftUI ring.
@MainActor
final class RingState: ObservableObject {
    @Published var items: [ActionItem] = []
    @Published var category: FileCategory = .other
    @Published var fileCount = 0
    @Published var highlighted: Int?
    @Published var appeared = false
}

enum RingGeometry {
    static let size: CGFloat = 300           // panel size, leaves room for the shadow
    static let outerRadius: CGFloat = 112
    static let innerRadius: CGFloat = 40     // the center = cancel
    static let iconRadius: CGFloat = 76

    /// Slice index for a point relative to the center (y up, AppKit coordinates).
    /// Picks by direction, like the window-snapping ring: anything outside the
    /// center circle selects the slice in that direction.
    static func slice(dx: CGFloat, dy: CGFloat, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let distance = sqrt(dx * dx + dy * dy)
        guard distance > innerRadius else { return nil }
        // Compass angle: 0° = up, 90° = right (clockwise).
        var angle = atan2(dx, dy) * 180 / .pi
        if angle < 0 { angle += 360 }
        let span = 360 / Double(count)
        let shifted = (Double(angle) + span / 2).truncatingRemainder(dividingBy: 360)
        return min(Int(shifted / span), count - 1)
    }
}

/// Owns the floating panel that shows the ring under the cursor.
@MainActor
final class RingController {
    private let store: ConfigStore
    private let state = RingState()
    private lazy var panel: RingPanel = makePanel()
    private(set) var isVisible = false
    private(set) var isDropping = false

    init(store: ConfigStore) {
        self.store = store
    }

    func show(files: [URL], at point: NSPoint) {
        let category = FileCategory.detect(files)
        state.category = category
        state.items = store.items(for: category)
        state.fileCount = files.count
        state.highlighted = nil
        state.appeared = false

        // Center on the cursor, but keep it on screen.
        let size = RingGeometry.size
        var origin = NSPoint(x: point.x - size / 2, y: point.y - size / 2)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) {
            let f = screen.frame
            origin.x = max(f.minX, min(origin.x, f.maxX - size))
            origin.y = max(f.minY, min(origin.y, f.maxY - size))
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        isVisible = true
        isDropping = false

        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
            state.appeared = true
        }
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        isDropping = false
        state.highlighted = nil
        state.appeared = false
        panel.orderOut(nil)
    }

    private func makePanel() -> RingPanel {
        let panel = RingPanel(size: RingGeometry.size)
        let dropView = RingDropView(state: state)
        dropView.onDropStarted = { [weak self] in self?.isDropping = true }
        dropView.onDrop = { [weak self] index, urls in
            self?.handleDrop(index: index, urls: urls)
        }
        let container = NSView(frame: dropView.bounds)
        let host = NSHostingView(rootView: RingView(state: state))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        host.unregisterDraggedTypes()
        dropView.autoresizingMask = [.width, .height]
        // The drop view sits on top of the SwiftUI view so it always receives the drag.
        container.addSubview(host)
        container.addSubview(dropView)
        panel.contentView = container
        return panel
    }

    private func handleDrop(index: Int, urls: [URL]) {
        guard state.items.indices.contains(index) else { hide(); return }
        let item = state.items[index]
        let point = NSEvent.mouseLocation
        hide()
        ActionRunner.run(item, urls: urls, near: point)
    }
}

/// Transparent, borderless panel that floats above everything and never takes focus.
final class RingPanel: NSPanel {
    init(size: CGFloat) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The actual drop target. Works out which slice the cursor points at and receives the files.
final class RingDropView: NSView {
    private let state: RingState
    var onDrop: ((Int, [URL]) -> Void)?
    var onDropStarted: (() -> Void)?
    private var lastHighlighted: Int?

    init(state: RingState) {
        self.state = state
        super.init(frame: NSRect(x: 0, y: 0, width: RingGeometry.size, height: RingGeometry.size))
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func sliceIndex(for info: NSDraggingInfo) -> Int? {
        let p = convert(info.draggingLocation, from: nil)
        return RingGeometry.slice(dx: p.x - bounds.midX, dy: p.y - bounds.midY, count: state.items.count)
    }

    private func operation(for info: NSDraggingInfo, slice: Int?) -> NSDragOperation {
        guard slice != nil else { return [] }
        // Must return an operation the source allows. Finder changes it with modifier keys.
        let mask = info.draggingSourceOperationMask
        for op: NSDragOperation in [.copy, .generic, .link, .move] where mask.contains(op) {
            return op
        }
        return .copy
    }

    private func updateHighlight(_ index: Int?) {
        guard index != lastHighlighted else { return }
        lastHighlighted = index
        if index != nil {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        withAnimation(.easeOut(duration: 0.12)) { state.highlighted = index }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let index = sliceIndex(for: sender)
        updateHighlight(index)
        return operation(for: sender, slice: index)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let index = sliceIndex(for: sender)
        updateHighlight(index)
        return operation(for: sender, slice: index)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        updateHighlight(nil)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard sliceIndex(for: sender) != nil else { return false }
        onDropStarted?()
        return true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let index = sliceIndex(for: sender) else { return false }
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        lastHighlighted = nil
        // Run after the drag finishes so Finder isn't kept waiting.
        Task { @MainActor [weak self] in self?.onDrop?(index, urls) }
        return true
    }
}
