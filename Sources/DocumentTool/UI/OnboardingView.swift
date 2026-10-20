import SwiftUI

/// First-run setup: explains the idea and asks for the trigger key.
struct OnboardingView: View {
    @ObservedObject var store: ConfigStore
    var onFinish: () -> Void

    @State private var step = 0

    var body: some View {
        VStack(spacing: 22) {
            if step == 0 { intro } else { pickKey }
        }
        .padding(36)
        .frame(width: 460, height: 440)
    }

    private var intro: some View {
        VStack(spacing: 18) {
            Spacer()
            RingPreview()
                .frame(width: 190, height: 190)
            Text("Document Tool")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Drag any file, hold your key, and a ring of actions appears under the cursor. Drop the file on an action — convert, share, compress, make a snippet and more.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Set up my key") { withAnimation { step = 1 } }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var pickKey: some View {
        VStack(spacing: 18) {
            Text("Choose your key")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("This is the key you hold while dragging a file to open the ring. Pick one you don't use for anything else while dragging — Control or Fn work well.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            KeyRecorder(trigger: $store.config.trigger)
            Spacer()
            HStack {
                Button("Back") { withAnimation { step = 0 } }
                Spacer()
                Button("Done") { onFinish() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(store.config.trigger == nil)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// Static mini version of the ring for the welcome screen.
private struct RingPreview: View {
    private let items = DefaultActions.items(for: .pdf)

    var body: some View {
        RingFace(items: items, highlighted: 0, category: .pdf, fileCount: 1)
    }
}
