import AppKit

struct MangaPageID: Hashable {
    let chapter: Int
    let page: Int
}

struct LoadedMangaPage {
    let id: MangaPageID
    let image: NSImage
}

final class CBZBook {
    let url: URL
    let tempDir: URL
    private let entries: [URL]
    var pageCount: Int { entries.count }

    private static let imageExtensions = ["jpg", "jpeg", "png", "webp"]

    init?(url: URL) {
        self.url = url

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            return nil
        }

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
        guard let image = NSImage(contentsOf: entries[index]) else { return nil }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        return NSImage(cgImage: cgImage, size: image.size)
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
    private var books: [Int: CBZBook]
    private let booksLock = NSLock()
    private var isClosed = false
    private let chapters: [URL]
    private let currentIndex: Int
    private var viewController: MangaViewController!

    init(book: CBZBook, chapters: [URL], currentIndex: Int) {
        self.books = [currentIndex: book]
        self.chapters = chapters
        self.currentIndex = currentIndex
#if DEBUG
        print("[manga] opened viewer currentFile=\(book.url.path) currentChapterIndex=\(currentIndex) chapterCount=\(chapters.count)")
#endif

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

        let vc = MangaViewController(
            chapterIndex: currentIndex,
            pageCount: { [weak self] chapter in self?.pageCount(chapter: chapter) ?? 0 },
            loadPage: { [weak self] id in self?.loadPage(id) },
            titleForPage: { [weak self] id in self?.title(for: id) ?? "" }
        )
        self.viewController = vc
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
        booksLock.lock()
        isClosed = true
        let books = Array(self.books.values)
        self.books.removeAll()
        booksLock.unlock()
        super.close()
        books.forEach { $0.cleanup() }
    }

    private func book(at chapter: Int) -> CBZBook? {
        guard chapters.indices.contains(chapter) else { return nil }
        booksLock.lock()
        defer { booksLock.unlock() }
        guard !isClosed else { return nil }
        if let book = books[chapter] {
            return book
        }
        guard let book = CBZBook(url: chapters[chapter]) else { return nil }
        books[chapter] = book
#if DEBUG
        print("[manga] opened archive file=\(chapters[chapter].path) chapterIndex=\(chapter) pageCount=\(book.pageCount)")
#endif
        return book
    }

    private func pageCount(chapter: Int) -> Int {
        book(at: chapter)?.pageCount ?? 0
    }

    private func loadPage(_ id: MangaPageID) -> NSImage? {
        guard chapters.indices.contains(id.chapter) else {
#if DEBUG
            print("[manga] skipped invalid chapter index \(id.chapter) for page \(id.page + 1)")
#endif
            return nil
        }
        let chapterURL = chapters[id.chapter]
        guard let book = book(at: id.chapter), id.page >= 0, id.page < book.pageCount else {
#if DEBUG
            print("[manga] skipped invalid page file=\(chapterURL.path) chapterIndex=\(id.chapter) pageIndex=\(id.page) pageCount=\(book(at: id.chapter)?.pageCount ?? 0)")
#endif
            return nil
        }
        let image = book.image(at: id.page)
#if DEBUG
        if image != nil {
            print("[manga] loaded file=\(chapterURL.path) chapterIndex=\(id.chapter) pageIndex=\(id.page) pageCount=\(book.pageCount)")
        }
#endif
        return image
    }

    private func title(for id: MangaPageID) -> String {
        guard chapters.indices.contains(id.chapter) else { return "" }
        return chapters[id.chapter].deletingPathExtension().lastPathComponent
    }
}

