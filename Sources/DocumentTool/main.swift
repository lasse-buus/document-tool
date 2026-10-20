import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Menu bar app: no Dock icon (also set via LSUIElement when bundled).
    app.setActivationPolicy(.accessory)
    app.run()
}
