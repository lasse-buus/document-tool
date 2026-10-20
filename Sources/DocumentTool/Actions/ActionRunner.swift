import AppKit

/// Runs the chosen slice on every dropped file and shows a small confirmation near the cursor.
@MainActor
enum ActionRunner {
    static func run(_ item: ActionItem, urls: [URL], near point: NSPoint) {
        let config = ConfigStore.shared.config

        switch item.kind {
        case .builtIn(let action):
            runBuiltIn(action, urls: urls, config: config, near: point)

        case .shortcut(let name):
            background(urls, point: point, verb: "Ran “\(name)” on") { url in
                try Shell.run("/usr/bin/shortcuts", ["run", name, "--input-path", url.path])
                return nil
            }

        case .script(let name, let command):
            Toast.show("Running \(name)…", symbol: "terminal", near: point)
            Task.detached {
                do {
                    // Files are $1, $2 … and "$@".
                    try Shell.run("/bin/zsh", ["-lc", command, "document-tool"] + urls.map(\.path))
                    await Toast.show("\(name) finished", symbol: "checkmark.circle.fill", near: point)
                } catch {
                    await Toast.show("\(name) failed: \(error.localizedDescription)", symbol: "xmark.octagon.fill", near: point, isError: true)
                }
            }

        case .openWith(let appPath):
            let appURL = URL(fileURLWithPath: appPath)
            NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error {
                    Task { @MainActor in Toast.show(error.localizedDescription, symbol: "xmark.octagon.fill", near: point, isError: true) }
                }
            }
        }
    }

    private static func runBuiltIn(_ action: BuiltInAction, urls: [URL], config: AppConfig, near point: NSPoint) {
        switch action {
        case .pdfToText:
            background(urls, point: point, verb: "Converted") { url in try PDFToText.convert(url) }

        case .textToPDF:
            // Uses AppKit printing, so it runs on the main thread.
            var outputs: [URL] = []
            var failure: Error?
            for url in urls {
                do { outputs.append(try TextToPDF.convert(url)) } catch { failure = error }
            }
            finish(outputs: outputs, total: urls.count, failure: failure, verb: "Converted", point: point)

        case .compressImage:
            let quality = config.imageQuality
            Task.detached {
                var outputs: [URL] = []
                var before: Int64 = 0, after: Int64 = 0
                var failure: Error?
                for url in urls {
                    do {
                        let result = try ImageCompressor.compress(url, quality: quality)
                        outputs.append(result.output)
                        before += result.originalBytes
                        after += result.newBytes
                    } catch { failure = error }
                }
                let saved = "\(Files.byteString(before)) → \(Files.byteString(after))"
                let finalOutputs = outputs
                let finalFailure = failure
                await MainActor.run {
                    finish(outputs: finalOutputs, total: urls.count, failure: finalFailure,
                           verb: "Compressed", point: point, detail: saved)
                }
            }

        case .edit:
            for url in urls { NSWorkspace.shared.open(url) }

        case .openWithFavorite:
            let appURL = FavoriteEditor.resolve(config.favoriteEditorPath)
            NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error {
                    Task { @MainActor in Toast.show(error.localizedDescription, symbol: "xmark.octagon.fill", near: point, isError: true) }
                }
            }

        case .share:
            ShareAnchor.shared.share(urls, at: point)

        case .gradientBackground, .codeSnippet:
            var outputs: [URL] = []
            var images: [NSImage] = []
            var failure: Error?
            for url in urls {
                do {
                    let result = try (action == .codeSnippet
                        ? ImageCards.snippet(for: url, gradient: config.gradient)
                        : ImageCards.background(for: url, gradient: config.gradient))
                    outputs.append(result.url)
                    images.append(result.image)
                } catch { failure = error }
            }
            if config.copyImagesToClipboard, !images.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects(images)
            }
            finish(outputs: outputs, total: urls.count, failure: failure,
                   verb: action == .codeSnippet ? "Snippet saved for" : "Background added to",
                   point: point,
                   detail: config.copyImagesToClipboard && !images.isEmpty ? "Copied to clipboard" : nil)

        case .trash:
            NSWorkspace.shared.recycle(urls) { trashed, error in
                Task { @MainActor in
                    if let error {
                        Toast.show(error.localizedDescription, symbol: "xmark.octagon.fill", near: point, isError: true)
                    } else {
                        Toast.show("Moved \(Files.count(trashed.count)) to Trash", symbol: "trash.fill", near: point)
                    }
                }
            }
        }
    }

    /// Runs `work` for each file off the main thread, then reports.
    private static func background(_ urls: [URL], point: NSPoint, verb: String,
                                   work: @escaping @Sendable (URL) throws -> URL?) {
        Task.detached {
            var outputs: [URL] = []
            var failure: Error?
            for url in urls {
                do { if let out = try work(url) { outputs.append(out) } } catch { failure = error }
            }
            let finalOutputs = outputs
            let finalFailure = failure
            await MainActor.run {
                finish(outputs: finalOutputs, total: urls.count, failure: finalFailure, verb: verb, point: point)
            }
        }
    }

    private static func finish(outputs: [URL], total: Int, failure: Error?, verb: String,
                               point: NSPoint, detail: String? = nil) {
        if let failure, outputs.isEmpty {
            Toast.show(failure.localizedDescription, symbol: "xmark.octagon.fill", near: point, isError: true)
            return
        }
        var message = "\(verb) \(Files.count(total))"
        if failure != nil { message += " (some failed)" }
        if let detail { message += "\n\(detail)" }
        Toast.show(message, symbol: "checkmark.circle.fill", near: point)
        // Select the new files in Finder so they're easy to find.
        if !outputs.isEmpty, outputs.count <= 20 {
            NSWorkspace.shared.activateFileViewerSelecting(outputs)
        }
    }
}

enum FavoriteEditor {
    /// Editors to try when no favorite is set, in order.
    static let knownBundleIDs = [
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "com.microsoft.VSCode",
        "dev.zed.Zed",
        "com.sublimetext.4",
        "com.panic.Nova",
        "com.apple.TextEdit"
    ]

    static func resolve(_ path: String?) -> URL {
        if let path, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        for id in knownBundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return url }
        }
        return URL(fileURLWithPath: "/System/Applications/TextEdit.app")
    }
}

enum Shell {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let msg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure(message: (msg?.isEmpty == false ? msg! : "Exited with code \(process.terminationStatus)"))
        }
        return String(data: outData, encoding: .utf8) ?? ""
    }
}
