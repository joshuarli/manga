import AppKit
import ImageIO

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

    func image(at index: Int, maxPixelWidth: Int = 2400) -> NSImage? {
        guard entries.indices.contains(index) else { return nil }
        guard let source = CGImageSourceCreateWithURL(entries[index] as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelWidth)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
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
    nonisolated(unsafe) private var books: [Int: CBZBook]
    nonisolated private let booksLock = NSLock()
    nonisolated(unsafe) private var isClosed = false
    nonisolated private let chapters: [URL]
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
            loadPage: { [weak self] id, maxPixelWidth in self?.loadPage(id, maxPixelWidth: maxPixelWidth) },
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

    nonisolated private func book(at chapter: Int) -> CBZBook? {
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

    nonisolated private func pageCount(chapter: Int) -> Int {
        book(at: chapter)?.pageCount ?? 0
    }

    nonisolated private func loadPage(_ id: MangaPageID, maxPixelWidth: Int) -> NSImage? {
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
        let image = book.image(at: id.page, maxPixelWidth: maxPixelWidth)
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
    private let pageWindowCapacity = 48
    private let prefetchBatchSize = 8
    private let prefetchThreshold = 20
    private let startingChapter: Int
    private let pageCount: @Sendable (Int) -> Int
    private let loadPage: @Sendable (MangaPageID, Int) -> NSImage?
    private let titleForPage: (MangaPageID) -> String
    private let scrollView = NSScrollView()
    private var containerView: PageContainerView?
    nonisolated(unsafe) private var boundsObserver: NSObjectProtocol?
    private var pages: [LoadedMangaPage] = []
    private var isMaintainingPageWindow = false
    private var isLoadingPageWindow = false
    private var lastScrollY: CGFloat?
    private var shouldPrefetchForwardAfterInitialBackward = false
#if DEBUG
    private let debugPositionLabel = NSTextField(labelWithString: "")
    private var lastDebugPageID: MangaPageID?
#endif

    init(
        chapterIndex: Int,
        pageCount: @escaping @Sendable (Int) -> Int,
        loadPage: @escaping @Sendable (MangaPageID, Int) -> NSImage?,
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
            Task { @MainActor [weak self] in
                self?.maintainPageWindow()
            }
        }
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
        guard let image = loadPage(id, 2400) else { return nil }
        return LoadedMangaPage(id: id, image: image)
    }

    nonisolated private static func nextPage(after id: MangaPageID, pageCount: (Int) -> Int) -> MangaPageID? {
        MangaPageNavigation.nextPage(after: id, pageCount: pageCount)
    }

    nonisolated private static func previousPage(before id: MangaPageID, pageCount: (Int) -> Int) -> MangaPageID? {
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
    }
}

private extension MangaViewController {
    func maintainPageWindow() {
        guard !isMaintainingPageWindow else { return }
        isMaintainingPageWindow = true
        defer { isMaintainingPageWindow = false }

        guard let containerView, !pages.isEmpty else { return }
        let currentY = scrollView.contentView.bounds.minY
        let scrollingDown = lastScrollY.map { currentY > $0 + 0.5 } ?? false
        let scrollingUp = lastScrollY.map { currentY < $0 - 0.5 } ?? false
        lastScrollY = currentY
        containerView.updateVisiblePageViews(in: scrollView.contentView.bounds)
        let visibleRange = containerView.visiblePageRange(in: scrollView.contentView.bounds)
        updateDebugPosition(visibleRange: visibleRange)
        guard !isLoadingPageWindow else { return }
        if scrollingDown,
           MangaPagePrefetchPolicy.shouldPrefetch(
               direction: .forward,
               visibleRange: visibleRange,
               pageCount: pages.count,
               threshold: prefetchThreshold
           ) {
            requestForward()
        } else if scrollingUp,
                  MangaPagePrefetchPolicy.shouldPrefetch(
                      direction: .backward,
                      visibleRange: visibleRange,
                      pageCount: pages.count,
                      threshold: prefetchThreshold
                  ) {
            requestBackward()
        }
    }

    func requestForward() {
        guard let anchor = pages.last?.id else { return }
        isLoadingPageWindow = true
        let pageCount = self.pageCount
        let loadPage = self.loadPage
        let maxPixelWidth = 2400
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
                guard let image = loadPage(id, maxPixelWidth) else { return nil }
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
                self.applyForward(loaded)
            }
        }
    }

    func applyForward(_ loaded: [LoadedMangaPage]) {
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
#if DEBUG
        if !removed.isEmpty {
            print("[manga] evicted side=backward pages=\(removed.count) available=\(pages.count)")
        }
#endif
    }

    func requestBackward() {
        guard let anchor = pages.first?.id else { return }
        isLoadingPageWindow = true
        let pageCount = self.pageCount
        let loadPage = self.loadPage
        let maxPixelWidth = 2400
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
                guard let image = loadPage(id, maxPixelWidth) else { return nil }
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
                self.applyBackward(loaded)
                self.startInitialForwardPrefetchIfNeeded()
            }
        }
    }

    func startInitialForwardPrefetchIfNeeded() {
        guard shouldPrefetchForwardAfterInitialBackward else { return }
        shouldPrefetchForwardAfterInitialBackward = false
        requestForward()
    }

    func applyBackward(_ loaded: [LoadedMangaPage]) {
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
        containerView.relayout(updateVisibleViews: false)
        let y = oldY + addedHeight
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        containerView.updateVisiblePageViews(in: scrollView.contentView.bounds)
        lastScrollY = y
#if DEBUG
        if !removed.isEmpty {
            print("[manga] evicted side=forward pages=\(removed.count) available=\(pages.count)")
        }
#endif
    }
}

