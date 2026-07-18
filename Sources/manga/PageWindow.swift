struct MangaPageNavigation {
    static func nextPage(after id: MangaPageID, pageCount: (Int) -> Int) -> MangaPageID? {
        if id.page + 1 < pageCount(id.chapter) {
            return MangaPageID(chapter: id.chapter, page: id.page + 1)
        }
        let chapter = id.chapter + 1
        guard pageCount(chapter) > 0 else { return nil }
        return MangaPageID(chapter: chapter, page: 0)
    }

    static func previousPage(before id: MangaPageID, pageCount: (Int) -> Int) -> MangaPageID? {
        if id.page > 0 {
            return MangaPageID(chapter: id.chapter, page: id.page - 1)
        }
        let chapter = id.chapter - 1
        let count = pageCount(chapter)
        guard count > 0 else { return nil }
        return MangaPageID(chapter: chapter, page: count - 1)
    }

    static func initialPages(
        startingChapter: Int,
        limit: Int,
        pageCount: (Int) -> Int
    ) -> [MangaPageID] {
        var result: [MangaPageID] = []
        var next = MangaPageID(chapter: startingChapter, page: 0)
        while result.count < limit {
            guard next.page < pageCount(next.chapter) else { break }
            result.append(next)
            guard let following = nextPage(after: next, pageCount: pageCount) else { break }
            next = following
        }
        return result
    }
}

struct MangaPageWindow {
    private(set) var pages: [MangaPageID]
    let capacity: Int

    init(pages: [MangaPageID], capacity: Int = 20) {
        self.pages = Array(pages.prefix(capacity))
        self.capacity = capacity
    }

    mutating func append(_ newPages: [MangaPageID]) -> [MangaPageID] {
        pages.append(contentsOf: newPages)
        let removeCount = max(0, pages.count - capacity)
        let removed = Array(pages.prefix(removeCount))
        pages.removeFirst(removeCount)
        return removed
    }

    mutating func prepend(_ newPages: [MangaPageID]) -> [MangaPageID] {
        pages.insert(contentsOf: newPages, at: 0)
        let removeCount = max(0, pages.count - capacity)
        let removed = Array(pages.suffix(removeCount))
        pages.removeLast(removeCount)
        return removed
    }
}
