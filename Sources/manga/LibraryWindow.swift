import AppKit

struct MangaSeries {
    let name: String
    let path: URL
    let coverURL: URL?
    let chapterURLs: [URL]

    static func scanLibrary(at rootPath: String) -> [MangaSeries] {
        let root = URL(fileURLWithPath: rootPath)
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents.compactMap { dir in
            guard let resourceValues = try? dir.resourceValues(forKeys: [.isDirectoryKey]),
                  resourceValues.isDirectory == true else { return nil }

            let name = dir.lastPathComponent.replacingOccurrences(of: "_", with: " ")
            let coverExtensions = ["jpg", "jpeg", "png", "webp"]
            let coverURL = coverExtensions.compactMap { ext -> URL? in
                let url = dir.appendingPathComponent("cover.\(ext)")
                return fm.fileExists(atPath: url.path) ? url : nil
            }.first

            let chapterURLs = (try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ))?.filter { $0.pathExtension.lowercased() == "cbz" }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                ?? []

            guard !chapterURLs.isEmpty else { return nil }
            return MangaSeries(name: name, path: dir, coverURL: coverURL, chapterURLs: chapterURLs)
        }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

final class LibraryWindowController: NSWindowController {
    private let onOpen: (URL, [URL], Int) -> Void

    init(libraryPath: String, onOpen: @escaping (URL, [URL], Int) -> Void) {
        self.onOpen = onOpen

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Manga"
        window.backgroundColor = NSColor(white: 0.08, alpha: 1.0)
        window.setFrameAutosaveName("mangaLibrary")

        super.init(window: window)

        let series = MangaSeries.scanLibrary(at: libraryPath)
        let vc = LibraryViewController(series: series, onOpen: onOpen)
        window.contentViewController = vc

        if let screen = window.screen ?? NSScreen.main {
            let screenFrame = screen.visibleFrame
            let width = screenFrame.width * 0.6
            let height = screenFrame.height * 0.85
            let x = screenFrame.midX - width / 2
            let y = screenFrame.midY - height / 2
            window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class LibraryViewController: NSViewController {
    private let series: [MangaSeries]
    private let onOpen: (URL, [URL], Int) -> Void

    private var collectionView: NSCollectionView!
    private var gridScrollView: NSScrollView!
    private var flowLayout: NSCollectionViewFlowLayout!
    private var tableView: NSTableView!
    private var tableViewScrollView: NSScrollView!
    private var backButton: NSButton!
    private var selectedSeries: MangaSeries?
    private var headerView: NSView!
    private var hasLaidOut = false
    private var collectionConfigured = false

    private enum Mode { case grid, list }
    private var mode: Mode = .grid {
        didSet { updateVisibility() }
    }

    init(series: [MangaSeries], onOpen: @escaping (URL, [URL], Int) -> Void) {
        self.series = series
        self.onOpen = onOpen
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(white: 0.08, alpha: 1.0).cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        headerView = NSView(frame: .zero)
        headerView.autoresizingMask = [.width, .minYMargin]

        backButton = NSButton(
            title: "← Back",
            target: self,
            action: #selector(goBack)
        )
        backButton.bezelStyle = .inline
        backButton.isBordered = false
        backButton.font = NSFont.systemFont(ofSize: 13)
        backButton.frame = NSRect(x: 12, y: 4, width: 60, height: 28)
        headerView.addSubview(backButton)
        view.addSubview(headerView)

        let contentFrame = NSRect(x: 0, y: 0, width: view.bounds.width, height: max(0, view.bounds.height - 36))

        gridScrollView = NSScrollView(frame: contentFrame)
        gridScrollView.autoresizingMask = [.width, .height]
        gridScrollView.hasHorizontalScroller = false
        gridScrollView.hasVerticalScroller = true
        gridScrollView.autohidesScrollers = true
        gridScrollView.drawsBackground = false
        gridScrollView.borderType = .noBorder

        flowLayout = NSCollectionViewFlowLayout()
        flowLayout.minimumInteritemSpacing = 16
        flowLayout.minimumLineSpacing = 20
        flowLayout.sectionInset = NSEdgeInsetsZero

        collectionView = NSCollectionView(frame: gridScrollView.bounds)
        collectionView.autoresizingMask = [.width, .height]
        collectionView.isSelectable = true
        collectionView.backgroundColors = [NSColor(white: 0.08, alpha: 1.0)]
        collectionView.register(
            CoverGridItem.self,
            forItemWithIdentifier: NSUserInterfaceItemIdentifier("cover")
        )

        gridScrollView.documentView = collectionView
        view.addSubview(gridScrollView)

        tableViewScrollView = NSScrollView(frame: contentFrame)
        tableViewScrollView.autoresizingMask = [.width, .height]
        tableViewScrollView.hasHorizontalScroller = false
        tableViewScrollView.hasVerticalScroller = true
        tableViewScrollView.autohidesScrollers = true
        tableViewScrollView.drawsBackground = false
        tableViewScrollView.borderType = .noBorder

        tableView = NSTableView(frame: tableViewScrollView.bounds)
        tableView.autoresizingMask = [.width, .height]
        tableView.backgroundColor = NSColor(white: 0.08, alpha: 1.0)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("chapter"))
        column.title = ""
        column.width = tableViewScrollView.bounds.width
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.headerView = nil
        tableView.rowHeight = 32
        tableView.intercellSpacing = NSSize(width: 0, height: 0)

        tableViewScrollView.documentView = tableView
        view.addSubview(tableViewScrollView)

        updateVisibility()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let contentFrame = NSRect(x: 0, y: 0, width: view.bounds.width, height: max(0, view.bounds.height - 36))
        gridScrollView.frame = contentFrame
        collectionView.frame = gridScrollView.bounds
        tableViewScrollView.frame = contentFrame
        headerView.frame = NSRect(x: 0, y: max(0, view.bounds.height - 36), width: view.bounds.width, height: 36)
        if view.bounds.width > 0, view.bounds.height > 0 {
            hasLaidOut = true
        }
        updateVisibility()
        if mode == .grid {
            if let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout,
               collectionConfigured, collectionView.bounds.width > 40 {
                layout.sectionInset = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
            }
            if collectionConfigured {
                collectionView.collectionViewLayout?.invalidateLayout()
            }
        }
        if tableView.tableColumns.count > 0 {
            tableView.tableColumns[0].width = tableViewScrollView.bounds.width
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.layoutSubtreeIfNeeded()
        guard collectionView.bounds.width > 40 else { return }
        hasLaidOut = true
        collectionView.collectionViewLayout = flowLayout
        collectionView.register(
            CoverGridItem.self,
            forItemWithIdentifier: NSUserInterfaceItemIdentifier("cover")
        )
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionConfigured = true
        if let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout {
            layout.sectionInset = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        }
        collectionView.reloadData()
        updateVisibility()
    }

    private func updateVisibility() {
        let isGrid = mode == .grid
        gridScrollView.isHidden = !isGrid || !hasLaidOut
        tableViewScrollView.isHidden = isGrid
        headerView.isHidden = isGrid
        backButton.isHidden = isGrid
    }

    @objc private func goBack() {
        mode = .grid
        selectedSeries = nil
    }
}

extension LibraryViewController: NSCollectionViewDataSource, NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        collectionView.bounds.width > 40 ? series.count : 0
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: NSUserInterfaceItemIdentifier("cover"),
            for: indexPath
        ) as! CoverGridItem
        let s = series[indexPath.item]
        item.configure(coverURL: s.coverURL, title: s.name)
        return item
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        layout collectionViewLayout: NSCollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> NSSize {
        let inset = (collectionViewLayout as? NSCollectionViewFlowLayout)?.sectionInset ?? NSEdgeInsetsZero
        let spacing = (collectionViewLayout as? NSCollectionViewFlowLayout)?.minimumInteritemSpacing ?? 0
        let contentInset = collectionView.enclosingScrollView?.contentInsets ?? NSEdgeInsetsZero
        let availableWidth = collectionView.bounds.width
            - inset.left - inset.right
            - contentInset.left - contentInset.right
        guard availableWidth > 10 else { return .zero }
        let columns: CGFloat = max(1, floor(availableWidth / 220))
        let itemWidth = min(
            availableWidth - 1,
            max(1, (availableWidth - spacing * (columns - 1)) / columns)
        )
        let itemHeight = itemWidth * 1.45 + 36
        return NSSize(width: itemWidth, height: itemHeight)
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let indexPath = indexPaths.first else { return }
        let s = series[indexPath.item]
        selectedSeries = s
        tableView.reloadData()
        mode = .list
    }
}

extension LibraryViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        selectedSeries?.chapterURLs.count ?? 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let s = selectedSeries else { return nil }
        let url = s.chapterURLs[row]
        let displayName = url.lastPathComponent

