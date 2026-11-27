import Foundation
import Combine

enum RestSource: String, Codable {
    case countdown, automatic, manual, skipped

    var title: String {
        switch self {
        case .countdown: L.tr("短休息计时结束")
        case .automatic: L.tr("自动计为休息")
        case .manual: L.tr("我刚休息过")
        case .skipped: L.tr("跳过休息")
        }
    }
}

struct RestEvent: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let source: RestSource
}

struct RestDay: Identifiable {
    let id: Date
    let events: [RestEvent]
    var skipped: Int { events.filter { $0.source == .skipped }.count }
    var completed: Int { events.count - skipped }
    var clean: Bool { completed > 0 && skipped == 0 }
    var onlyRecognized: Bool { clean && !events.contains { $0.source == .countdown } }
}

@MainActor
final class RestHistory: ObservableObject {
    @Published private(set) var events: [RestEvent] = []
    @Published private(set) var today: Date
    @Published private(set) var unavailable = false
    private let file: URL
    private let calendar: Calendar
    private var pending: [RestEvent] = []

    static var applicationFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Breather")
            .appendingPathComponent("rest-history.json")
    }

    init(file: URL = RestHistory.applicationFile, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) {
        self.file = file
        self.calendar = calendar
        today = calendar.startOfDay(for: now)
        synchronize()
    }

    func record(_ event: RestEvent) {
        pending.append(event)
        synchronize()
    }

    func refresh(at date: Date) {
        let day = calendar.startOfDay(for: date)
        guard today != day else { return }
        today = day
        synchronize()
    }

    func retry() { synchronize() }

    private func synchronize() {
        do {
            let saved: [RestEvent]
            do {
                saved = try JSONDecoder().decode([RestEvent].self, from: Data(contentsOf: file))
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                saved = []
            }
            let cutoff = calendar.date(byAdding: .day, value: -29, to: today)!
            var ids = Set<UUID>()
            let next = (saved + pending).filter { $0.date >= cutoff && ids.insert($0.id).inserted }
                .sorted { $0.date < $1.date }
            if next != saved {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(next).write(to: file, options: .atomic)
            }
            events = next
            pending.removeAll()
            unavailable = false
        } catch {
            unavailable = true
        }
    }

    func days(_ count: Int) -> [RestDay] {
        let byDay = Dictionary(grouping: events) { calendar.startOfDay(for: $0.date) }
        return (1-count...0).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today).map { RestDay(id: $0, events: byDay[$0] ?? []) }
        }
    }
}
