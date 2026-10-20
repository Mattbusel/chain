import StoreKit
import SwiftUI
import TipKit
import UIKit

// MARK: Milestones

/// The streak lengths worth stopping for.
enum Milestones {
    static let all = [7, 14, 21, 30, 50, 66, 100, 150, 200, 250, 300, 365, 500, 730, 1000]
    /// The milestone a habit just reached, once per habit and length.
    static func check(_ s: Store, _ h: Habit) -> Int? {
        guard h.kind == .build, h.frequency != .weekly else { return nil }
        let n = s.streak(h)
        guard all.contains(n) else { return nil }
        let key = "\(h.id)-\(n)"
        var seen = UserDefaults.standard.stringArray(forKey: "chain.milestones") ?? []
        guard !seen.contains(key) else { return nil }
        seen.append(key)
        UserDefaults.standard.set(Array(seen.suffix(500)), forKey: "chain.milestones")
        return n
    }
    static func next(after n: Int) -> Int? { all.first { $0 > n } }
}

/// What the big moment sheet shows: a streak milestone or a challenge won.
enum Moment: Identifiable {
    case streak(Habit, Int)
    case won(ChallengeRun)
    var id: String {
        switch self {
        case .streak(let h, let n): return "s\(h.id)\(n)"
        case .won(let r): return "w" + r.id
        }
    }
}

/// Asks for a rating at most once per version, and only right after something went well.
enum ReviewAsk {
    static var asked: Bool {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return UserDefaults.standard.string(forKey: "chain.reviewAsked") == v
    }
    @MainActor static func maybe(_ request: RequestReviewAction) {
        guard !asked, !ProcessInfo.processInfo.arguments.contains("-shot") else { return }
        UserDefaults.standard.set(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "", forKey: "chain.reviewAsked")
        request()
    }
}

struct MomentSheet: View {
    @Environment(Store.self) private var store
    @Environment(Purchases.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    let moment: Moment
    @State private var card: UIImage? = nil
    @State private var pop = false
    private var streakHabit: Habit? { if case .streak(let h, _) = moment { return h }; return nil }
    var body: some View {
        ZStack(alignment: .topTrailing) {
            CharcoalBackground()
            VStack(alignment: .leading, spacing: 18) {
                Spacer(minLength: 30)
                switch moment {
                case .streak(let h, let n):
                    Image(systemName: "flame.fill").font(.system(size: 46, weight: .black)).foregroundStyle(Ink.lime)
                        .symbolEffect(.bounce, value: pop)
                    Eyebrow("Milestone")
                    (Text("\(n)").foregroundStyle(Ink.lime) + Text(" days.").foregroundStyle(Ink.white)).font(.system(size: 64, weight: .black, design: .rounded))
                    Text("\(h.emoji) \(h.name), \(n) days without a gap. " + (Milestones.next(after: n).map { "Next stop: \($0)." } ?? "Legendary."))
                        .font(.ui(16, .medium)).foregroundStyle(Ink.grey).fixedSize(horizontal: false, vertical: true)
                case .won(let r):
                    let c = Challenges.byID(r.challenge)
                    Image(systemName: "trophy.fill").font(.system(size: 46, weight: .black)).foregroundStyle(Ink.amber)
                        .symbolEffect(.bounce, value: pop)
                    Eyebrow("Challenge won")
                    Text((c?.emoji ?? "🏁") + " " + (c?.title ?? "Challenge")).font(.big(34)).foregroundStyle(Ink.white)
                    Text("\(store.progress(r)) days of \(c?.habit.lowercased() ?? "it"). The badge is yours, and the chain keeps going.")
                        .font(.ui(16, .medium)).foregroundStyle(Ink.grey).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if let card, let h = streakHabit {
                    ShareLink(item: Image(uiImage: card), preview: SharePreview("\(h.name) on Chain", image: Image(uiImage: card))) {
                        HStack(spacing: 8) { Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .black)); Text("Share it").font(.ui(15, .heavy)) }
                            .foregroundStyle(Ink.white).frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Ink.card2))
                    }
                }
                LimeButton(title: "Keep going", icon: "arrow.right") { dismiss() }
            }
            .padding(24)
            CloseButton { dismiss() }.padding(.trailing, 18).padding(.top, 16)
        }
        .task {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            pop.toggle()
            if let h = streakHabit { card = ShareCard.render(store: store, habit: h, watermark: !purchases.unlocked || ShareCard.watermarkOn) }
        }
    }
}

