import AppIntents
import SwiftUI
import UserNotifications
import WidgetKit

/// Tick a habit off from a widget, without opening the app.
struct ToggleHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Check off a habit"
    static var isDiscoverable = false
    @Parameter(title: "Habit") var habitID: String
    init() {}
    init(id: UUID) { habitID = id.uuidString }
    func perform() async throws -> some IntentResult {
        let s = Store(demo: false)
        if let h = s.habits.first(where: { $0.id.uuidString == habitID }) {
            s.tap(h, Day.today)
            s.saveNow()
            if s.done(h, Day.today) {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["chain-\(h.id)-\(Day.today)"])
            }
        }
        return .result()
    }
}

struct WidgetRow: Identifiable, Hashable {
    let id: UUID
    let name: String
    let emoji: String
    let done: Bool
    let progress: Double
    let streak: Int
    let detail: String
}

/// Everything a widget draws, read from the shared file once per timeline.
struct Snapshot {
    var rows: [WidgetRow]
    var done: Int
    var due: Int
    var unlocked: Bool
    /// The last 12 weeks, every habit together: 0 nothing, 1 a perfect day, -1 nothing was due.
    var quilt: [Double]
    var topStreak: Int
    var topName: String

    var fraction: Double { due == 0 ? 0 : Double(done) / Double(due) }
    var next: WidgetRow? { rows.first { !$0.done } }

    static func make(_ s: Store, unlocked: Bool) -> Snapshot {
        let t = Day.today
        let due = s.dueToday
        let rows = due.map { h -> WidgetRow in
            let detail = h.target > 1 ? "\(s.count(h, t).formatted())/\(h.target.formatted()) \(h.unit)" : h.frequency == .weekly ? "\(s.weekHits(h, t))/\(h.perWeek) this week" : "\(s.streak(h)) day chain"
            return WidgetRow(id: h.id, name: h.name, emoji: h.emoji, done: s.satisfiedToday(h), progress: h.frequency == .weekly && s.satisfiedToday(h) ? 1 : s.progress(h, t), streak: s.streak(h), detail: detail)
        }.sorted { !$0.done && $1.done }
        let start = Day.add(Day.weekStart(t), -11 * 7)
        var quilt: [Double] = []
        var d = start
        while d <= Day.add(Day.weekStart(t), 6) {
            let hs = s.active.filter { s.due($0, d) && $0.frequency != .weekly }
            quilt.append(d > t || hs.isEmpty ? -1 : Double(hs.filter { s.covered($0, d) }.count) / Double(hs.count))
            d = Day.add(d, 1)
        }
        let top = s.active.filter { $0.kind == .build }.max { s.streak($0) < s.streak($1) }
        return Snapshot(rows: rows, done: rows.filter(\.done).count, due: rows.count, unlocked: unlocked, quilt: quilt,
                        topStreak: top.map { s.streak($0) } ?? 0, topName: top.map { $0.emoji + " " + $0.name } ?? "")
    }

    static func load() -> Snapshot {
        Palette.reload()
        return make(Store(demo: false), unlocked: Shared.unlocked)
    }
    static var placeholder: Snapshot { make(Store(demo: true), unlocked: true) }
}

// MARK: Views

/// The check square, shared by every widget.
struct WidgetCheck: View {
    let row: WidgetRow
    var size: CGFloat = 30
    var body: some View {
        Button(intent: ToggleHabitIntent(id: row.id)) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(row.done ? Ink.lime : Ink.card2)
                    .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(row.done ? Ink.lime : Ink.line2, lineWidth: 1.5))
                if !row.done && row.progress > 0 {
                    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).trim(from: 0, to: row.progress)
                        .stroke(Ink.lime, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
                if row.done { Image(systemName: "checkmark").font(.system(size: size * 0.45, weight: .black)).foregroundStyle(Ink.bg) }
                else { Text(row.emoji).font(.system(size: size * 0.5)) }
            }.frame(width: size, height: size)
        }.buttonStyle(.plain)
    }
}

/// Small: the next thing to do, and one tap to do it.
struct NextUpView: View {
    let snap: Snapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Ring(fraction: snap.fraction, size: 38, width: 5, label: false)
                    .overlay(Text("\(snap.done)").font(.num(13)).foregroundStyle(Ink.white))
                Spacer()
                Text("of \(snap.due)").font(.ui(11, .heavy)).foregroundStyle(Ink.dim)
            }
            Spacer(minLength: 6)
            if let n = snap.next {
                Text("NEXT UP").font(.ui(9, .black)).tracking(1.5).foregroundStyle(Ink.dim)
                Text(n.name).font(.ui(15, .heavy)).foregroundStyle(Ink.white).lineLimit(2).minimumScaleFactor(0.8)
                Spacer(minLength: 6)
                HStack {
                    WidgetCheck(row: n, size: 36)
                    Text(n.detail).font(.ui(10, .heavy)).foregroundStyle(Ink.grey).lineLimit(2)
                }
            } else {
                Text(snap.due == 0 ? "Nothing due." : "Clean sweep.").font(.ui(17, .heavy)).foregroundStyle(Ink.lime)
                Text(snap.topStreak > 0 ? "\(snap.topStreak) day chain going." : "Add a habit in Chain.").font(.ui(11, .semibold)).foregroundStyle(Ink.grey)
                Spacer(minLength: 0)
            }
        }
    }
}

