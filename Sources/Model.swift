import Foundation
import Observation

enum Frequency: String, Codable, CaseIterable { case daily, days, weekly }

struct Habit: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var emoji: String = "✅"
    var frequency: Frequency = .daily
    var days: [Int] = [0, 1, 2, 3, 4]        // Mon = 0
    var perWeek: Int = 3
    var start: String                         // yyyy-MM-dd
    var remind: Bool = false
    var remindHour: Int = 20
}

enum Day {
    static let cal: Calendar = { var c = Calendar(identifier: .iso8601); c.timeZone = .current; return c }()
    static let f: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.calendar = cal; f.timeZone = .current; return f }()
    static func key(_ d: Date) -> String { f.string(from: d) }
    static func date(_ k: String) -> Date { f.date(from: k) ?? .now }
    static var today: String { key(.now) }
    static func add(_ k: String, _ n: Int) -> String { key(cal.date(byAdding: .day, value: n, to: date(k))!) }
    /// Monday = 0 … Sunday = 6
    static func dow(_ k: String) -> Int { (cal.component(.weekday, from: date(k)) + 5) % 7 }
    static func weekStart(_ k: String) -> String { add(k, -dow(k)) }
    static func diff(_ a: String, _ b: String) -> Int { cal.dateComponents([.day], from: date(a), to: date(b)).day ?? 0 }
    static let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
}

@Observable
final class Store {
    var habits: [Habit] = []
    var log: [String: [UUID]] = [:]           // day key -> habits done
    var weekOffset = 0
    private var saveTask: Task<Void, Never>?
    private let url = URL.documentsDirectory.appending(path: "chain.json")
    struct Disk: Codable { var habits: [Habit]; var log: [String: [UUID]] }

    init(demo: Bool) {
        if demo { Demo.fill(self); return }
        if let d = try? Data(contentsOf: url), let disk = try? JSONDecoder().decode(Disk.self, from: d) { habits = disk.habits; log = disk.log }
    }
    func save() {
        saveTask?.cancel(); let disk = Disk(habits: habits, log: log); let u = url
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(200)); if Task.isCancelled { return }
            if let d = try? JSONEncoder().encode(disk) { try? d.write(to: u, options: .atomic) }
        }
    }

    func done(_ h: Habit, _ day: String) -> Bool { log[day]?.contains(h.id) ?? false }
    func due(_ h: Habit, _ day: String) -> Bool {
        guard day >= h.start else { return false }
        switch h.frequency {
        case .daily, .weekly: return true
        case .days: return h.days.contains(Day.dow(day))
        }
    }
    func toggle(_ h: Habit, _ day: String) {
        var l = log[day] ?? []
        if let i = l.firstIndex(of: h.id) { l.remove(at: i) } else { l.append(h.id) }
        log[day] = l; save()
    }
    func weekHits(_ h: Habit, _ anyDay: String) -> Int {
        let ws = Day.weekStart(anyDay); return (0..<7).filter { done(h, Day.add(ws, $0)) }.count
    }
    func satisfiedToday(_ h: Habit) -> Bool { h.frequency == .weekly ? (weekHits(h, Day.today) >= h.perWeek || done(h, Day.today)) : done(h, Day.today) }

    func streak(_ h: Habit) -> Int {
        if h.frequency == .weekly {
            var s = 0; var ws = Day.weekStart(Day.today)
            if weekHits(h, ws) >= h.perWeek { s += 1 }
            ws = Day.add(ws, -7)
            while ws >= Day.weekStart(h.start) && weekHits(h, ws) >= h.perWeek { s += 1; ws = Day.add(ws, -7) }
            return s
        }
        var s = 0; var d = Day.today
        if !done(h, d) { d = Day.add(d, -1) }
        while d >= h.start {
            if due(h, d) { if done(h, d) { s += 1 } else { break } }
            d = Day.add(d, -1)
        }
        return s
    }
    func best(_ h: Habit) -> Int {
        var b = 0, s = 0; var d = h.start
        while d <= Day.today {
            if due(h, d) { if done(h, d) { s += 1; b = max(b, s) } else { s = 0 } }
            d = Day.add(d, 1)
        }
        return b
    }
    func rate(_ h: Habit, days: Int) -> Double {
        if h.frequency == .weekly {
            var w = 0, ok = 0
            for i in 0..<max(1, days / 7) { let ws = Day.add(Day.weekStart(Day.today), -7 * i); if ws < Day.weekStart(h.start) { break }; w += 1; if weekHits(h, ws) >= h.perWeek { ok += 1 } }
            return w > 0 ? Double(ok) / Double(w) : 0
        }
        var d = 0, hit = 0
        for i in 0..<days { let k = Day.add(Day.today, -i); if due(h, k) { d += 1; if done(h, k) { hit += 1 } } }
        return d > 0 ? Double(hit) / Double(d) : 0
    }
    func total(_ h: Habit) -> Int { log.values.filter { $0.contains(h.id) }.count }
    var totalDone: Int { log.values.reduce(0) { $0 + $1.count } }

    func perfectDays(_ days: Int) -> Int {
        var n = 0
        for i in 0..<days {
            let k = Day.add(Day.today, -i); let dueH = habits.filter { due($0, k) && $0.frequency != .weekly }
            if !dueH.isEmpty && dueH.allSatisfy({ done($0, k) }) { n += 1 }
        }
        return n
    }
    func weekdayRates() -> [Double] {
        var due_ = Array(repeating: 0, count: 7), hit = Array(repeating: 0, count: 7)
        for i in 0..<90 { let k = Day.add(Day.today, -i); let w = Day.dow(k); for h in habits where h.frequency != .weekly && due(h, k) { due_[w] += 1; if done(h, k) { hit[w] += 1 } } }
        return (0..<7).map { due_[$0] > 0 ? Double(hit[$0]) / Double(due_[$0]) : 0 }
    }
}
