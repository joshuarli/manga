import Foundation
import XCTest
@testable import manga

final class CBZBookTests: XCTestCase {
    func testArchivesHaveIndependentExtractionDirectoriesAndPageCounts() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("manga-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let firstURL = try makeArchive(at: root, name: "first", pageCount: 2)
        let secondURL = try makeArchive(at: root, name: "second", pageCount: 3)
        guard let first = CBZBook(url: firstURL), let second = CBZBook(url: secondURL) else {
            return XCTFail("Synthetic archives should open")
        }
        defer {
            first.cleanup()
            second.cleanup()
        }

        XCTAssertEqual(first.pageCount, 2)
        XCTAssertEqual(second.pageCount, 3)
        XCTAssertNotEqual(first.tempDir, second.tempDir)
    }

    private func makeArchive(at root: URL, name: String, pageCount: Int) throws -> URL {
        let source = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let names = (0..<pageCount).map { "page-\($0).webp" }
        for name in names {
            try Data([0]).write(to: source.appendingPathComponent(name))
        }

        let archive = root.appendingPathComponent("\(name).cbz")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = source
        process.arguments = ["-q", archive.path] + names
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return archive
    }
}