final class MangaViewController: NSViewController {
    private let pageWindowCapacity = 60
    private let prefetchBatchSize = 12
    private let prefetchThreshold = 24
    private let startingChapter: Int
    private let pageCount: (Int) -> Int
    private let loadPage: (MangaPageID) -> NSImage?
    private let titleForPage: (MangaPageID) -> String
    private let scrollView = NSScrollView()
    private var containerView: PageContainerView?
    private var boundsObserver: NSObjectProtocol?
    private var liveScrollObservers: [NSObjectProtocol] = []
    private var pages: [LoadedMangaPage] = []
    private var isMaintainingPageWindow = false
    private var isLoadingPageWindow = false
    private var lastScrollY: CGFloat?
    private var isLiveScrolling = false
    private var pendingForward: (MangaPageID, [LoadedMangaPage])?
    private var pendingBackward: (MangaPageID, [LoadedMangaPage])?
    private var shouldPrefetchForwardAfterInitialBackward = false
#if DEBUG
    private let debugPositionLabel = NSTextField(labelWithString: "")
    private var lastDebugPageID: MangaPageID?
#endif

    init(
        chapterIndex: Int,
        pageCount: @escaping (Int) -> Int,
        loadPage: @escaping (MangaPageID) -> NSImage?,
        titleForPage: @escaping (MangaPageID) -> String
    ) {
        self.startingChapter = chapterIndex
        self.pageCount = pageCount
        self.loadPage = loadPage
        self.titleForPage = titleForPage
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

        pages = makeInitialPages()
        let cv = PageContainerView(pages: pages)
        containerView = cv

        scrollView.autoresizingMask = [.width, .height]
        scrollView.frame = .zero
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.verticalScrollElasticity = .allowed
        scrollView.usesPredominantAxisScrolling = true
        scrollView.drawsBackground = false
        scrollView.documentView = cv
        view.addSubview(scrollView)
#if DEBUG
        debugPositionLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        debugPositionLabel.textColor = .white
        debugPositionLabel.backgroundColor = NSColor.black.withAlphaComponent(0.75)
        debugPositionLabel.drawsBackground = true
        debugPositionLabel.alignment = .right
        view.addSubview(debugPositionLabel)
#endif

        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.maintainPageWindow()
        }
        liveScrollObservers.append(NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            self?.isLiveScrolling = true
        })
        liveScrollObservers.append(NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            self?.isLiveScrolling = false
            self?.applyPendingWindowUpdate()
        })
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.shouldPrefetchForwardAfterInitialBackward = true
            self.requestBackward()
        }
    }

    private func makeInitialPages() -> [LoadedMangaPage] {
        MangaPageNavigation.initialPages(
            startingChapter: startingChapter,
            limit: 20,
            pageCount: pageCount
        ).compactMap(loadedPage)
    }

    private func loadedPage(_ id: MangaPageID) -> LoadedMangaPage? {
        guard let image = loadPage(id) else { return nil }
        return LoadedMangaPage(id: id, image: image)
    }

    private func maintainPageWindow() {
        guard !isMaintainingPageWindow else { return }
        isMaintainingPageWindow = true
        defer { isMaintainingPageWindow = false }

        guard let containerView, !pages.isEmpty else { return }
        let currentY = scrollView.contentView.bounds.minY
        let scrollingDown = lastScrollY.map { currentY > $0 + 0.5 } ?? false
        let scrollingUp = lastScrollY.map { currentY < $0 - 0.5 } ?? false
        lastScrollY = currentY
        let visibleRange = containerView.visiblePageRange(in: scrollView.contentView.bounds)
        updateDebugPosition(visibleRange: visibleRange)
        guard !isLoadingPageWindow, pendingForward == nil, pendingBackward == nil else { return }
        if scrollingDown, pages.count - visibleRange.upperBound <= prefetchThreshold {
            requestForward()
        } else if scrollingUp, scrollView.contentView.bounds.minY < -1 {
            requestBackward()
        }
    }

    private func requestForward() {
        guard let anchor = pages.last?.id else { return }
        isLoadingPageWindow = true
        let pageCount = self.pageCount
        let loadPage = self.loadPage
        let batchSize = prefetchBatchSize
#if DEBUG
        print("[manga] prefetch request direction=forward after=chapter:\(anchor.chapter + 1) page:\(anchor.page + 1) batch=\(batchSize) available=\(pages.count)")
#endif
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var ids: [MangaPageID] = []
            var next = anchor
            while ids.count < batchSize, let id = Self.nextPage(after: next, pageCount: pageCount) {
                ids.append(id)
                next = id
            }
            let loaded = ids.compactMap { id -> LoadedMangaPage? in
                guard let image = loadPage(id) else { return nil }
                return LoadedMangaPage(id: id, image: image)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.pages.last?.id == anchor else {
                    self.isLoadingPageWindow = false
                    return
                }
                self.isLoadingPageWindow = false
#if DEBUG
                print("[manga] prefetch complete direction=forward loaded=\(loaded.count) available=\(self.pages.count + loaded.count)")
#endif
                if self.isLiveScrolling {
                    self.pendingForward = (anchor, loaded)
                } else {
                    self.applyForward(loaded)
                }
            }
        }
    }

    private func applyForward(_ loaded: [LoadedMangaPage]) {
        guard let containerView, !loaded.isEmpty else { return }
        var window = MangaPageWindow(pages: pages.map(\.id), capacity: pageWindowCapacity)
        let removed = window.append(loaded.map(\.id))
        var updated = pages
        updated.append(contentsOf: loaded)
        let removeCount = removed.count

        let removedHeight = containerView.height(of: Array(pages.prefix(removeCount)))
        let oldY = scrollView.contentView.bounds.minY
        pages = Array(updated.dropFirst(removeCount))
        containerView.setPages(pages)
        containerView.relayout()
        let y = max(0, oldY - removedHeight)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        lastScrollY = y
    }

    private func requestBackward() {
        guard let anchor = pages.first?.id else { return }
        isLoadingPageWindow = true
        let pageCount = self.pageCount
        let loadPage = self.loadPage
        let batchSize = prefetchBatchSize
#if DEBUG
        print("[manga] prefetch request direction=backward before=chapter:\(anchor.chapter + 1) page:\(anchor.page + 1) batch=\(batchSize) available=\(pages.count)")
#endif
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var ids: [MangaPageID] = []
            var previous = anchor
            while ids.count < batchSize, let id = Self.previousPage(before: previous, pageCount: pageCount) {
                ids.insert(id, at: 0)
                previous = id
            }
            let loaded = ids.compactMap { id -> LoadedMangaPage? in
                guard let image = loadPage(id) else { return nil }
                return LoadedMangaPage(id: id, image: image)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.pages.first?.id == anchor else {
                    self.isLoadingPageWindow = false
                    return
                }
                self.isLoadingPageWindow = false
#if DEBUG
                print("[manga] prefetch complete direction=backward loaded=\(loaded.count) available=\(self.pages.count + loaded.count)")
#endif
                if self.isLiveScrolling {
                    self.pendingBackward = (anchor, loaded)
                } else {
                    self.applyBackward(loaded)
                    self.startInitialForwardPrefetchIfNeeded()
                }
            }
        }
    }

    private func startInitialForwardPrefetchIfNeeded() {
        guard shouldPrefetchForwardAfterInitialBackward else { return }
        shouldPrefetchForwardAfterInitialBackward = false
        requestForward()
    }

    private func applyBackward(_ loaded: [LoadedMangaPage]) {
        guard let containerView, !loaded.isEmpty else { return }
        var window = MangaPageWindow(pages: pages.map(\.id), capacity: pageWindowCapacity)
        let removed = window.prepend(loaded.map(\.id))
        var updated = loaded
        updated.append(contentsOf: pages)
        let removeCount = removed.count

        let addedHeight = containerView.height(of: Array(updated.prefix(updated.count - pages.count)))
        let oldY = scrollView.contentView.bounds.minY
        pages = Array(updated.dropLast(removeCount))
        containerView.setPages(pages)
        containerView.relayout()
        let y = oldY + addedHeight
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        lastScrollY = y
    }

    private func applyPendingWindowUpdate() {
        if let pendingForward,
           pages.last?.id == pendingForward.0 {
            self.pendingForward = nil
            applyForward(pendingForward.1)
        } else if let pendingBackward,
                  pages.first?.id == pendingBackward.0 {
            self.pendingBackward = nil
            applyBackward(pendingBackward.1)
            startInitialForwardPrefetchIfNeeded()
        } else {
            pendingForward = nil
            pendingBackward = nil
        }
    }

    private static func nextPage(after id: MangaPageID, pageCount: (Int) -> Int) -> MangaPageID? {
        MangaPageNavigation.nextPage(after: id, pageCount: pageCount)
    }

    private static func previousPage(before id: MangaPageID, pageCount: (Int) -> Int) -> MangaPageID? {
        MangaPageNavigation.previousPage(before: id, pageCount: pageCount)
    }

