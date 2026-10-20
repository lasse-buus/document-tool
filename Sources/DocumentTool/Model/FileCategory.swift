import Foundation
import UniformTypeIdentifiers

/// Which kind of file is being dragged. Decides which slices the ring shows.
enum FileCategory: String, Codable, CaseIterable, Identifiable {
    case pdf
    case text
    case image
    case video
    case code
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdf: return "PDF"
        case .text: return "Text"
        case .image: return "Image"
        case .video: return "Video"
        case .code: return "Code"
        case .other: return "Other / mixed"
        }
    }

    var symbol: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .text: return "doc.plaintext"
        case .image: return "photo"
        case .video: return "film"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .other: return "doc.on.doc"
        }
    }

    /// Extensions treated as code. Checked before UTType, because e.g. `.ts`
    /// is registered as an MPEG transport stream video.
    static let codeExtensions: Set<String> = [
        "swift", "js", "jsx", "ts", "tsx", "mjs", "cjs", "json", "css", "scss", "sass", "less",
        "html", "htm", "vue", "svelte", "astro", "php", "py", "rb", "go", "rs", "java", "kt",
        "c", "h", "cpp", "hpp", "m", "mm", "cs", "sh", "zsh", "bash", "fish", "yml", "yaml",
        "toml", "xml", "sql", "graphql", "gql", "lua", "dart", "scala", "r", "pl", "ex", "exs",
        "env", "ini", "dockerfile", "makefile", "gradle", "prisma", "groq"
    ]

    static func detect(_ url: URL) -> FileCategory {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()
        if ext == "pdf" { return .pdf }
        if codeExtensions.contains(ext) || codeExtensions.contains(name) { return .code }

        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: ext)
        guard let type else { return .other }

        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .sourceCode) { return .code }
        if type.conforms(to: .text) { return .text }
        return .other
    }

    /// All files share one category -> that category. Mixed -> `.other`.
    static func detect(_ urls: [URL]) -> FileCategory {
        let cats = Set(urls.map { detect($0) })
        return cats.count == 1 ? cats.first! : .other
    }
}
