import Foundation
import Observation

enum Frequency: String, Codable, CaseIterable { case daily, days, weekly }

/// Build a habit (tick it off) or quit one (count the clean days, log a slip).
enum Kind: String, Codable, CaseIterable { case build, quit }

/// When in the day a habit lives; Today groups by it.
enum Part: String, Codable, CaseIterable {
    case anytime, morning, afternoon, evening
    var title: String {
        switch self {
        case .anytime: return "Anytime"
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        }
    }
    var icon: String {
        switch self {
        case .anytime: return "circle.dashed"
        case .morning: return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .evening: return "moon.stars.fill"
        }
    }
}

/// Apple Health numbers a habit can tick itself off from.
enum HealthMetric: String, Codable, CaseIterable, Identifiable {
    case steps, exercise, mindful, workouts
    var id: String { rawValue }
    var title: String {
        switch self {
        case .steps: return "Steps"
        case .exercise: return "Exercise minutes"
        case .mindful: return "Mindful minutes"
        case .workouts: return "Workouts"
        }
    }
    var unit: String {
        switch self {
        case .steps: return "steps"
        case .exercise, .mindful: return "min"
        case .workouts: return "workout"
        }
    }
    var defaultTarget: Int {
        switch self {
        case .steps: return 8000
        case .exercise: return 30
        case .mindful: return 10
        case .workouts: return 1
        }
    }
}

/// A stretch of days a habit is paused for: holiday, illness. Paused days are not due.
struct Pause: Codable, Hashable { var from: String; var to: String }

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
    var remindMinute: Int = 0
    var kind: Kind = .build
    /// 1 is a plain tick. More than 1 is an amount: 8 glasses, 20 pages.
    var target: Int = 1
    var unit: String = ""
    var step: Int = 1
    var health: HealthMetric? = nil
    var part: Part = .anytime
    var pauses: [Pause] = []
    var archived: Bool = false

    var isAmount: Bool { target > 1 || health != nil }
}

extension Habit {
    /// Every field after `remindHour` arrived in 1.2. A 1.1 file has none of them, and a
    /// synthesized decoder would throw on the first missing key and lose the person's data.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        start = try c.decode(String.self, forKey: .start)
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? "✅"
        frequency = try c.decodeIfPresent(Frequency.self, forKey: .frequency) ?? .daily
        days = try c.decodeIfPresent([Int].self, forKey: .days) ?? [0, 1, 2, 3, 4]
        perWeek = try c.decodeIfPresent(Int.self, forKey: .perWeek) ?? 3
        remind = try c.decodeIfPresent(Bool.self, forKey: .remind) ?? false
        remindHour = try c.decodeIfPresent(Int.self, forKey: .remindHour) ?? 20
        remindMinute = try c.decodeIfPresent(Int.self, forKey: .remindMinute) ?? 0
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .build
        target = max(1, try c.decodeIfPresent(Int.self, forKey: .target) ?? 1)
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? ""
        step = max(1, try c.decodeIfPresent(Int.self, forKey: .step) ?? 1)
        health = try? c.decodeIfPresent(HealthMetric.self, forKey: .health)
        part = (try? c.decodeIfPresent(Part.self, forKey: .part)) ?? .anytime
        pauses = try c.decodeIfPresent([Pause].self, forKey: .pauses) ?? []
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
    }
}

enum Day {
    static let cal: Calendar = { var c = Calendar(identifier: .iso8601); c.timeZone = .current; return c }()
    static let f: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.calendar = cal; f.timeZone = .current; f.locale = Locale(identifier: "en_US_POSIX"); return f }()
    static func key(_ d: Date) -> String { f.string(from: d) }
    static func date(_ k: String) -> Date { f.date(from: k) ?? .now }
    static var today: String { key(.now) }
    static func add(_ k: String, _ n: Int) -> String { key(cal.date(byAdding: .day, value: n, to: date(k))!) }
    /// Monday = 0 … Sunday = 6
    static func dow(_ k: String) -> Int { (cal.component(.weekday, from: date(k)) + 5) % 7 }
    static func weekStart(_ k: String) -> String { add(k, -dow(k)) }
    static func diff(_ a: String, _ b: String) -> Int { cal.dateComponents([.day], from: date(a), to: date(b)).day ?? 0 }
    static func month(_ k: String) -> String { String(k.prefix(7)) }
    static let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
}

/// A broken chain that can still be saved: the most recent due day was missed, recently.
struct Rescue: Identifiable, Hashable {
    let habit: Habit
    let day: String
    let lost: Int
    var id: String { habit.id.uuidString + day }
}