#if DEBUG
    private func updateDebugPosition(visibleRange: Range<Int>) {
        guard pages.indices.contains(visibleRange.lowerBound) else { return }
        let page = pages[visibleRange.lowerBound]
        guard lastDebugPageID != page.id else { return }
        lastDebugPageID = page.id
        let title = titleForPage(page.id)
        debugPositionLabel.stringValue = "\(title) chapter \(page.id.chapter + 1) page \(page.id.page + 1)"
    }
#else
    private func updateDebugPosition(visibleRange: Range<Int>) {}
#endif

    override func viewDidLayout() {
        super.viewDidLayout()
        scrollView.frame = view.bounds
        containerView?.relayout()
        updateDebugPosition(visibleRange: containerView?.visiblePageRange(in: scrollView.contentView.bounds) ?? 0..<0)
#if DEBUG
        debugPositionLabel.frame = NSRect(
            x: max(0, view.bounds.width - 340),
            y: 8,
            width: min(332, view.bounds.width),
            height: 20
        )
#endif
    }

    deinit {
        if let observer = boundsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        liveScrollObservers.forEach(NotificationCenter.default.removeObserver)
    }
}

final class PageContainerView: NSView {
    override var isFlipped: Bool { true }

    private var pages: [LoadedMangaPage]
    private var imageViews: [NSImageView]

