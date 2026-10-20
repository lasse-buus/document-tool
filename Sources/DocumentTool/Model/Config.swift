import AppKit
import SwiftUI

/// The key (or key combination) you hold while dragging to open the ring.
/// Only modifier keys (⌃ ⌥ ⇧ ⌘ fn) are supported: they can be read without
/// asking for Accessibility / Input Monitoring permission.
struct TriggerKey: Codable, Equatable {
    var rawFlags: UInt

    static let relevantMask: NSEvent.ModifierFlags = [.control, .option, .shift, .command, .function]

    init(_ flags: NSEvent.ModifierFlags) {
        rawFlags = flags.intersection(Self.relevantMask).rawValue
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: rawFlags) }

    func matches(_ current: NSEvent.ModifierFlags) -> Bool {
        !flags.isEmpty && current.intersection(Self.relevantMask) == flags
    }

    var display: String {
        var s = ""
        if flags.contains(.function) { s += "fn " }
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s.trimmingCharacters(in: .whitespaces)
    }

    var spokenName: String {
        var parts: [String] = []
        if flags.contains(.function) { parts.append("Fn") }
        if flags.contains(.control) { parts.append("Control") }
        if flags.contains(.option) { parts.append("Option") }
        if flags.contains(.shift) { parts.append("Shift") }
        if flags.contains(.command) { parts.append("Command") }
        return parts.joined(separator: " + ")
    }
}

enum GradientPreset: String, Codable, CaseIterable, Identifiable {
    case sunset, ocean, grape, mint, candy, night

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var colors: [Color] {
        switch self {
        case .sunset: return [Color(red: 1.00, green: 0.54, blue: 0.36), Color(red: 0.93, green: 0.26, blue: 0.52), Color(red: 0.55, green: 0.24, blue: 0.85)]
        case .ocean: return [Color(red: 0.20, green: 0.83, blue: 0.93), Color(red: 0.23, green: 0.42, blue: 0.95), Color(red: 0.29, green: 0.20, blue: 0.75)]
        case .grape: return [Color(red: 0.78, green: 0.47, blue: 0.98), Color(red: 0.42, green: 0.25, blue: 0.85)]
        case .mint: return [Color(red: 0.62, green: 0.95, blue: 0.70), Color(red: 0.16, green: 0.69, blue: 0.64)]
        case .candy: return [Color(red: 1.00, green: 0.80, blue: 0.44), Color(red: 1.00, green: 0.47, blue: 0.62), Color(red: 0.54, green: 0.63, blue: 1.00)]
        case .night: return [Color(red: 0.15, green: 0.16, blue: 0.30), Color(red: 0.36, green: 0.20, blue: 0.50)]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct AppConfig: Codable, Equatable {
    var trigger: TriggerKey?
    /// Slices per file category, keyed by `FileCategory.rawValue`.
    var actions: [String: [ActionItem]] = [:]
    var favoriteEditorPath: String?
    var gradient: GradientPreset = .sunset
    var imageQuality: Double = 0.7
    /// Also copy generated images (Background / Snippet) to the clipboard.
    var copyImagesToClipboard = true

    func items(for category: FileCategory) -> [ActionItem] {
        actions[category.rawValue] ?? DefaultActions.items(for: category)
    }
}

@MainActor
final class ConfigStore: ObservableObject {
    static let shared = ConfigStore()
    static let maxSlices = 8

    @Published var config: AppConfig {
        didSet { if config != oldValue { save() } }
    }

    private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DocumentTool", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = decoded
        } else {
            config = AppConfig()
        }
        // Fill in categories that don't exist yet with defaults.
        for cat in FileCategory.allCases where config.actions[cat.rawValue] == nil {
            config.actions[cat.rawValue] = DefaultActions.items(for: cat)
        }
    }

    func items(for category: FileCategory) -> [ActionItem] { config.items(for: category) }

    func setItems(_ items: [ActionItem], for category: FileCategory) {
        config.actions[category.rawValue] = Array(items.prefix(Self.maxSlices))
    }

    func resetActions(for category: FileCategory) {
        config.actions[category.rawValue] = DefaultActions.items(for: category)
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}