final class PageContainerView: NSView {
    override var isFlipped: Bool { true }

    private var pages: [LoadedMangaPage]
    private var pageFrames: [NSRect] = []
    private var imageViews: [MangaPageID: NSImageView] = [:]
    private var recycledImageViews: [NSImageView] = []

    init(pages: [LoadedMangaPage]) {
        self.pages = pages
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setPages(_ pages: [LoadedMangaPage]) {
        self.pages = pages
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
        let visible = pageFrames.indices.filter { pageFrames[$0].intersects(bounds) }
        guard let first = visible.first, let last = visible.last else { return 0..<0 }
        return first..<(last + 1)
    }

    func relayout(updateVisibleViews: Bool = true) {
        guard let scrollView = enclosingScrollView else { return }
        let width = scrollView.contentSize.width
        guard width > 0 else { return }

        var y: CGFloat = 0
        pageFrames = pages.map { page in
            guard page.image.size.width > 0, page.image.size.height > 0 else {
                return NSRect(x: 0, y: y, width: width, height: 0)
            }
            let height = round(width * page.image.size.height / page.image.size.width)
            let pageFrame = NSRect(x: 0, y: y, width: width, height: height)
            y += height
            return pageFrame
        }
        frame.size = CGSize(width: width, height: max(y, 1))
        if updateVisibleViews {
            updateVisiblePageViews(in: scrollView.contentView.bounds)
        }
    }

    func updateVisiblePageViews(in bounds: NSRect) {
        guard pageFrames.count == pages.count else { return }
        let overscan = bounds.insetBy(dx: 0, dy: -max(bounds.height * 2, 1000))
        let visibleIDs = Set(pageFrames.indices.compactMap { index in
            pageFrames[index].intersects(overscan) ? pages[index].id : nil
        })

        let staleIDs = imageViews.keys.filter { !visibleIDs.contains($0) }
        for id in staleIDs {
            guard let imageView = imageViews.removeValue(forKey: id) else { continue }
            imageView.removeFromSuperview()
            imageView.image = nil
            recycledImageViews.append(imageView)
        }

        for index in pageFrames.indices where visibleIDs.contains(pages[index].id) {
            let id = pages[index].id
            let imageView = imageViews[id] ?? makeImageView()
            if imageViews[id] == nil {
                imageViews[id] = imageView
                addSubview(imageView)
            }
            imageView.image = pages[index].image
            imageView.frame = pageFrames[index]
        }
    }

    private func makeImageView() -> NSImageView {
        if let imageView = recycledImageViews.popLast() {
            return imageView
        }
        let imageView = NSImageView()
        imageView.wantsLayer = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        return imageView
    }
}
