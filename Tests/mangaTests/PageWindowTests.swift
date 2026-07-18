import XCTest
@testable import manga

final class PageWindowTests: XCTestCase {
    private let pageCounts = [3, 2, 4]

    func testNavigationMovesAcrossChapterBoundaries() {
        XCTAssertEqual(
            MangaPageNavigation.nextPage(after: MangaPageID(chapter: 0, page: 2), pageCount: count),
            MangaPageID(chapter: 1, page: 0)
        )
        XCTAssertEqual(
            MangaPageNavigation.previousPage(before: MangaPageID(chapter: 1, page: 0), pageCount: count),
            MangaPageID(chapter: 0, page: 2)
        )
    }

    func testNavigationClampsAtLibraryBoundaries() {
        XCTAssertNil(
            MangaPageNavigation.previousPage(before: afterFirstPage, pageCount: count)
        )
        XCTAssertNil(
            MangaPageNavigation.nextPage(after: MangaPageID(chapter: 2, page: 3), pageCount: count)
        )
    }

    func testInitialPagesContinueIntoFollowingChapters() {
        let pages = MangaPageNavigation.initialPages(startingChapter: 1, limit: 20, pageCount: count)

        XCTAssertEqual(pages, [
            MangaPageID(chapter: 1, page: 0),
            MangaPageID(chapter: 1, page: 1),
            MangaPageID(chapter: 2, page: 0),
            MangaPageID(chapter: 2, page: 1),
            MangaPageID(chapter: 2, page: 2),
            MangaPageID(chapter: 2, page: 3)
        ])
    }

    func testAppendingKeepsTheNewestPagesWithinCapacity() {
        var window = MangaPageWindow(pages: (0..<5).map { MangaPageID(chapter: 0, page: $0) }, capacity: 5)

        let removed = window.append([
            MangaPageID(chapter: 1, page: 0),
            MangaPageID(chapter: 1, page: 1)
        ])

        XCTAssertEqual(removed, [
            MangaPageID(chapter: 0, page: 0),
            MangaPageID(chapter: 0, page: 1)
        ])
        XCTAssertEqual(window.pages, [
            MangaPageID(chapter: 0, page: 2),
            MangaPageID(chapter: 0, page: 3),
            MangaPageID(chapter: 0, page: 4),
            MangaPageID(chapter: 1, page: 0),
            MangaPageID(chapter: 1, page: 1)
        ])
    }

    func testPrependingKeepsTheOldestPagesWithinCapacity() {
        var window = MangaPageWindow(pages: (3..<8).map { MangaPageID(chapter: 0, page: $0) }, capacity: 5)

        let removed = window.prepend([
            MangaPageID(chapter: 0, page: 1),
            MangaPageID(chapter: 0, page: 2)
        ])

        XCTAssertEqual(removed, [
            MangaPageID(chapter: 0, page: 6),
            MangaPageID(chapter: 0, page: 7)
        ])
        XCTAssertEqual(window.pages, (1..<6).map { MangaPageID(chapter: 0, page: $0) })
    }

    private var afterFirstPage: MangaPageID {
        MangaPageID(chapter: 0, page: 0)
    }

    private func count(_ chapter: Int) -> Int {
        pageCounts.indices.contains(chapter) ? pageCounts[chapter] : 0
    }
}
