import Foundation

/// One day as reported by `photos-backup progress`.
struct DayProgress: Decodable {
    let day: String
    let totalItems: Int
    let syncedItems: Int
}

struct ProgressReport: Decodable {
    let days: [DayProgress]
}

enum ProgressLevel {
    case library, year, month, day
}

/// A node in the Library → year → month → day tree, with synced/total item counts.
struct ProgressNode: Identifiable {
    let id: String
    let level: ProgressLevel
    let title: String
    let firstDay: String
    let lastDay: String
    let syncedItems: Int
    let totalItems: Int
    let children: [ProgressNode]

    var missingItems: Int { totalItems - syncedItems }
    var syncedFraction: Double { totalItems == 0 ? 1 : Double(syncedItems) / Double(totalItems) }
    var canBeSynced: Bool { level != .library }

    func indexedByID() -> [String: ProgressNode] {
        children.reduce(into: [id: self]) { index, child in
            index.merge(child.indexedByID()) { existing, _ in existing }
        }
    }
}

enum ProgressTreeBuilder {
    private static let isoDayFormatter: DateFormatter = makeFormatter("yyyy-MM-dd", locale: Locale(identifier: "en_US_POSIX"))
    private static let monthTitleFormatter: DateFormatter = makeFormatter("LLLL yyyy", locale: .current)
    private static let dayTitleFormatter: DateFormatter = makeFormatter("EEEE d MMMM yyyy", locale: .current)

    static func buildLibrary(from days: [DayProgress]) -> ProgressNode {
        let yearNodes = Dictionary(grouping: days) { String($0.day.prefix(4)) }
            .map { year, daysInYear in buildYear(year, daysInYear) }
            .sorted { $0.id > $1.id }
        return ProgressNode(
            id: "library",
            level: .library,
            title: "Photos Library",
            firstDay: days.map(\.day).min() ?? "",
            lastDay: days.map(\.day).max() ?? "",
            syncedItems: yearNodes.reduce(0) { $0 + $1.syncedItems },
            totalItems: yearNodes.reduce(0) { $0 + $1.totalItems },
            children: yearNodes
        )
    }

    private static func buildYear(_ year: String, _ days: [DayProgress]) -> ProgressNode {
        let monthNodes = Dictionary(grouping: days) { String($0.day.prefix(7)) }
            .map { month, daysInMonth in buildMonth(month, daysInMonth) }
            .sorted { $0.id > $1.id }
        return ProgressNode(
            id: year,
            level: .year,
            title: year,
            firstDay: "\(year)-01-01",
            lastDay: "\(year)-12-31",
            syncedItems: monthNodes.reduce(0) { $0 + $1.syncedItems },
            totalItems: monthNodes.reduce(0) { $0 + $1.totalItems },
            children: monthNodes
        )
    }

    private static func buildMonth(_ month: String, _ days: [DayProgress]) -> ProgressNode {
        let firstDayOfMonth = isoDayFormatter.date(from: "\(month)-01")!
        let daysInMonth = Calendar.current.range(of: .day, in: .month, for: firstDayOfMonth)!.count
        let dayNodes = days.sorted { $0.day > $1.day }.map(buildDay)
        return ProgressNode(
            id: month,
            level: .month,
            title: monthTitleFormatter.string(from: firstDayOfMonth).capitalized,
            firstDay: "\(month)-01",
            lastDay: "\(month)-\(String(format: "%02d", daysInMonth))",
            syncedItems: dayNodes.reduce(0) { $0 + $1.syncedItems },
            totalItems: dayNodes.reduce(0) { $0 + $1.totalItems },
            children: dayNodes
        )
    }

    private static func buildDay(_ day: DayProgress) -> ProgressNode {
        ProgressNode(
            id: day.day,
            level: .day,
            title: dayTitleFormatter.string(from: isoDayFormatter.date(from: day.day)!),
            firstDay: day.day,
            lastDay: day.day,
            syncedItems: day.syncedItems,
            totalItems: day.totalItems,
            children: []
        )
    }

    private static func makeFormatter(_ format: String, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = format
        return formatter
    }
}
