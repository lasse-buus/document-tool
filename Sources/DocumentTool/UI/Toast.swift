import AppKit
import SwiftUI

/// A small HUD bubble near the cursor confirming what happened.
@MainActor
enum Toast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ message: String, symbol: String, near point: NSPoint, isError: Bool = false) {
        panel?.orderOut(nil)
        hideWork?.cancel()

        let host = NSHostingView(rootView: ToastView(message: message, symbol: symbol, isError: isError))
        let size = host.fittingSize
        let p = panel ?? makePanel()
        p.setContentSize(size)
        p.contentView = host

        var origin = NSPoint(x: point.x - size.width / 2, y: point.y - size.height - 24)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) {
            let f = screen.visibleFrame
            origin.x = max(f.minX + 8, min(origin.x, f.maxX - size.width - 8))
            origin.y = max(f.minY + 8, min(origin.y, f.maxY - size.height - 8))
        }
        p.setFrameOrigin(origin)
        p.alphaValue = 1
        p.orderFrontRegardless()
        panel = p

        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.25
                    p.animator().alphaValue = 0
                }, completionHandler: {
                    MainActor.assumeIsolated { p.orderOut(nil) }
                })
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (isError ? 4 : 2.2), execute: work)
    }

    private static func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .popUpMenu
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        return p
    }
}

private struct ToastView: View {
    let message: String
    let symbol: String
    let isError: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isError ? Color.red : Color.green)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 280, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.1)))
        .padding(12)
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    }
}
