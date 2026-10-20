import AppKit
import SwiftUI

/// Records a trigger key: click, then press and release the key(s) you want.
/// Supports ⌃ ⌥ ⇧ ⌘ fn and combinations of them.
struct KeyRecorder: View {
    @Binding var trigger: TriggerKey?
    @StateObject private var recorder = KeyRecorderModel()

    var body: some View {
        VStack(spacing: 10) {
            Button {
                if recorder.isRecording {
                    recorder.stop()
                } else {
                    recorder.start(onDone: { trigger = $0 })
                }
            } label: {
                Text(label)
                    .font(.system(size: recorder.isRecording || trigger == nil ? 15 : 26, weight: .semibold, design: .rounded))
                    .frame(minWidth: 180, minHeight: 64)
                    .padding(.horizontal, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(recorder.isRecording ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(recorder.isRecording ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)

            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .onDisappear { recorder.stop() }
    }

    private var label: String {
        if recorder.isRecording {
            return recorder.preview.isEmpty ? "Press your key…" : recorder.preview
        }
        return trigger?.display ?? "Click to set key"
    }

    private var hint: String {
        if recorder.isRecording { return "Hold the key (or keys), then let go." }
        if let trigger {
            if trigger.flags.contains(.command) || trigger.flags.contains(.option) {
                return "\(trigger.spokenName). Note: Finder also uses ⌘/⌥ while dragging (move/copy). It still works, but ⌃ or fn avoids surprises."
            }
            return "\(trigger.spokenName). Click to change."
        }
        return "Modifier keys only: Control, Option, Shift, Command, Fn — or a combination."
    }
}

final class KeyRecorderModel: ObservableObject {
    @Published var isRecording = false
    @Published var preview = ""

    private var monitor: Any?
    private var peak: NSEvent.ModifierFlags = []
    private var onDone: ((TriggerKey) -> Void)?

    func start(onDone: @escaping (TriggerKey) -> Void) {
        stop()
        self.onDone = onDone
        peak = []
        preview = ""
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event.modifierFlags)
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    private func handle(_ flags: NSEvent.ModifierFlags) {
        let current = flags.intersection(TriggerKey.relevantMask)
        if !current.isEmpty {
            // Remember the biggest combination held at once.
            if current.isSuperset(of: peak) { peak = current }
            preview = TriggerKey(peak).display
        } else if !peak.isEmpty {
            // All keys released: done.
            let key = TriggerKey(peak)
            stop()
            onDone?(key)
        }
    }
}