/// Where the data lives. The app group container, so the widgets read and write the same file.
enum Shared {
    static let group = "group.com.mattbusel.chainhabits"
    static let defaults = UserDefaults(suiteName: group) ?? .standard
    static var container: URL { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) ?? URL.documentsDirectory }
    static var file: URL { container.appending(path: "chain.json") }
    /// Chain Unlimited, mirrored here by the app so the widgets know.
    static var unlocked: Bool {
        get { defaults.bool(forKey: "unlocked") }
        set { defaults.set(newValue, forKey: "unlocked") }
    }
    static var theme: String {
        get { defaults.string(forKey: "theme") ?? "lime" }
        set { defaults.set(newValue, forKey: "theme") }
    }
    /// 1.1 kept the file in the app's own Documents, where a widget cannot reach it.
    static func migrate() {
        let old = URL.documentsDirectory.appending(path: "chain.json")
        let fm = FileManager.default
        guard !fm.fileExists(atPath: file.path), fm.fileExists(atPath: old.path), file != old else { return }
        try? fm.copyItem(at: old, to: file)
    }
}

extension Notification.Name {
    /// The file changed under the app: a widget, a notification action or Siri wrote it.
    static let chainExternalChange = Notification.Name("chainExternalChange")
}

@Observable
final class Store {
    var habits: [Habit] = []
    var log: [String: [UUID]] = [:]               // day -> habits done (for quit habits: slipped)
    var counts: [String: [String: Int]] = [:]     // day -> habit id -> amount
    var frozen: [String: [UUID]] = [:]            // day -> habits a freeze covered
    var repaired: [String: [UUID]] = [:]          // day -> habits a Streak Repair patched
    var notes: [String: [String: String]] = [:]   // day -> habit id -> note
    var freezeSpend: [String: Int] = [:]          // yyyy-MM -> freezes used that month
    var repairCredits = 0
    var stamp: Double = 0
    var weekOffset = 0
    @ObservationIgnored var didSave: (() -> Void)?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let demo: Bool

    struct Disk: Codable {
        var habits: [Habit]
        var log: [String: [UUID]]
        var counts: [String: [String: Int]]? = nil
        var frozen: [String: [UUID]]? = nil
        var repaired: [String: [UUID]]? = nil
        var notes: [String: [String: String]]? = nil
        var freezeSpend: [String: Int]? = nil
        var repairCredits: Int? = nil
        var stamp: Double? = nil
    }

    init(demo: Bool) {
        self.demo = demo
        if demo { Demo.fill(self); return }
        Shared.migrate()
        load()
    }

