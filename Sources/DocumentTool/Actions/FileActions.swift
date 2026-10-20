import AppKit
import PDFKit
import ImageIO
import UniformTypeIdentifiers

struct ActionError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum Files {
    /// "report.pdf" + suffix "text", ext "txt" -> "report text.txt", or "report text 2.txt" if taken.
    static func output(for url: URL, suffix: String?, ext: String) -> URL {
        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent + (suffix.map { " \($0)" } ?? "")
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    static func readText(_ url: URL) throws -> String {
        if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        if let s = try? String(contentsOf: url, encoding: .isoLatin1) { return s }
        throw ActionError("Couldn't read \(url.lastPathComponent) as text")
    }

    static func size(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    static func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func count(_ n: Int) -> String { n == 1 ? "1 file" : "\(n) files" }
}

// MARK: - PDF -> .txt

enum PDFToText {
    static func convert(_ url: URL) throws -> URL {
        guard let doc = PDFDocument(url: url) else { throw ActionError("Couldn't open \(url.lastPathComponent)") }
        var pages: [String] = []
        for i in 0..<doc.pageCount {
            if let text = doc.page(at: i)?.string { pages.append(text) }
        }
        let text = pages.joined(separator: "\n\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ActionError("\(url.lastPathComponent) has no selectable text (scanned PDF?)")
        }
        let out = Files.output(for: url, suffix: nil, ext: "txt")
        try text.write(to: out, atomically: true, encoding: .utf8)
        return out
    }
}

// MARK: - Text -> PDF

@MainActor
enum TextToPDF {
    static func convert(_ url: URL) throws -> URL {
        let text = try Files.readText(url)
        let out = Files.output(for: url, suffix: nil, ext: "pdf")

        let info = NSPrintInfo(dictionary: [.jobSavingURL: out])
        info.paperSize = NSSize(width: 595, height: 842) // A4
        info.topMargin = 56; info.bottomMargin = 56
        info.leftMargin = 56; info.rightMargin = 56
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.jobDisposition = .save

        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 11.5)
        textView.textColor = .black
        textView.backgroundColor = .white
        textView.string = text
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        if let container = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: container)
        }
        textView.sizeToFit()

        let op = NSPrintOperation(view: textView, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        guard op.run(), FileManager.default.fileExists(atPath: out.path) else {
            throw ActionError("Couldn't create a PDF from \(url.lastPathComponent)")
        }
        return out
    }
}

// MARK: - Image compression

enum ImageCompressor {
    struct Result {
        let output: URL
        let originalBytes: Int64
        let newBytes: Int64
    }

    /// Re-saves as JPEG (or HEIC when the image has transparency) at the given quality.
    /// Keeps metadata/orientation. Never touches the original.
    static func compress(_ url: URL, quality: Double) throws -> Result {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw ActionError("Couldn't read \(url.lastPathComponent)")
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        let hasAlpha = (props[kCGImagePropertyHasAlpha as String] as? Bool) ?? false

        let type: UTType = hasAlpha ? .heic : .jpeg
        let out = Files.output(for: url, suffix: "compressed", ext: type.preferredFilenameExtension ?? "jpg")

        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, type.identifier as CFString, 1, nil) else {
            throw ActionError("Couldn't write \(out.lastPathComponent)")
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImageFromSource(dest, source, 0, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ActionError("Couldn't compress \(url.lastPathComponent)")
        }

        let before = Files.size(url), after = Files.size(out)
        // If it didn't get smaller, don't keep a bigger copy around.
        if after >= before {
            try? FileManager.default.removeItem(at: out)
            throw ActionError("\(url.lastPathComponent) is already well compressed")
        }
        return Result(output: out, originalBytes: before, newBytes: after)
    }
}

// MARK: - Share

/// The macOS share menu needs a view to attach to, so we keep a tiny invisible window at the cursor.
@MainActor
final class ShareAnchor: NSObject, NSSharingServicePickerDelegate {
    static let shared = ShareAnchor()

    private lazy var window: NSPanel = {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 2, height: 2),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        return p
    }()

    func share(_ urls: [URL], at point: NSPoint) {
        window.setFrameOrigin(NSPoint(x: point.x - 1, y: point.y - 1))
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        let picker = NSSharingServicePicker(items: urls)
        picker.delegate = self
        if let view = window.contentView {
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
    }

    nonisolated func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        Task { @MainActor in self.window.orderOut(nil) }
    }
}