    init(pages: [LoadedMangaPage]) {
        self.pages = pages
        self.imageViews = pages.map { _ in PageContainerView.makeImageView() }
        super.init(frame: .zero)
        imageViews.forEach(addSubview)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setPages(_ pages: [LoadedMangaPage]) {
        let existingViews = Dictionary(uniqueKeysWithValues: zip(self.pages, imageViews).map { ($0.0.id, $0.1) })
        let updatedViews = pages.map { existingViews[$0.id] ?? PageContainerView.makeImageView() }
        imageViews.filter { view in !updatedViews.contains { $0 === view } }.forEach { $0.removeFromSuperview() }
        updatedViews.filter { $0.superview == nil }.forEach(addSubview)
        self.pages = pages
        imageViews = updatedViews
    }

    func height(of pages: [LoadedMangaPage]) -> CGFloat {
        guard let scrollView = enclosingScrollView else { return 0 }
        let width = scrollView.contentSize.width
        guard width > 0 else { return 0 }
        return pages.reduce(0) { total, page in
            guard page.image.size.width > 0 else { return total }
            return total + round(width * page.image.size.height / page.image.size.width)
        }
    }

    func visiblePageRange(in bounds: NSRect) -> Range<Int> {
        let visible = imageViews.indices.filter { imageViews[$0].frame.intersects(bounds) }
        guard let first = visible.first, let last = visible.last else { return 0..<0 }
        return first..<(last + 1)
    }

    func relayout() {
        guard let scrollView = enclosingScrollView else { return }
        let width = scrollView.contentSize.width
        guard width > 0 else { return }

        var y: CGFloat = 0
        for (index, page) in pages.enumerated() {
            let imageView = imageViews[index]
            guard page.image.size.width > 0, page.image.size.height > 0 else { continue }
            if imageView.image !== page.image {
                imageView.image = page.image
            }
            let height = round(width * page.image.size.height / page.image.size.width)
            imageView.frame = NSRect(x: 0, y: y, width: width, height: height)
            y += height
        }
        frame.size = CGSize(width: width, height: max(y, 1))
    }

    private static func makeImageView() -> NSImageView {
        let imageView = NSImageView()
        imageView.wantsLayer = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        return imageView
    }
}