// MARK: Challenges

/// The month's challenge, at the top of Today.
struct ChallengeCard: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    var body: some View {
        let c = Challenges.featured()
        let r = store.openRun(c)
        Button { router.challenges = true } label: {
            HStack(spacing: 12) {
                Text(c.emoji).font(.system(size: 26)).frame(width: 50, height: 50)
                    .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Ink.lime.opacity(0.14)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(Day.date(Day.today).formatted(.dateTime.month(.wide)).uppercased() + " CHALLENGE").font(.ui(10, .black)).tracking(1.4).foregroundStyle(Ink.lime)
                    Text(c.title).font(.ui(16, .heavy)).foregroundStyle(Ink.white).lineLimit(1)
                    if let r {
                        ChallengeBar(done: store.progress(r), goal: r.goal)
                        Text(r.won ? "Won. \(store.progress(r)) days so far." : "\(store.progress(r)) of \(r.goal) days · \(store.daysLeft(r)) left")
                            .font(.ui(11, .heavy)).foregroundStyle(Ink.dim)
                    } else {
                        Text(c.habit).font(.ui(12, .medium)).foregroundStyle(Ink.grey).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if r == nil {
                    Text("Join").font(.ui(13, .heavy)).foregroundStyle(Ink.bg).padding(.horizontal, 14).padding(.vertical, 8).background(Capsule().fill(Ink.lime))
                } else if r?.won == true {
                    Image(systemName: "trophy.fill").font(.system(size: 20, weight: .black)).foregroundStyle(Ink.amber)
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .black)).foregroundStyle(Ink.lime)
                }
            }.tile(padding: 12)
        }
        .buttonStyle(Press())
        .accessibilityLabel(r == nil ? "\(c.title) challenge. Join." : "\(c.title) challenge, \(store.progress(r!)) of \(r!.goal) days")
    }
}

struct ChallengeBar: View {
    let done: Int
    let goal: Int
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.hole)
                Capsule().fill(Ink.lime).frame(width: max(6, g.size.width * min(1, Double(done) / Double(max(1, goal)))))
            }
        }.frame(height: 6)
    }
}

