import AppKit

@main
@MainActor
struct Manga {
    private static var delegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var viewerController: MangaWindowController?
    private var libraryController: LibraryWindowController?
    private var openedPath: URL?
    private var openingLibrary = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if args.count == 1 {
            let mangaDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Sync/Manga")
            if FileManager.default.fileExists(atPath: mangaDir.path) {
                openLibrary(mangaDir.path)
            } else {
                openPanel()
            }
        }
    }

    func application(_ application: NSApplication, openFile filename: String) -> Bool {
        openPath(URL(fileURLWithPath: filename))
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc private func openDocument(_ sender: Any?) {
        openPanel()
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.message = "Open a CBZ archive"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                if self?.viewerController == nil, self?.libraryController == nil {
                    NSApplication.shared.terminate(nil)
                }
                return
            }
            self?.openPath(url)
        }
    }

    private func openPath(_ url: URL) {
        let resolved = url.resolvingSymlinksInPath()
        if openedPath == resolved, viewerController != nil || libraryController != nil {
            return
        }
        openedPath = resolved
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir) else {
            openFile(resolved)
            return
        }
        if isDir.boolValue {
            openLibrary(resolved.path)
        } else {
            openFile(resolved)
        }
    }

    private func openFile(_ url: URL) {
        let resolved = url.resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir), isDir.boolValue {
            openLibrary(resolved.path)
            return
        }
        guard let book = CBZBook(url: resolved) else {
            showAlert("Could not open CBZ", "The file could not be read as a valid CBZ archive.")
            return
        }
        libraryController?.close()
        viewerController?.close()
        let wc = MangaWindowController(book: book, chapters: [resolved], currentIndex: 0)
        viewerController = wc
        wc.showWindow(nil)
    }

    private func openLibrary(_ path: String) {
        guard libraryController == nil, !openingLibrary else { return }
        openingLibrary = true
        viewerController?.close()
        let wc = LibraryWindowController(libraryPath: path) { [weak self] chapterURL, chapters, index in
            self?.openChapter(chapterURL, chapters: chapters, index: index)
        }
        libraryController = wc
        openingLibrary = false
        wc.showWindow(nil)
    }

    private func openChapter(_ url: URL, chapters: [URL], index: Int) {
        viewerController?.close()
        viewerController = nil
        guard let book = CBZBook(url: url) else {
            showAlert("Could not open chapter", "The file could not be read.")
            return
        }
        let wc = MangaWindowController(book: book, chapters: chapters, currentIndex: index)
        viewerController = wc
        wc.showWindow(nil)
        libraryController?.close()
        libraryController = nil
    }

    private func showAlert(_ message: String, _ info: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.alertStyle = .warning
        alert.runModal()
    }
}
