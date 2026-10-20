import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        TabView {
            ActionsSettings(store: store)
                .tabItem { Label("Actions", systemImage: "circle.grid.cross") }
            GeneralSettings(store: store)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 620, height: 520)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var store: ConfigStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Trigger key") {
                HStack {
                    Spacer()
                    KeyRecorder(trigger: $store.config.trigger)
                    Spacer()
                }
                .padding(.vertical, 6)
            }

            Section("Open in editor") {
                HStack {
                    Text(editorName)
                    Spacer()
                    Button("Choose…") {
                        if let url = AppPicker.pick() { store.config.favoriteEditorPath = url.path }
                    }
                    if store.config.favoriteEditorPath != nil {
                        Button("Auto") { store.config.favoriteEditorPath = nil }
                    }
                }
            }

            Section("Background & Snippet") {
                Picker("Gradient", selection: $store.config.gradient) {
                    ForEach(GradientPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                HStack(spacing: 8) {
                    ForEach(GradientPreset.allCases) { preset in
                        RoundedRectangle(cornerRadius: 6)
                            .fill(preset.gradient)
                            .frame(width: 44, height: 28)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.accentColor, lineWidth: store.config.gradient == preset ? 2.5 : 0)
                            )
                            .onTapGesture { store.config.gradient = preset }
                    }
                }
                Toggle("Copy the image to the clipboard", isOn: $store.config.copyImagesToClipboard)
            }

            Section("Compress images") {
                Slider(value: $store.config.imageQuality, in: 0.3...0.95, step: 0.05) {
                    Text("Quality \(Int(store.config.imageQuality * 100))%")
                }
            }

            Section("System") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var editorName: String {
        FileManager.default.displayName(atPath: FavoriteEditor.resolve(store.config.favoriteEditorPath).path)
            .replacingOccurrences(of: ".app", with: "")
            + (store.config.favoriteEditorPath == nil ? " (auto)" : "")
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change this: \(error.localizedDescription). It only works when running the built .app."
        }
    }
}

// MARK: - Actions

private struct ActionsSettings: View {
    @ObservedObject var store: ConfigStore
    @State private var category: FileCategory = .pdf
    @State private var customSheet: CustomKind?

    enum CustomKind: Identifiable {
        case shortcut, script
        var id: Int { self == .shortcut ? 0 : 1 }
    }

    private var items: [ActionItem] { store.items(for: category) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("File type", selection: $category) {
                ForEach(FileCategory.allCases) { cat in
                    Label(cat.title, systemImage: cat.symbol).tag(cat)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text("Slices for \(category.title) files, clockwise from the top. Drag to reorder. Up to \(ConfigStore.maxSlices).")
                .font(.callout)
                .foregroundStyle(.secondary)

            List {
                ForEach(items) { item in
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6).fill(item.color)
                            if let icon = item.appIcon {
                                Image(nsImage: icon).resizable().padding(3)
                            } else {
                                Image(systemName: item.symbol).foregroundStyle(.white)
                            }
                        }
                        .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                            if let subtitle = subtitle(for: item) {
                                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        Button {
                            store.setItems(items.filter { $0.id != item.id }, for: category)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove")
                    }
                    .padding(.vertical, 2)
                }
                .onMove { from, to in
                    var copy = items
                    copy.move(fromOffsets: from, toOffset: to)
                    store.setItems(copy, for: category)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            HStack {
                Menu {
                    Section("Built-in") {
                        ForEach(BuiltInAction.allCases.filter { $0.categories.contains(category) }) { action in
                            Button {
                                add(ActionItem(action))
                            } label: {
                                Label(action.title, systemImage: action.symbol)
                            }
                        }
                    }
                    Section("Custom") {
                        Button("Run a Shortcut…") { customSheet = .shortcut }
                        Button("Run a shell script…") { customSheet = .script }
                        Button("Open with app…") {
                            if let url = AppPicker.pick() { add(ActionItem(.openWith(appPath: url.path))) }
                        }
                    }
                } label: {
                    Label("Add action", systemImage: "plus")
                }
                .fixedSize()
                .disabled(items.count >= ConfigStore.maxSlices)

                Spacer()
                Button("Reset to defaults") { store.resetActions(for: category) }
            }
        }
        .padding(20)
        .sheet(item: $customSheet) { kind in
            CustomActionSheet(kind: kind) { item in add(item) }
        }
    }

    private func add(_ item: ActionItem) {
        store.setItems(items + [item], for: category)
    }

    private func subtitle(for item: ActionItem) -> String? {
        switch item.kind {
        case .builtIn: return nil
        case .shortcut: return "Shortcut"
        case .script(_, let command): return command
        case .openWith(let path): return path
        }
    }
}

private struct CustomActionSheet: View {
    let kind: ActionsSettings.CustomKind
    var onAdd: (ActionItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var command = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(kind == .shortcut ? "Run a Shortcut" : "Run a shell script")
                .font(.title3.bold())

            if kind == .shortcut {
                TextField("Shortcut name (exactly as in the Shortcuts app)", text: $name)
                Text("Each dropped file is passed to the shortcut as input.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                TextField("Name shown in the ring", text: $name)
                TextEditor(text: $command)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 110)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15)))
                Text("Runs in zsh. Dropped files are $1, $2 … — use \"$@\" for all of them.\nExample: for f in \"$@\"; do sips -Z 1200 \"$f\"; done")
                    .font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    let trimmedName = name.trimmingCharacters(in: .whitespaces)
                    if kind == .shortcut {
                        onAdd(ActionItem(.shortcut(name: trimmedName)))
                    } else {
                        onAdd(ActionItem(.script(name: trimmedName, command: command)))
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                          || (kind == .script && command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

enum AppPicker {
    @MainActor
    static func pick() -> URL? {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