struct ChallengesSheet: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(Purchases.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @State private var paywall: Locked? = nil
    var body: some View {
        let featured = Challenges.featured()
        ZStack(alignment: .topTrailing) {
            CharcoalBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow("Challenges")
                        Text("One habit,\none month.").font(.big(32)).foregroundStyle(Ink.white)
                        Text("Hit four days in five and the badge is yours. Every month brings a new headline challenge.").font(.ui(14, .medium)).foregroundStyle(Ink.grey)
                    }.padding(.top, 50)
                    featuredCard(featured)
                    let others = store.liveRuns.filter { $0.challenge != featured.id }
                    if !others.isEmpty {
                        Eyebrow("Running")
                        ForEach(others) { r in runRow(r) }
                    }
                    HStack { Eyebrow("Library"); Spacer(); if !purchases.plus { PlusTag() } }
                    ForEach(Challenges.library.filter { $0.id != featured.id }) { c in libraryRow(c) }
                    if !store.wonRuns.isEmpty {
                        Eyebrow("Badges")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                            ForEach(store.wonRuns) { r in badge(r) }
                        }
                    }
                }.padding(.horizontal, 18).padding(.bottom, 30)
            }
            CloseButton { dismiss() }.padding(.trailing, 18).padding(.top, 16)
        }
        .sheet(item: $paywall) { r in Paywall(reason: r).presentationBackground(Ink.bg).presentationDetents([.large]) }
    }

    func featuredCard(_ c: Challenge) -> some View {
        let r = store.openRun(c)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(c.emoji).font(.system(size: 34)).frame(width: 62, height: 62).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Ink.lime.opacity(0.14)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(Day.date(Day.today).formatted(.dateTime.month(.wide)).uppercased() + " · FREE FOR EVERYONE").font(.ui(10, .black)).tracking(1.2).foregroundStyle(Ink.lime)
                    Text(c.title).font(.big(24)).foregroundStyle(Ink.white)
                    Text(c.habit).font(.ui(13, .heavy)).foregroundStyle(Ink.grey)
                }
            }
            Text(c.blurb).font(.ui(13, .medium)).foregroundStyle(Ink.grey).fixedSize(horizontal: false, vertical: true)
            if let r {
                ChallengeBar(done: store.progress(r), goal: r.goal)
                Text(r.won ? "Won! \(store.progress(r)) days and counting." : "\(store.progress(r)) of \(r.goal) days · \(store.daysLeft(r)) days left").font(.ui(12, .heavy)).foregroundStyle(r.won ? Ink.amber : Ink.dim)
            } else {
                LimeButton(title: "Join the challenge", icon: "flag.checkered") { store.join(c, featured: true); UINotificationFeedbackGenerator().notificationOccurred(.success) }
                Text("Adds \"\(c.habit)\" to Today until \(Day.date(Challenges.monthEnd(Day.today)).formatted(.dateTime.month(.abbreviated).day())). It doesn't count toward the free three.").font(.ui(11, .medium)).foregroundStyle(Ink.dim)
            }
        }.tile(padding: 16)
    }

    func runRow(_ r: ChallengeRun) -> some View {
        let c = Challenges.byID(r.challenge)
        return VStack(alignment: .leading, spacing: 8) {
            HStack { Text((c?.emoji ?? "") + " " + (c?.title ?? "")).font(.ui(15, .heavy)).foregroundStyle(Ink.white); Spacer()
                Text("\(store.progress(r))/\(r.goal)").font(.num(13)).foregroundStyle(r.won ? Ink.amber : Ink.grey) }
            ChallengeBar(done: store.progress(r), goal: r.goal)
        }.tile(padding: 14)
    }

    func libraryRow(_ c: Challenge) -> some View {
        let r = store.openRun(c)
        return HStack(spacing: 12) {
            Text(c.emoji).font(.system(size: 22)).frame(width: 42, height: 42).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Ink.card2))
            VStack(alignment: .leading, spacing: 2) {
                Text(c.title).font(.ui(15, .heavy)).foregroundStyle(Ink.white)
                Text(c.habit).font(.ui(12, .medium)).foregroundStyle(Ink.grey).lineLimit(1)
            }
            Spacer(minLength: 4)
            if r != nil {
                Text("Running").font(.ui(12, .heavy)).foregroundStyle(Ink.lime)
            } else if purchases.plus {
                Button { store.join(c, featured: false); UINotificationFeedbackGenerator().notificationOccurred(.success) } label: {
                    Text("Start").font(.ui(13, .heavy)).foregroundStyle(Ink.bg).padding(.horizontal, 14).padding(.vertical, 7).background(Capsule().fill(Ink.lime))
                }.buttonStyle(Press())
            } else {
                Button { paywall = .challenges } label: {
                    Image(systemName: "lock.fill").font(.system(size: 13, weight: .black)).foregroundStyle(Ink.dim).frame(width: 34, height: 34).background(Circle().fill(Ink.card2))
                }.buttonStyle(Press()).accessibilityLabel("Unlock \(c.title) with Chain Plus")
            }
        }.tile(padding: 12)
    }

    func badge(_ r: ChallengeRun) -> some View {
        let c = Challenges.byID(r.challenge)
        return VStack(spacing: 6) {
            Text(c?.emoji ?? "🏁").font(.system(size: 30))
            Text(c?.title ?? "").font(.ui(11, .heavy)).foregroundStyle(Ink.white).multilineTextAlignment(.center).lineLimit(2)
            Text(Day.date(r.from).formatted(.dateTime.month(.abbreviated).year())).font(.ui(10, .medium)).foregroundStyle(Ink.dim)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Ink.amber.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Ink.amber.opacity(0.5)))
    }
}

// MARK: Insights

extension Store {
    /// Share of due days done between two days, inclusive; frozen days and today-not-yet-done are left out.
    func completion(from: String, to: String, of list: [Habit]? = nil) -> Double? {
        let hs = list ?? active.filter { $0.kind == .build && $0.frequency != .weekly }
        var due_ = 0, hit = 0; var d = from
        while d <= min(to, Day.today) {
            for h in hs where due(h, d) && !isFrozen(h, d) {
                if d == Day.today && !done(h, d) { continue }
                due_ += 1; if done(h, d) || isRepaired(h, d) { hit += 1 }
            }
            d = Day.add(d, 1)
        }
        return due_ > 0 ? Double(hit) / Double(due_) : nil
    }

