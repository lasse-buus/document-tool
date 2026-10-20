import AppKit

/// Watches for files being dragged anywhere on the Mac (Finder, Desktop, other apps).
/// While a file drag is in progress and the trigger key is held, it shows the ring.
///
/// How it works:
/// - A global monitor sees `leftMouseDragged` events from every app (no permission needed for mouse events).
/// - When a drag starts, the system "drag pasteboard" changes. If it holds file URLs, it's a file drag.
/// - While the drag lasts, a timer checks the held modifier keys and whether the mouse is still down.
@MainActor
final class DragMonitor {
    private let store: ConfigStore
    private let ring: RingController

    private var dragMonitor: Any?
    private var lastChangeCount = NSPasteboard(name: .drag).changeCount
    private var sessionFiles: [URL]?
    private var pollTimer: Timer?

    init(store: ConfigStore, ring: RingController) {
        self.store = store
        self.ring = ring
    }

    func start() {
        guard dragMonitor == nil else { return }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            self?.handleDragEvent()
        }
    }

    func stop() {
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        dragMonitor = nil
        endSession()
    }

    private func handleDragEvent() {
        if sessionFiles == nil {
            let pb = NSPasteboard(name: .drag)
            guard pb.changeCount != lastChangeCount else { return }
            lastChangeCount = pb.changeCount
            let urls = pb.readObjects(forClasses: [NSURL.self],
                                      options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            guard !urls.isEmpty else { return }
            beginSession(urls)
        }
        tick()
    }

    private func beginSession(_ urls: [URL]) {
        sessionFiles = urls
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard let files = sessionFiles else { return }

        // Mouse released -> the drag is over (dropped on the ring or anywhere else).
        if NSEvent.pressedMouseButtons & 1 == 0 {
            endSession()
            return
        }

        guard let trigger = store.config.trigger else { return }
        let held = trigger.matches(NSEvent.modifierFlags)

        if held && !ring.isVisible {
            ring.show(files: files, at: NSEvent.mouseLocation)
        } else if !held && ring.isVisible && !ring.isDropping {
            // Letting go of the key cancels.
            ring.hide()
        }
    }

    private func endSession() {
        pollTimer?.invalidate()
        pollTimer = nil
        sessionFiles = nil
        lastChangeCount = NSPasteboard(name: .drag).changeCount
        // Give the drop a moment to be delivered before hiding.
        if ring.isVisible {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [ring] in
                MainActor.assumeIsolated { ring.hide() }
            }
        }
    }
}
