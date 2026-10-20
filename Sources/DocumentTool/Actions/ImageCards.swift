import AppKit
import PDFKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// "Bg" and "Snippet": render the file onto a gradient and save it as a PNG next to the original.
@MainActor
enum ImageCards {
    struct Result {
        let url: URL
        let image: NSImage
    }

    static let maxLines = 70
    static let maxLineLength = 140

    /// Bg: the file's content on a gradient.
    /// - Text: the text on a light card.
    /// - Code: the code (plain, monospaced) on a dark card.
    /// - PDF: the first page on the gradient.
    static func background(for url: URL, gradient: GradientPreset) throws -> Result {
        let category = FileCategory.detect(url)
        let view: AnyView
        switch category {
        case .pdf:
            guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else {
                throw ActionError("Couldn't open \(url.lastPathComponent)")
            }
            let bounds = page.bounds(for: .mediaBox)
            let targetWidth: CGFloat = 900
            let scale = targetWidth / max(bounds.width, 1)
            let thumb = page.thumbnail(of: NSSize(width: targetWidth, height: bounds.height * scale), for: .mediaBox)
            view = AnyView(PDFCard(image: thumb, gradient: gradient))
        case .code:
            let code = try trimmed(Files.readText(url))
            view = AnyView(CodeCard(code: AttributedString(code), fileName: nil, lineCount: lineCount(code), gradient: gradient))
        default:
            let text = try trimmed(Files.readText(url))
            view = AnyView(TextCard(text: text, gradient: gradient))
        }
        return try save(view, nextTo: url, suffix: "bg")
    }

    /// Snippet: code in a window with syntax highlighting, line numbers and the file name.
    static func snippet(for url: URL, gradient: GradientPreset) throws -> Result {
        let code = try trimmed(Files.readText(url))
        let highlighted = SyntaxHighlighter.highlight(code, fileExtension: url.pathExtension.lowercased())
        let view = CodeCard(code: highlighted, fileName: url.lastPathComponent,
                            lineCount: lineCount(code), gradient: gradient)
        return try save(AnyView(view), nextTo: url, suffix: "snippet")
    }

    private static func lineCount(_ s: String) -> Int {
        s.components(separatedBy: "\n").count
    }

    /// Keeps images a sensible size: max lines, max line length, tabs -> spaces.
    private static func trimmed(_ s: String) -> String {
        var lines = s.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\t", with: "    ")
            .components(separatedBy: "\n")
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty, lines.count > 1 {
            lines.removeLast()
        }
        var truncated = false
        if lines.count > maxLines {
            lines = Array(lines.prefix(maxLines))
            truncated = true
        }
        lines = lines.map { $0.count > maxLineLength ? String($0.prefix(maxLineLength)) + "…" : $0 }
        if truncated { lines.append("…") }
        return lines.joined(separator: "\n")
    }

    private static func save(_ view: AnyView, nextTo url: URL, suffix: String) throws -> Result {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { throw ActionError("Couldn't render the image") }

        let out = Files.output(for: url, suffix: suffix, ext: "png")
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ActionError("Couldn't write \(out.lastPathComponent)")
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { throw ActionError("Couldn't save \(out.lastPathComponent)") }

        let image = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
        return Result(url: out, image: image)
    }
}

// MARK: - Card views

private struct GradientFrame<Content: View>: View {
    let gradient: GradientPreset
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(64)
            .background(gradient.gradient)
    }
}

private struct TextCard: View {
    let text: String
    let gradient: GradientPreset

    var body: some View {
        GradientFrame(gradient: gradient) {
            Text(text)
                .font(.system(size: 17, weight: .regular))
                .lineSpacing(5)
                .foregroundStyle(Color(white: 0.12))
                .frame(width: 620, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(36)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.94))
                        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                )
        }
    }
}

private struct PDFCard: View {
    let image: NSImage
    let gradient: GradientPreset

    var body: some View {
        GradientFrame(gradient: gradient) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 600)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
        }
    }
}

private struct CodeCard: View {
    let code: AttributedString
    /// When set, shows a window title bar with the file name (Snippet). Nil = plain card (Bg).
    let fileName: String?
    let lineCount: Int
    let gradient: GradientPreset

    private let font = Font.system(size: 14, design: .monospaced)

    var body: some View {
        GradientFrame(gradient: gradient) {
            VStack(alignment: .leading, spacing: 0) {
                if let fileName {
                    HStack(spacing: 8) {
                        Circle().fill(Color(red: 1.00, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
                        Circle().fill(Color(red: 1.00, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
                        Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 12, height: 12)
                        Spacer()
                        Text(fileName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.55))
                        Spacer()
                        Color.clear.frame(width: 52, height: 12)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }

                HStack(alignment: .top, spacing: 18) {
                    if fileName != nil {
                        Text((1...max(lineCount, 1)).map(String.init).joined(separator: "\n"))
                            .font(font)
                            .lineSpacing(4)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(Color.white.opacity(0.28))
                    }
                    Text(code)
                        .font(font)
                        .lineSpacing(4)
                        .foregroundStyle(Color(white: 0.9))
                        .fixedSize(horizontal: true, vertical: true)
                }
                .padding(.horizontal, 22)
                .padding(.top, fileName == nil ? 22 : 4)
                .padding(.bottom, 22)
            }
            .frame(minWidth: 480, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.11, green: 0.11, blue: 0.16).opacity(0.96))
                    .shadow(color: .black.opacity(0.35), radius: 28, y: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
}