        let tf = NSTextField(labelWithString: displayName)
        tf.font = NSFont.systemFont(ofSize: 14)
        tf.textColor = NSColor(white: 0.9, alpha: 1.0)
        tf.frame = NSRect(x: 16, y: 4, width: max(1, tableView.bounds.width - 32), height: 22)
        tf.autoresizingMask = .width

        let cell = NSTableCellView()
        cell.identifier = NSUserInterfaceItemIdentifier("chapterCell")
        cell.addSubview(tf)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let s = selectedSeries, tableView.selectedRow >= 0 else { return }
        let url = s.chapterURLs[tableView.selectedRow]
        onOpen(url, s.chapterURLs, tableView.selectedRow)
        tableView.deselectAll(nil)
    }
}

final class CoverGridItem: NSCollectionViewItem {
    private let coverImageView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        coverImageView.wantsLayer = true
        coverImageView.imageScaling = .scaleProportionallyUpOrDown
        coverImageView.frame = NSRect(x: 0, y: 36, width: 200, height: 264)
        coverImageView.autoresizingMask = [.width]
        view.addSubview(coverImageView)

        titleField.font = NSFont.systemFont(ofSize: 12)
        titleField.textColor = NSColor(white: 0.8, alpha: 1.0)
        titleField.alignment = .center
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 2
        titleField.frame = NSRect(x: 0, y: 4, width: 200, height: 28)
        titleField.autoresizingMask = [.width]
        view.addSubview(titleField)
    }

    func configure(coverURL: URL?, title: String) {
        titleField.stringValue = title
        if let url = coverURL {
            coverImageView.image = NSImage(contentsOf: url)
        } else {
            coverImageView.image = nil
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let w = view.bounds.width
        coverImageView.frame = NSRect(x: 0, y: 36, width: w, height: max(0, view.bounds.height - 40))
        titleField.frame = NSRect(x: 0, y: 4, width: w, height: 28)
    }
}