    struct Pair { let a: Habit; let b: Habit; let with: Double; let without: Double }
    /// The two habits that go together most: on days A is done, B is done far more often.
    func bestPair() -> Pair? {
        let hs = active.filter { $0.kind == .build && $0.frequency != .weekly }
        var best: Pair? = nil
        for a in hs { for b in hs where a.id != b.id {
            var w = 0, wHit = 0, wo = 0, woHit = 0
            for i in 1...90 {
                let k = Day.add(Day.today, -i)
                guard due(a, k), due(b, k) else { continue }
                if done(a, k) { w += 1; if done(b, k) { wHit += 1 } } else { wo += 1; if done(b, k) { woHit += 1 } }
            }
            guard w >= 8, wo >= 4, w + wo >= 30 else { continue }
            let p1 = Double(wHit) / Double(w), p0 = Double(woHit) / Double(wo)
            if p1 - p0 >= 0.15, best.map({ p1 - p0 > $0.with - $0.without }) ?? true { best = Pair(a: a, b: b, with: p1, without: p0) }
        } }
        return best
    }

    /// 30-day completion by time of day.
    func partRates() -> [(Part, Double)] {
        Part.allCases.compactMap { p in
            let hs = active.filter { $0.kind == .build && $0.frequency != .weekly && $0.part == p }
            guard !hs.isEmpty, let r = completion(from: Day.add(Day.today, -29), to: Day.today, of: hs) else { return nil }
            return (p, r)
        }
    }

    /// Habits whose last 30 days moved most against the 30 before.
    func movers() -> [(Habit, Double)] {
        active.filter { $0.kind == .build && $0.frequency != .weekly }.compactMap { h -> (Habit, Double)? in
            guard let now = completion(from: Day.add(Day.today, -29), to: Day.today, of: [h]),
                  let before = completion(from: Day.add(Day.today, -59), to: Day.add(Day.today, -30), of: [h]) else { return nil }
            return (h, now - before)
        }.sorted { abs($0.1) > abs($1.1) }
    }
}