/// Medium and large: the day's list, each row its own button.
struct TodayListView: View {
    let snap: Snapshot
    let limit: Int
    var large = false
    var body: some View {
        if large {
            VStack(alignment: .leading, spacing: 10) {
                header
                list
                Spacer(minLength: 0)
                MiniQuilt(values: snap.quilt).frame(height: 62)
            }
        } else {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Ring(fraction: snap.fraction, size: 56, width: 7, label: false)
                        .overlay(Text("\(snap.done)/\(snap.due)").font(.num(13)).foregroundStyle(Ink.white))
                    Spacer(minLength: 0)
                    Text(snap.done == snap.due && snap.due > 0 ? "Clean\nsweep." : "Keep the\nchain.").font(.ui(12, .heavy)).foregroundStyle(snap.done == snap.due && snap.due > 0 ? Ink.lime : Ink.grey)
                }.frame(width: 64, alignment: .leading)
                list
            }
        }
    }
    private var header: some View {
        HStack {
            Ring(fraction: snap.fraction, size: 40, width: 6, label: false)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(snap.done) of \(snap.due) done").font(.ui(16, .heavy)).foregroundStyle(Ink.white)
                Text(snap.topStreak > 0 ? "Longest going: \(snap.topName), \(snap.topStreak)" : "Keep the chain.").font(.ui(11, .semibold)).foregroundStyle(Ink.grey).lineLimit(1)
            }
            Spacer()
        }
    }
    private var list: some View {
        VStack(alignment: .leading, spacing: large ? 7 : 5) {
            ForEach(snap.rows.prefix(limit)) { r in
                HStack(spacing: 8) {
                    WidgetCheck(row: r, size: large ? 30 : 26)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(r.name).font(.ui(large ? 13 : 12, .heavy)).foregroundStyle(r.done ? Ink.dim : Ink.white).lineLimit(1).strikethrough(r.done, color: Ink.dim)
                        if large { Text(r.detail).font(.ui(10, .semibold)).foregroundStyle(Ink.dim).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                    if r.streak > 0 { Text("\(r.streak)").font(.num(12)).foregroundStyle(r.done ? Ink.lime : Ink.grey) }
                }
            }
            if snap.rows.count > limit { Text("+\(snap.rows.count - limit) more").font(.ui(10, .heavy)).foregroundStyle(Ink.dim) }
            if snap.rows.isEmpty { Text("Nothing due today.").font(.ui(13, .heavy)).foregroundStyle(Ink.grey) }
        }
    }
}

/// Twelve weeks of every habit together, columns of weeks.
struct MiniQuilt: View {
    let values: [Double]
    var body: some View {
        Canvas { ctx, size in
            let cols = max(1, (values.count + 6) / 7)
            let cell = min(size.width / CGFloat(cols), size.height / 7)
            let s = cell - 2
            for (i, v) in values.enumerated() {
                let rect = CGRect(x: CGFloat(i / 7) * cell, y: CGFloat(i % 7) * cell, width: s, height: s)
                let c: Color = v < 0 ? Ink.line : v >= 1 ? Ink.lime : v > 0 ? Ink.lime.opacity(0.2 + 0.5 * v) : Ink.hole
                ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(c))
            }
        }
    }
}

struct LockCircularView: View {
    let snap: Snapshot
    var body: some View {
        Gauge(value: snap.fraction) { Image(systemName: "link") } currentValueLabel: { Text("\(snap.done)") }
            .gaugeStyle(.accessoryCircularCapacity)
    }
}

struct LockRectView: View {
    let snap: Snapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(snap.done) of \(snap.due) done").font(.ui(15, .heavy))
            if let n = snap.next { Text("Next: \(n.emoji) \(n.name)").font(.ui(12, .semibold)).lineLimit(1) }
            else { Text(snap.topStreak > 0 ? "Clean sweep · \(snap.topStreak) day chain" : "Clean sweep").font(.ui(12, .semibold)) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What a locked widget shows on the free plan.
struct LockedWidgetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "lock.fill").font(.system(size: 16, weight: .black)).foregroundStyle(Ink.lime)
            Text("Chain Unlimited").font(.ui(15, .heavy)).foregroundStyle(Ink.white)
            Text("This widget comes with the one-time unlock. The Next Up widget is free.").font(.ui(11, .semibold)).foregroundStyle(Ink.grey)
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
