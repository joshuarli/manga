import AppKit

final class CBZBook {
    let url: URL
    let tempDir: URL
    private let entries: [URL]
    var pageCount: Int { entries.count }

    private static let imageExtensions = ["jpg", "jpeg", "png", "webp"]

    init?(url: URL) {
        self.url = url

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manga-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", url.path, "-d", tempDir.path]
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: tempDir)
            return nil
        }

        self.tempDir = tempDir
        self.entries = CBZBook.sortedImageEntries(in: tempDir)
        guard !self.entries.isEmpty else {
            try? FileManager.default.removeItem(at: tempDir)
            return nil
        }
    }

    func image(at index: Int) -> NSImage? {
        guard entries.indices.contains(index) else { return nil }
        return NSImage(contentsOf: entries[index])
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    deinit {
        cleanup()
    }

    private static func sortedImageEntries(in dir: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return contents
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

final class MangaWindowController: NSWindowController {
    private let book: CBZBook

    init(book: CBZBook) {
        self.book = book

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = book.url.lastPathComponent
        window.backgroundColor = NSColor(white: 0.08, alpha: 1.0)
        window.setFrameAutosaveName("mangaViewer")

        super.init(window: window)

        let vc = MangaViewController(book: book)
        window.contentViewController = vc

        if let screen = window.screen ?? NSScreen.main {
            let screenFrame = screen.visibleFrame
            let width = screenFrame.width * 0.55
            let height = screenFrame.height * 0.9
            let x = screenFrame.midX - width / 2
            let y = screenFrame.midY - height / 2
            window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func close() {
        super.close()
        book.cleanup()
    }
}

final class MangaViewController: NSViewController {
    private let book: CBZBook
    private let scrollView = NSScrollView()
    private var containerView: PageContainerView?

    init(book: CBZBook) {
        self.book = book
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let images: [NSImage] = (0..<book.pageCount).compactMap { book.image(at: $0) }
        guard !images.isEmpty else { return }

        let cv = PageContainerView(images: images)
        containerView = cv

        scrollView.autoresizingMask = [.width, .height]
        scrollView.frame = view.bounds
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.usesPredominantAxisScrolling = true
        scrollView.drawsBackground = false
        scrollView.documentView = cv
        view.addSubview(scrollView)

        cv.relayout()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        containerView?.relayout()
    }
}

final class PageContainerView: NSView {
    override var isFlipped: Bool { true }

    private let images: [NSImage]
    private let imageViews: [NSImageView]

    init(images: [NSImage]) {
        self.images = images
        self.imageViews = images.map { _ in
            let iv = NSImageView()
            iv.wantsLayer = true
            iv.imageScaling = .scaleProportionallyUpOrDown
            return iv
        }
        super.init(frame: .zero)
        for iv in imageViews {
            addSubview(iv)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func relayout() {
        guard let scrollView = enclosingScrollView else { return }
        let width = scrollView.contentSize.width
        guard width > 0 else { return }

        var y: CGFloat = 0
        for (i, iv) in imageViews.enumerated() {
            let image = images[i]
            iv.image = image
            let ratio = image.size.height / image.size.width
            let h = round(width * ratio)
            iv.frame = CGRect(x: 0, y: y, width: width, height: h)
            y += h
        }
        frame.size = CGSize(width: width, height: max(y, 1))
    }
}
