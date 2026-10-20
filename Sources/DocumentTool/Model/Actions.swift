import AppKit
import SwiftUI

/// The built-in options.
enum BuiltInAction: String, Codable, CaseIterable, Identifiable {
    case pdfToText
    case textToPDF
    case compressImage
    case edit
    case share
    case gradientBackground
    case codeSnippet
    case openWithFavorite
    case trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdfToText: return "To .txt"
        case .textToPDF: return "To PDF"
        case .compressImage: return "Compress"
        case .edit: return "Edit"
        case .share: return "Share"
        case .gradientBackground: return "Background"
        case .codeSnippet: return "Snippet"
        case .openWithFavorite: return "Open in editor"
        case .trash: return "Trash"
        }
    }

    var symbol: String {
        switch self {
        case .pdfToText: return "doc.plaintext"
        case .textToPDF: return "doc.richtext"
        case .compressImage: return "arrow.down.right.and.arrow.up.left"
        case .edit: return "pencil"
        case .share: return "square.and.arrow.up"
        case .gradientBackground: return "paintpalette"
        case .codeSnippet: return "camera.viewfinder"
        case .openWithFavorite: return "star"
        case .trash: return "trash"
        }
    }

    var color: Color {
        switch self {
        case .pdfToText, .textToPDF: return Color(red: 0.89, green: 0.42, blue: 0.24) // orange
        case .compressImage: return Color(red: 0.36, green: 0.62, blue: 0.95)
        case .edit: return Color(red: 0.93, green: 0.77, blue: 0.22)                   // yellow
        case .share: return Color(red: 0.24, green: 0.47, blue: 0.93)                  // blue
        case .gradientBackground: return Color(red: 0.58, green: 0.35, blue: 0.80)     // purple
        case .codeSnippet: return Color(red: 0.20, green: 0.72, blue: 0.62)
        case .openWithFavorite: return Color(red: 0.93, green: 0.77, blue: 0.22)
        case .trash: return Color(red: 0.47, green: 0.65, blue: 0.27)                  // green
        }
    }

    /// Which file categories this action makes sense for (used by the "Add" menu in Settings).
    var categories: Set<FileCategory> {
        switch self {
        case .pdfToText: return [.pdf]
        case .textToPDF: return [.text, .code]
        case .compressImage: return [.image]
        case .edit: return [.pdf, .text, .image, .video, .code, .other]
        case .share: return Set(FileCategory.allCases)
        case .gradientBackground: return [.pdf, .text, .code]
        case .codeSnippet: return [.code, .text]
        case .openWithFavorite: return [.code, .text]
        case .trash: return Set(FileCategory.allCases)
        }
    }
}

/// What a slice does: a built-in action or one the user made.
enum ActionKind: Codable, Hashable {
    case builtIn(BuiltInAction)
    /// Runs an Apple Shortcut with the file as input.
    case shortcut(name: String)
    /// Runs a shell command. Files are passed as $1, $2 … ("$@" for all).
    case script(name: String, command: String)
    /// Opens the files with a specific app.
    case openWith(appPath: String)
}

struct ActionItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: ActionKind

    init(_ kind: ActionKind) { self.kind = kind }
    init(_ builtIn: BuiltInAction) { self.kind = .builtIn(builtIn) }

    var title: String {
        switch kind {
        case .builtIn(let a): return a.title
        case .shortcut(let name): return name
        case .script(let name, _): return name
        case .openWith(let path):
            return FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
        }
    }

    var symbol: String {
        switch kind {
        case .builtIn(let a): return a.symbol
        case .shortcut: return "square.stack.3d.up"
        case .script: return "terminal"
        case .openWith: return "app"
        }
    }

    var color: Color {
        switch kind {
        case .builtIn(let a): return a.color
        case .shortcut: return Color(red: 0.90, green: 0.33, blue: 0.55)
        case .script: return Color(white: 0.45)
        case .openWith: return Color(red: 0.93, green: 0.77, blue: 0.22)
        }
    }

    /// App icon for "open with" items, shown instead of an SF Symbol.
    var appIcon: NSImage? {
        if case .openWith(let path) = kind { return NSWorkspace.shared.icon(forFile: path) }
        return nil
    }
}

enum DefaultActions {
    static func items(for category: FileCategory) -> [ActionItem] {
        let list: [BuiltInAction]
        switch category {
        case .pdf: list = [.pdfToText, .share, .edit, .gradientBackground, .trash]
        case .text: list = [.textToPDF, .share, .edit, .gradientBackground, .trash]
        case .image: list = [.compressImage, .edit, .share, .trash]
        case .video: list = [.edit, .share, .trash]
        case .code: list = [.openWithFavorite, .share, .codeSnippet, .gradientBackground, .trash]
        case .other: list = [.share, .edit, .trash]
        }
        return list.map { ActionItem($0) }
    }
}