/// Chain Plus: the month in review, what goes together, and what's coming next.
struct InsightsSheet: View {
    @Environment(Store.self) private var store
    @Environment(Purchases.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @State private var paywall: Locked? = nil
    var body: some View {
        ZStack(alignment: .topTrailing) {
            CharcoalBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Eyebrow("Insights"); PlusTag() }
                        Text("What makes\nyour habits stick.").font(.big(30)).foregroundStyle(Ink.white)
                    }.padding(.top, 50)
                    if purchases.plus { content } else { locked }
                }.padding(.horizontal, 18).padding(.bottom, 30)
            }
            CloseButton { dismiss() }.padding(.trailing, 18).padding(.top, 16)
        }
        .sheet(item: $paywall) { r in Paywall(reason: r).presentationBackground(Ink.bg).presentationDetents([.large]) }
    }

    private var monthStart: String { String(Day.today.prefix(7)) + "-01" }
    private var lastMonthStart: String { String(Day.add(monthStart, -1).prefix(7)) + "-01" }

    @ViewBuilder private var content: some View {
        let now = store.completion(from: monthStart, to: Day.today)
        let before = store.completion(from: lastMonthStart, to: Day.add(monthStart, -1))
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("This month")
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(now.map { "\(Int(($0 * 100).rounded()))%" } ?? "–").font(.num(46)).foregroundStyle(Ink.lime)
                if let now, let before {
                    let delta = Int(((now - before) * 100).rounded())
                    Label("\(abs(delta)) \(abs(delta) == 1 ? "pt" : "pts") vs \(Day.date(lastMonthStart).formatted(.dateTime.month(.wide)))", systemImage: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.ui(13, .heavy)).foregroundStyle(delta >= 0 ? Ink.lime : Ink.red)
                }
            }
            Text("\(store.perfectDays(Day.diff(monthStart, Day.today) + 1)) perfect days so far, every habit done.").font(.ui(13, .medium)).foregroundStyle(Ink.grey)
        }.tile()
        if let p = store.bestPair() {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("Better together")
                Text("On days you \(p.a.emoji) \(p.a.name.lowercased()), you \(p.b.emoji) \(p.b.name.lowercased()) \(Int((p.with * 100).rounded()))% of the time. Otherwise, \(Int((p.without * 100).rounded()))%.")
                    .font(.ui(15, .heavy)).foregroundStyle(Ink.white).fixedSize(horizontal: false, vertical: true)
                Text("Stack them: do \(p.b.name.lowercased()) right after \(p.a.name.lowercased()).").font(.ui(12, .medium)).foregroundStyle(Ink.grey)
            }.tile()
        }
        let parts = store.partRates()
        if parts.count > 1 {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("Time of day, last 30")
                ForEach(parts, id: \.0) { p, r in
                    HStack(spacing: 10) {
                        Image(systemName: p.icon).font(.system(size: 13, weight: .black)).foregroundStyle(Ink.lime).frame(width: 22)
                        Text(p.title).font(.ui(13, .heavy)).foregroundStyle(Ink.white).frame(width: 84, alignment: .leading)
                        ChallengeBar(done: Int(r * 100), goal: 100)
                        Text("\(Int((r * 100).rounded()))%").font(.num(12, .bold)).foregroundStyle(Ink.grey).frame(width: 40, alignment: .trailing)
                    }
                }
            }.tile()
        }
        let moves = store.movers().prefix(4)
        if !moves.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("Moving, last 30 vs 30 before")
                ForEach(Array(moves), id: \.0.id) { h, d in
                    HStack {
                        Text(h.emoji + " " + h.name).font(.ui(13, .heavy)).foregroundStyle(Ink.white).lineLimit(1)
                        Spacer()
                        Label("\(abs(Int((d * 100).rounded()))) pts", systemImage: d >= 0 ? "arrow.up" : "arrow.down").font(.num(12, .bold)).foregroundStyle(d >= 0 ? Ink.lime : Ink.red)
                    }
                }
            }.tile()
        }
        let upcoming = store.active.filter { $0.kind == .build && $0.frequency != .weekly }
            .compactMap { h -> (Habit, Int, Int)? in let s = store.streak(h); guard s > 0, let n = Milestones.next(after: s) else { return nil }; return (h, s, n) }
            .sorted { ($0.2 - $0.1) < ($1.2 - $1.1) }.prefix(3)
        if !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("Next milestones")
                ForEach(Array(upcoming), id: \.0.id) { h, s, n in
                    HStack {
                        Text(h.emoji + " " + h.name).font(.ui(13, .heavy)).foregroundStyle(Ink.white).lineLimit(1)
                        Spacer()
                        Text("\(n) days on \(Day.date(Day.add(Day.today, n - s)).formatted(.dateTime.month(.abbreviated).day()))").font(.num(12, .bold)).foregroundStyle(Ink.lime)
                    }
                }
                Text("If you keep every day from here.").font(.ui(11, .medium)).foregroundStyle(Ink.dim)
            }.tile()
        }
    }

    private var locked: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(["This month against last, in points", "The habits that lift each other", "Your best time of day", "When each chain hits its next milestone"], id: \.self) { t in
                HStack(spacing: 10) {
                    Image(systemName: "sparkle").font(.system(size: 12, weight: .black)).foregroundStyle(Ink.lime)
                    Text(t).font(.ui(14, .heavy)).foregroundStyle(Ink.white)
                }
            }
            LimeButton(title: "See Insights with Plus", icon: "chart.xyaxis.line") { paywall = .insights }
        }.tile(padding: 18)
    }
}

/// The door to Insights from Stats.
struct InsightsEntry: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(Purchases.self) private var purchases
    var body: some View {
        Button { router.insights = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.xyaxis.line").font(.system(size: 15, weight: .black)).foregroundStyle(Ink.bg)
                    .frame(width: 36, height: 36).background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Ink.lime))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) { Text("Insights").font(.ui(15, .heavy)).foregroundStyle(Ink.white); PlusTag() }
                    Text(purchases.plus ? "Your month, what goes together, what's next." : "See what makes your habits stick.").font(.ui(12, .medium)).foregroundStyle(Ink.grey)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .black)).foregroundStyle(Ink.lime)
            }.tile(padding: 12)
        }.buttonStyle(Press())
    }
}

// MARK: Tips

struct HoldTip: Tip {
    var title: Text { Text("Hold a habit for more") }
    var message: Text? { Text("Notes, details, reset and edit are one long press away.") }
    var image: Image? { Image(systemName: "hand.tap.fill") }
}

struct WidgetTip: Tip {
    @Parameter static var sweeps: Int = 0
    var title: Text { Text("Tick it from your Home Screen") }
    var message: Text? { Text("Add the Next Up widget: one tap ticks the next habit without opening Chain. Or add Log Next Habit to Control Center.") }
    var image: Image? { Image(systemName: "rectangle.3.group.fill") }
    var rules: [Rule] { [#Rule(Self.$sweeps) { $0 >= 1 }] }
}
