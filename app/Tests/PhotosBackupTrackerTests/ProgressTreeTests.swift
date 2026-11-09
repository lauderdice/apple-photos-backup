import Foundation
import Testing
@testable import PhotosBackupTracker

private func day(_ isoDay: String, total: Int, synced: Int) -> DayProgress {
    DayProgress(day: isoDay, totalItems: total, syncedItems: synced)
}

private let sampleDays = [
    day("2024-02-29", total: 4, synced: 0),
    day("2026-02-14", total: 2, synced: 2),
    day("2026-03-20", total: 18, synced: 18),
    day("2026-03-01", total: 5, synced: 1),
]

@Suite("Progress tree")
struct ProgressTreeTests {
    let library = ProgressTreeBuilder.buildLibrary(from: sampleDays)

    @Test func libraryTotalsAddUpEveryDay() {
        #expect(library.level == .library)
        #expect(library.title == "Photos Library")
        #expect(library.totalItems == 29)
        #expect(library.syncedItems == 21)
        #expect(library.missingItems == 8)
        #expect(library.firstDay == "2024-02-29")
        #expect(library.lastDay == "2026-03-20")
    }

    @Test func yearsMonthsAndDaysAreNewestFirst() {
        #expect(library.children.map(\.id) == ["2026", "2024"])
        #expect(library.children[0].children.map(\.id) == ["2026-03", "2026-02"])
        #expect(library.children[0].children[0].children.map(\.id) == ["2026-03-20", "2026-03-01"])
    }

    @Test func monthAndYearTotalsAreAggregated() {
        let year2026 = library.children[0]
        let march2026 = year2026.children[0]
        #expect((year2026.totalItems, year2026.syncedItems) == (25, 21))
        #expect((march2026.totalItems, march2026.syncedItems) == (23, 19))
    }

    @Test(arguments: [
        ("2024-02", "2024-02-29"),
        ("2026-02", "2026-02-28"),
        ("2026-03", "2026-03-31"),
        ("2025-04", "2025-04-30"),
    ])
    func monthRangeCoversTheWholeMonth(month: String, expectedLastDay: String) throws {
        let tree = ProgressTreeBuilder.buildLibrary(from: [day("\(month)-15", total: 1, synced: 0)])
        let monthNode = try #require(tree.indexedByID()[month])
        #expect(monthNode.firstDay == "\(month)-01")
        #expect(monthNode.lastDay == expectedLastDay)
    }

    @Test func yearRangeCoversTheWholeYear() {
        let year2024 = library.children[1]
        #expect(year2024.firstDay == "2024-01-01")
        #expect(year2024.lastDay == "2024-12-31")
    }

    @Test func dayRangeIsThatSingleDay() throws {
        let dayNode = try #require(library.indexedByID()["2026-02-14"])
        #expect(dayNode.level == .day)
        #expect((dayNode.firstDay, dayNode.lastDay) == ("2026-02-14", "2026-02-14"))
        #expect(dayNode.title.contains("2026"))
        #expect(dayNode.children.isEmpty)
    }

    @Test func yearsMonthsAndDaysCanBeSyncedButNotTheWholeLibrary() throws {
        let index = library.indexedByID()
        #expect(try #require(index["library"]).canBeSynced == false)
        #expect(try #require(index["2026"]).canBeSynced == true)
        #expect(try #require(index["2026-03"]).canBeSynced == true)
        #expect(try #require(index["2026-03-20"]).canBeSynced == true)
    }

    @Test func indexContainsEveryNodeExactlyOnce() {
        let index = library.indexedByID()
        #expect(index.count == 1 + 2 + 3 + 4)
        #expect(Set(index.keys) == ["library", "2026", "2024", "2026-03", "2026-02", "2024-02",
                                    "2026-03-20", "2026-03-01", "2026-02-14", "2024-02-29"])
    }

    @Test func syncedFractionHandlesEmptyAndPartialNodes() throws {
        #expect(ProgressTreeBuilder.buildLibrary(from: []).syncedFraction == 1)
        #expect(try #require(library.indexedByID()["2026-03-01"]).syncedFraction == 0.2)
    }

    @Test func emptyLibraryHasNoChildren() {
        let empty = ProgressTreeBuilder.buildLibrary(from: [])
        #expect(empty.children.isEmpty)
        #expect((empty.totalItems, empty.syncedItems) == (0, 0))
    }

    @Test func monthTitleIsHumanReadable() throws {
        let march = try #require(library.indexedByID()["2026-03"])
        #expect(march.title.contains("2026"))
        #expect(march.title != "2026-03")
    }

    @Test func decodesTheCLIsSnakeCaseJSON() throws {
        let json = Data(#"{"days": [{"day": "2026-02-14", "total_items": 2, "synced_items": 1}]}"#.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let report = try decoder.decode(ProgressReport.self, from: json)

        #expect(report.days.count == 1)
        #expect((report.days[0].day, report.days[0].totalItems, report.days[0].syncedItems) == ("2026-02-14", 2, 1))
    }
}