    func load() {
        guard let d = try? Data(contentsOf: Shared.file) else { return }
        apply(d)
    }
    @discardableResult func apply(_ d: Data) -> Bool {
        guard let disk = try? JSONDecoder().decode(Disk.self, from: d) else { return false }
        habits = disk.habits; log = disk.log
        counts = disk.counts ?? [:]; frozen = disk.frozen ?? [:]; repaired = disk.repaired ?? [:]
        notes = disk.notes ?? [:]; freezeSpend = disk.freezeSpend ?? [:]
        repairCredits = disk.repairCredits ?? 0; stamp = disk.stamp ?? 0
        return true
    }
    func encoded() -> Data? {
        try? JSONEncoder().encode(Disk(habits: habits, log: log, counts: counts, frozen: frozen, repaired: repaired,
                                       notes: notes, freezeSpend: freezeSpend, repairCredits: repairCredits, stamp: stamp))
    }
    /// Debounced, off the main thread: for the app, where taps come in bursts.
    func save() {
        guard !demo else { didSave?(); return }
        stamp = Date().timeIntervalSince1970
        saveTask?.cancel()
        guard let data = encoded() else { return }
        let u = Shared.file
        saveTask = Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .milliseconds(200)); if Task.isCancelled { return }
            try? data.write(to: u, options: .atomic)
            await MainActor.run { self?.didSave?() }
        }
    }
    /// Straight to disk: widgets, intents and notification actions, which may be killed right after.
    func saveNow() {
        guard !demo else { return }
        stamp = Date().timeIntervalSince1970
        if let data = encoded() { try? data.write(to: Shared.file, options: .atomic) }
    }

    var active: [Habit] { habits.filter { !$0.archived } }

    // MARK: Days

    func paused(_ h: Habit, _ day: String) -> Bool { h.pauses.contains { day >= $0.from && day <= $0.to } }
    func done(_ h: Habit, _ day: String) -> Bool { log[day]?.contains(h.id) ?? false }
    func isFrozen(_ h: Habit, _ day: String) -> Bool { frozen[day]?.contains(h.id) ?? false }
    func isRepaired(_ h: Habit, _ day: String) -> Bool { repaired[day]?.contains(h.id) ?? false }
    /// Done, frozen or repaired: the chain holds.
    func covered(_ h: Habit, _ day: String) -> Bool { done(h, day) || isFrozen(h, day) || isRepaired(h, day) }
    func due(_ h: Habit, _ day: String) -> Bool {
        guard h.kind == .build, day >= h.start, !paused(h, day) else { return false }
        switch h.frequency {
        case .daily, .weekly: return true
        case .days: return h.days.contains(Day.dow(day))
        }
    }
    func count(_ h: Habit, _ day: String) -> Int { counts[day]?[h.id.uuidString] ?? (done(h, day) ? h.target : 0) }
    func progress(_ h: Habit, _ day: String) -> Double { h.target <= 1 ? (done(h, day) ? 1 : 0) : min(1, Double(count(h, day)) / Double(h.target)) }

    func setDone(_ h: Habit, _ day: String, _ on: Bool) {
        var l = log[day] ?? []
        if on { if !l.contains(h.id) { l.append(h.id) } } else { l.removeAll { $0 == h.id } }
        log[day] = l.isEmpty ? nil : l
    }
    func setCount(_ h: Habit, _ day: String, _ n: Int) {
        var c = counts[day] ?? [:]
        c[h.id.uuidString] = max(0, n)
        counts[day] = c
        setDone(h, day, n >= h.target)
    }
    /// One tap: a plain habit flips; an amount habit adds a step, and a tap on a finished one starts it over.
    func tap(_ h: Habit, _ day: String) {
        if h.target <= 1 { setDone(h, day, !done(h, day)) }
        else if done(h, day) { setCount(h, day, 0) }
        else { setCount(h, day, min(h.target, count(h, day) + h.step)) }
    }
    func toggle(_ h: Habit, _ day: String) { tap(h, day); save() }
    func markDone(_ h: Habit, _ day: String) {
        if h.target > 1 { setCount(h, day, max(count(h, day), h.target)) } else { setDone(h, day, true) }
    }

    func weekHits(_ h: Habit, _ anyDay: String) -> Int {
        let ws = Day.weekStart(anyDay); return (0..<7).filter { covered(h, Day.add(ws, $0)) }.count
    }
    func satisfiedToday(_ h: Habit) -> Bool { h.frequency == .weekly ? (weekHits(h, Day.today) >= h.perWeek || done(h, Day.today)) : done(h, Day.today) }

    // MARK: Chains

    func streak(_ h: Habit) -> Int {
        if h.kind == .quit { return cleanDays(h) }
        if h.frequency == .weekly {
            var s = 0; var ws = Day.weekStart(Day.today)
            if weekHits(h, ws) >= h.perWeek { s += 1 }
            ws = Day.add(ws, -7)
            while ws >= Day.weekStart(h.start) && weekHits(h, ws) >= h.perWeek { s += 1; ws = Day.add(ws, -7) }
            return s
        }
        var d = Day.today
        if !covered(h, d) { d = Day.add(d, -1) }
        return run(h, from: d)
    }
    /// The chain that ends on `from`, walking back. A freeze holds the chain without adding to it.
    func run(_ h: Habit, from: String) -> Int {
        var s = 0; var d = from
        while d >= h.start {
            if due(h, d) {
                if done(h, d) || isRepaired(h, d) { s += 1 } else if !isFrozen(h, d) { break }
            }
            d = Day.add(d, -1)
        }
        return s
    }
    func best(_ h: Habit) -> Int {
        if h.kind == .quit { return bestClean(h) }
        var b = 0, s = 0; var d = h.start
        while d <= Day.today {
            if due(h, d) {
                if done(h, d) || isRepaired(h, d) { s += 1; b = max(b, s) } else if !isFrozen(h, d) && d < Day.today { s = 0 }
            }
            d = Day.add(d, 1)
        }
        return b
    }
    func rate(_ h: Habit, days: Int) -> Double {
        if h.kind == .quit {
            let span = min(days, max(1, Day.diff(h.start, Day.today) + 1))
            let slips = (0..<span).filter { done(h, Day.add(Day.today, -$0)) }.count
            return Double(span - slips) / Double(span)
        }
        if h.frequency == .weekly {
            var w = 0, ok = 0
            for i in 0..<max(1, days / 7) { let ws = Day.add(Day.weekStart(Day.today), -7 * i); if ws < Day.weekStart(h.start) { break }; w += 1; if weekHits(h, ws) >= h.perWeek { ok += 1 } }
            return w > 0 ? Double(ok) / Double(w) : 0
        }
        var d = 0, hit = 0
        for i in 0..<days {
            let k = Day.add(Day.today, -i)
            guard due(h, k), !isFrozen(h, k) else { continue }
            if k == Day.today && !done(h, k) { continue }
            d += 1; if done(h, k) || isRepaired(h, k) { hit += 1 }
        }
        return d > 0 ? Double(hit) / Double(d) : 0
    }
    func total(_ h: Habit) -> Int { log.values.filter { $0.contains(h.id) }.count }
    var totalDone: Int {
        let builds = Set(habits.filter { $0.kind == .build }.map(\.id))
        return log.values.reduce(0) { $0 + $1.filter { builds.contains($0) }.count }
    }

    // MARK: Quitting

    func lastSlip(_ h: Habit) -> String? { log.keys.filter { $0 >= h.start && $0 <= Day.today && done(h, $0) }.max() }
    func cleanDays(_ h: Habit) -> Int {
        guard Day.today >= h.start else { return 0 }
        if let s = lastSlip(h) { return Day.diff(s, Day.today) }
        return Day.diff(h.start, Day.today)
    }
    func bestClean(_ h: Habit) -> Int {
        let slips = log.keys.filter { $0 >= h.start && done(h, $0) }.sorted()
        var b = 0; var from = h.start
        for s in slips { b = max(b, Day.diff(from, s)); from = s }
        return max(b, cleanDays(h))
    }

    // MARK: Freezes and repairs

    func freezesUsed(_ month: String = Day.month(Day.today)) -> Int { freezeSpend[month] ?? 0 }
    func freezesLeft(pro: Bool) -> Int { max(0, (pro ? 3 : 1) - freezesUsed()) }
    func freeze(_ h: Habit, _ day: String) {
        frozen[day, default: []].append(h.id)
        freezeSpend[Day.month(Day.today), default: 0] += 1
        save()
    }
    func repair(_ h: Habit, _ day: String) {
        guard repairCredits > 0 else { return }
        repaired[day, default: []].append(h.id)
        repairCredits -= 1
        save()
    }
    /// Chains that broke on their most recent due day, within the last two days, and were worth keeping.
    func rescues() -> [Rescue] {
        var out: [Rescue] = []
        for h in active where h.kind == .build && h.frequency != .weekly {
            var d = Day.add(Day.today, -1); var guardDays = 0
            while guardDays < 8 && d >= h.start && !due(h, d) { d = Day.add(d, -1); guardDays += 1 }
            guard d >= h.start, due(h, d), !covered(h, d), Day.diff(d, Day.today) <= 2 else { continue }
            let lost = run(h, from: Day.add(d, -1))
            if lost >= 2 { out.append(Rescue(habit: h, day: d, lost: lost)) }
        }
        return out
    }

    // MARK: Whole-day numbers

    func perfectDays(_ days: Int) -> Int {
        var n = 0
        for i in 0..<days {
            let k = Day.add(Day.today, -i); let dueH = active.filter { due($0, k) && $0.frequency != .weekly }
            if !dueH.isEmpty && dueH.allSatisfy({ covered($0, k) }) { n += 1 }
        }
        return n
    }
    func weekdayRates() -> [Double] {
        var due_ = Array(repeating: 0, count: 7), hit = Array(repeating: 0, count: 7)
        for i in 1..<91 { let k = Day.add(Day.today, -i); let w = Day.dow(k); for h in active where h.frequency != .weekly && due(h, k) { due_[w] += 1; if done(h, k) { hit[w] += 1 } } }
        return (0..<7).map { due_[$0] > 0 ? Double(hit[$0]) / Double(due_[$0]) : 0 }
    }
    /// Today's checklist: build habits due today, in their saved order.
    var dueToday: [Habit] { active.filter { due($0, Day.today) } }
    var doneToday: Int { dueToday.filter { satisfiedToday($0) }.count }
    func note(_ h: Habit, _ day: String) -> String { notes[day]?[h.id.uuidString] ?? "" }
    func setNote(_ h: Habit, _ day: String, _ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var n = notes[day] ?? [:]
        n[h.id.uuidString] = t.isEmpty ? nil : t
        notes[day] = n.isEmpty ? nil : n
        save()
    }
    func recentNotes(_ h: Habit, limit: Int = 12) -> [(String, String)] {
        notes.keys.sorted(by: >).compactMap { k in notes[k]?[h.id.uuidString].map { (k, $0) } }.prefix(limit).map { $0 }
    }

    func csv() -> String {
        var rows = ["date,habit,done,amount,frozen,repaired,note"]
        let all = Set(log.keys).union(counts.keys).union(frozen.keys).union(repaired.keys).union(notes.keys).sorted()
        for k in all {
            for h in habits {
                let dn = done(h, k), c = counts[k]?[h.id.uuidString], fz = isFrozen(h, k), rp = isRepaired(h, k), nt = note(h, k)
                guard dn || c != nil || fz || rp || !nt.isEmpty else { continue }
                let esc = { (s: String) in "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
                rows.append([k, esc(h.name), dn ? (h.kind == .quit ? "slip" : "1") : "0", c.map(String.init) ?? "", fz ? "1" : "", rp ? "1" : "", esc(nt)].joined(separator: ","))
            }
        }
        return rows.joined(separator: "\n")
    }
}
