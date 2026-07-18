import AppKit

@main
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MangaWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if args.count > 1 {
            openFile(URL(fileURLWithPath: args[1]))
        } else {
            openPanel()
        }
    }

    func application(_ application: NSApplication, openFile filename: String) -> Bool {
        openFile(URL(fileURLWithPath: filename))
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
                if self?.windowController == nil {
                    NSApplication.shared.terminate(nil)
                }
                return
            }
            self?.openFile(url)
        }
    }

    private func openFile(_ url: URL) {
        let resolved = url.resolvingSymlinksInPath()
        guard let book = CBZBook(url: resolved) else {
            let alert = NSAlert()
            alert.messageText = "Could not open CBZ"
            alert.informativeText = "The file could not be read as a valid CBZ archive."
            alert.alertStyle = .warning
            alert.runModal()
            if windowController == nil {
                NSApplication.shared.terminate(nil)
            }
            return
        }
        windowController?.close()
        let wc = MangaWindowController(book: book)
        windowController = wc
        wc.showWindow(nil)
    }
}
