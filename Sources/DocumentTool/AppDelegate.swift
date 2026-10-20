import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ConfigStore.shared
    private var statusItem: NSStatusItem?
    private var ring: RingController?
    private var monitor: DragMonitor?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let ring = RingController(store: store)
        let monitor = DragMonitor(store: store, ring: ring)
        monitor.start()
        self.ring = ring
        self.monitor = monitor

        setUpStatusItem()

        if store.config.trigger == nil {
            showOnboarding()
        }
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "smallcircle.filled.circle", accessibilityDescription: "Document Tool")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        rebuildMenu(menu)
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let keyText = store.config.trigger.map { "Hold \($0.display) while dragging a file" } ?? "No key set yet"
        let info = NSMenuItem(title: keyText, action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Run setup again…", action: #selector(openOnboarding), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Document Tool", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    // MARK: Windows

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store)))
            window.title = "Document Tool Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        present(settingsWindow!)
    }

    @objc private func openOnboarding() { showOnboarding() }

    private func showOnboarding() {
        if onboardingWindow == nil {
            let view = OnboardingView(store: store) { [weak self] in
                self?.onboardingWindow?.close()
                if let key = self?.store.config.trigger {
                    Toast.show("All set! Drag a file and hold \(key.display)",
                               symbol: "checkmark.circle.fill", near: NSEvent.mouseLocation)
                }
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Welcome to Document Tool"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            onboardingWindow = window
        }
        present(onboardingWindow!)
    }

    private func present(_ window: NSWindow) {
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated { rebuildMenu(menu) }
    }
}
