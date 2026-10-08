import SwiftUI
import UIKit
import WidgetKit

// MARK: Habit detail

struct HabitDetail: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(Purchases.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    let habitID: UUID
    @State private var card: UIImage? = nil
    var body: some View {
        if let h = store.habits.first(where: { $0.id == habitID }) {
            ZStack(alignment: .topTrailing) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Text(h.emoji).font(.system(size: 34)).frame(width: 60, height: 60).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Ink.card))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(h.name).font(.big(26)).foregroundStyle(Ink.white).lineLimit(2)
                                Text(summary(h)).font(.ui(13, .medium)).foregroundStyle(Ink.grey)
                            }
                        }.padding(.top, 22).padding(.trailing, 44)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            if h.kind == .quit {
                                stat("\(store.cleanDays(h))", "days clean"); stat("\(store.bestClean(h))", "best run")
                                stat("\(Int((store.rate(h, days: 365) * 100).rounded()))%", "clean days, year"); stat("\(store.total(h))", "slips logged")
                            } else {
                                stat("\(store.streak(h))", h.frequency == .weekly ? "week chain" : "day chain"); stat("\(store.best(h))", "best chain")
                                stat("\(Int((store.rate(h, days: 30) * 100).rounded()))%", "last 30 days"); stat("\(store.total(h))", "times done")
                            }
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Eyebrow(purchases.unlocked ? "The last year" : "The last 26 weeks"); Spacer() }
                            Quilt(habit: h, locked: !purchases.unlocked, weeks: purchases.unlocked ? 52 : 26)
                        }.tile()
                        if h.isAmount { amounts(h) }
                        let notes = store.recentNotes(h)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Eyebrow("Notes")
                                Spacer()
                                Button { router.noting = h } label: { Label("Today", systemImage: "plus").font(.ui(12, .heavy)).foregroundStyle(Ink.lime) }.buttonStyle(.plain)
                            }
                            if notes.isEmpty { Text("Hold a habit on Today to jot how it went. Notes show up here.").font(.ui(12, .medium)).foregroundStyle(Ink.dim) }
                            ForEach(notes, id: \.0) { k, n in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(Day.date(k).formatted(.dateTime.month(.abbreviated).day())).font(.num(11, .bold)).foregroundStyle(Ink.dim).frame(width: 46, alignment: .leading)
                                    Text(n).font(.ui(13, .medium)).foregroundStyle(Ink.white)
                                }
                            }
                        }.tile()
                        HStack(spacing: 8) {
                            if let card {
                                ShareLink(item: Image(uiImage: card), preview: SharePreview("\(h.name) on Chain", image: Image(uiImage: card))) {
                                    HStack(spacing: 8) { Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .black)); Text("Share the chain").font(.ui(15, .heavy)) }
                                        .foregroundStyle(Ink.bg).frame(maxWidth: .infinity).padding(.vertical, 15)
                                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Ink.lime))
                                }
                            }
                            GreyButton(title: "Edit", icon: "pencil") { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { router.editing = h } }
                        }
                    }.padding(.horizontal, 16).padding(.bottom, 30)
                }
                CloseButton { dismiss() }.padding(.trailing, 16).padding(.top, 16)
            }
            .task { card = ShareCard.render(store: store, habit: h, watermark: !purchases.unlocked || ShareCard.watermarkOn) }
        }
    }
    func summary(_ h: Habit) -> String {
        if h.kind == .quit { return "Quitting since \(Day.date(h.start).formatted(.dateTime.month(.wide).day().year()))" }
        let f: String
        switch h.frequency {
        case .daily: f = "Every day"
        case .days: f = h.days.sorted().map { Day.names[$0] }.joined(separator: ", ")
        case .weekly: f = "\(h.perWeek)× a week"
        }
        return f + (h.isAmount ? " · \(h.target.formatted()) \(h.unit)" : "") + " · since \(Day.date(h.start).formatted(.dateTime.month(.abbreviated).day()))"
    }
    func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(v).font(.num(28)).foregroundStyle(Ink.lime); Text(l).font(.ui(11, .heavy)).foregroundStyle(Ink.dim) }.frame(maxWidth: .infinity, alignment: .leading).tile(padding: 14)
    }
    func amounts(_ h: Habit) -> some View {
        let days = (0..<14).map { Day.add(Day.today, $0 - 13) }
        let top = Double(max(h.target, days.map { store.count(h, $0) }.max() ?? 1))
        return VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Last 14 days, \(h.unit)")
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(days, id: \.self) { d in
                    let c = Double(store.count(h, d))
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 4).fill(c >= Double(h.target) ? Ink.lime : c > 0 ? Ink.lime2 : Ink.hole).frame(height: max(3, 80 * c / top))
                        Text(String(d.suffix(2))).font(.num(8, .bold)).foregroundStyle(Ink.dim)
                    }.frame(maxWidth: .infinity)
                }
            }.frame(height: 100, alignment: .bottom)
                .overlay(alignment: .top) {
                    Rectangle().fill(Ink.lime.opacity(0.4)).frame(height: 1).offset(y: 80 - 80 * Double(h.target) / top + (100 - 80 - 11))
                }
        }.tile()
    }
}

// MARK: Share card

enum ShareCard {
    static var watermarkOn: Bool {
        get { UserDefaults.standard.object(forKey: "chain.watermark") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "chain.watermark") }
    }
    @MainActor static func render(store: Store, habit: Habit, watermark: Bool) -> UIImage? {
        let r = ImageRenderer(content: ShareCardView(habit: habit, watermark: watermark).environment(store))
        r.scale = 3
        return r.uiImage
    }
}

struct ShareCardView: View {
    @Environment(Store.self) private var store
    let habit: Habit
    let watermark: Bool
    var body: some View {
        let n = store.streak(habit)
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(habit.emoji).font(.system(size: 30))
                Text(habit.name).font(.big(26)).foregroundStyle(Ink.white).lineLimit(1)
            }
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(n)").font(.system(size: 88, weight: .black, design: .rounded)).foregroundStyle(Ink.lime)
                Text(habit.kind == .quit ? "days clean" : habit.frequency == .weekly ? "week chain" : "day chain").font(.big(22)).foregroundStyle(Ink.white)
            }
            Quilt(habit: habit, weeks: 26, width: 340)
            HStack {
                Text("Best \(store.best(habit)) · \(Int((store.rate(habit, days: 365) * 100).rounded()))% of the year").font(.ui(13, .heavy)).foregroundStyle(Ink.grey)
                Spacer()
                if watermark { Text("CHAIN · habit tracker").font(.ui(11, .black)).tracking(1.5).foregroundStyle(Ink.dim) }
            }
        }
        .padding(24)
        .frame(width: 388)
        .background(ZStack { Ink.bg; RadialGradient(colors: [Ink.lime.opacity(0.16), .clear], center: .topTrailing, startRadius: 10, endRadius: 360) })
    }
}

// MARK: Rescue

/// A chain broke. Freeze it (free allowance), repair it (99 cents), or say it was done and just not logged.
struct RescueSheet: View {
    @Environment(Store.self) private var store
    @Environment(Purchases.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    let rescue: Rescue
    @State private var saved = false
    var body: some View {
        let left = store.freezesLeft(pro: purchases.unlocked)
        let weekday = Day.date(rescue.day).formatted(.dateTime.weekday(.wide))
        ZStack(alignment: .topTrailing) {
            CharcoalBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    brokenChain.padding(.top, 50)
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(saved ? "Saved" : "Chain broken")
                        Text(saved ? "The chain holds.\n\(rescue.lost + 1) days and counting." : "\(rescue.habit.emoji) \(rescue.lost) days of \(rescue.habit.name),\nbroken on \(weekday).")
                            .font(.big(28)).foregroundStyle(Ink.white).fixedSize(horizontal: false, vertical: true)
                        if !saved { Text("One missed day doesn't have to cost the whole chain.").font(.ui(14, .medium)).foregroundStyle(Ink.grey) }
                    }
                    if saved {
                        LimeButton(title: "Keep going") { dismiss() }
                    } else {
                        if left > 0 {
                            option(icon: "snowflake", tint: Ink.ice, title: "Use a freeze", detail: "\(left) left this month. The day is skipped and the chain holds.", price: "Free") {
                                store.freeze(rescue.habit, rescue.day); win()
                            }
                        }
                        option(icon: "bandage.fill", tint: Ink.patch, title: store.repairCredits > 0 ? "Use a Streak Repair" : "Streak Repair",
                               detail: store.repairCredits > 0 ? "You have \(store.repairCredits). It patches the day in gold, and the day counts." : "Patches the missed day in gold. The day counts and the chain carries on.",
                               price: store.repairCredits > 0 ? "Use" : purchases.price(Purchases.repairID)) {
                            Task {
                                if store.repairCredits == 0 { guard await purchases.buy(Purchases.repairID) else { return } }
                                store.repair(rescue.habit, rescue.day); win()
                            }
                        }
                        Button { store.markDone(rescue.habit, rescue.day); store.save(); win() } label: {
                            Text("I did it on \(weekday), I just forgot to log it").font(.ui(13, .heavy)).foregroundStyle(Ink.grey).underline().frame(maxWidth: .infinity)
                        }.buttonStyle(.plain).padding(.top, 2)
                        Button { dismiss() } label: {
                            Text("Let it go and start again").font(.ui(13, .heavy)).foregroundStyle(Ink.dim).frame(maxWidth: .infinity)
                        }.buttonStyle(.plain)
                        if let m = purchases.message { Text(m).font(.ui(12, .medium)).foregroundStyle(Ink.amber).frame(maxWidth: .infinity) }
                    }
                }.padding(.horizontal, 22).padding(.bottom, 30)
            }
            CloseButton { dismiss() }.padding(.trailing, 18).padding(.top, 16)
        }
    }
    func win() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(duration: 0.5)) { saved = true }
    }
    private var brokenChain: some View {
        HStack(spacing: 5) {
            ForEach(0..<12, id: \.self) { i in
                let gap = i == 9
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(gap ? (saved ? Ink.patch : Ink.hole) : Ink.lime.opacity(i > 9 ? 0.35 : 1))
                    .frame(height: 26)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(gap && !saved ? Ink.red.opacity(0.8) : .clear, style: StrokeStyle(lineWidth: 2, dash: [4, 3])))
                    .scaleEffect(gap && saved ? 1.15 : 1)
            }
        }
    }
    private func option(icon: String, tint: Color, title: String, detail: String, price: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 17, weight: .black)).foregroundStyle(Ink.bg)
                    .frame(width: 42, height: 42).background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(tint))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.ui(16, .heavy)).foregroundStyle(Ink.white)
                    Text(detail).font(.ui(12, .medium)).foregroundStyle(Ink.grey).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 6)
                Text(price).font(.ui(14, .heavy)).foregroundStyle(Ink.bg).padding(.horizontal, 12).padding(.vertical, 8).background(Capsule().fill(tint))
            }.tile(padding: 14)
        }.buttonStyle(Press()).disabled(purchases.busy != nil)
    }
}

// MARK: Note

struct NoteSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let habit: Habit
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(habit.emoji) How did it go?").font(.big(22)).foregroundStyle(Ink.white).padding(.top, 22)
            TextField("A line for future you", text: $text, axis: .vertical).lineLimit(3...5).font(.ui(16, .semibold)).foregroundStyle(Ink.white)
                .padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Ink.card))
            LimeButton(title: "Save note") { store.setNote(habit, Day.today, text); dismiss() }
        }
        .padding(18)
        .onAppear { text = store.note(habit, Day.today) }
    }
}

// MARK: Celebration

/// The burst when the last habit of the day is ticked. Stitch is free; the pack adds Fireworks and Confetti.
struct Celebration: View {
    enum Style: String, CaseIterable { case stitch, fireworks, confetti
        var title: String { rawValue.capitalized }
        static var saved: Style {
            Style(rawValue: UserDefaults.standard.string(forKey: "chain.celebration") ?? "fireworks") ?? .fireworks
        }
    }
    let trigger: Int
    let style: Style
    @State private var start: Date? = nil
    var body: some View {
        TimelineView(.animation(paused: start == nil)) { tl in
            Canvas { ctx, size in
                guard let start else { return }
                let t = tl.date.timeIntervalSince(start)
                guard t < 2.4 else { return }
                Celebration.draw(style, t: t, ctx: &ctx, size: size)
            }
        }
        .onChange(of: trigger) { _, _ in
            start = .now
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { start = nil }
        }
        .onAppear { if trigger > 0 { start = .now; DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { start = nil } } }
    }

    static func draw(_ style: Style, t: Double, ctx: inout GraphicsContext, size: CGSize) {
        var seed: UInt64 = 42
        func r() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double((seed >> 33) % 10_000) / 10_000 }
        let fade = max(0, 1 - t / 2.4)
        let colours: [Color] = [Ink.lime, Ink.lime2, Ink.white, Ink.amber, Ink.ice]
        switch style {
        case .stitch:
            // Squares fly up from the bottom like a quilt coming apart and settling.
            for i in 0..<60 {
                let x0 = r() * size.width, vx = (r() - 0.5) * 140, vy = -(380 + r() * 520)
                let x = x0 + vx * t, y = size.height + vy * t + 520 * t * t
                let s = 8 + r() * 10
                var c = ctx; c.opacity = fade
                c.translateBy(x: x, y: y); c.rotate(by: .radians(t * (r() * 6 - 3)))
                c.fill(Path(roundedRect: CGRect(x: -s / 2, y: -s / 2, width: s, height: s), cornerRadius: 3), with: .color(i % 3 == 0 ? Ink.lime2 : Ink.lime))
            }
        case .fireworks:
            for b in 0..<4 {
                let cx = size.width * (0.2 + r() * 0.6), cy = size.height * (0.15 + r() * 0.35)
                let delay = Double(b) * 0.28, lt = t - delay
                guard lt > 0 else { continue }
                let col = colours[b % colours.count]
                for _ in 0..<34 {
                    let a = r() * .pi * 2, sp = 120 + r() * 160
                    let x = cx + cos(a) * sp * lt, y = cy + sin(a) * sp * lt + 90 * lt * lt
                    var c = ctx; c.opacity = max(0, 1 - lt / 1.6)
                    c.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)), with: .color(col))
                }
            }
        case .confetti:
            for i in 0..<110 {
                let x = r() * size.width + sin(t * 3 + Double(i)) * 24
                let y = -40 + (180 + r() * 420) * t
                let w = 6 + r() * 6
                var c = ctx; c.opacity = fade
                c.translateBy(x: x, y: y); c.rotate(by: .radians(t * 5 + Double(i)))
                c.fill(Path(CGRect(x: -w / 2, y: -2.5, width: w, height: 5)), with: .color(colours[i % colours.count]))
            }
        }
    }
}

// MARK: Settings

struct SettingsSheet: View {
    @Environment(Store.self) private var store
    @Environment(Purchases.self) private var purchases
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var checkIn = Reminders.checkInOn
    @State private var checkInAt = Day.cal.date(bySettingHour: Reminders.checkInMinutes / 60, minute: Reminders.checkInMinutes % 60, second: 0, of: .now) ?? .now
    @State private var icloud = CloudSync.enabled
    @State private var watermark = ShareCard.watermarkOn
    @State private var csvURL: URL? = nil
    @State private var manage = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings.").font(.big(26)).foregroundStyle(Ink.white).padding(.top, 22)
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow("Chain Unlimited")
                    HStack {
                        Image(systemName: purchases.unlocked ? "checkmark.seal.fill" : "lock.fill").foregroundStyle(purchases.unlocked ? Ink.lime : Ink.grey)
                        Text(purchases.unlocked ? (purchases.grandfathered ? "Unlocked: you bought Chain before it went free" : "Unlocked. Thank you.") : "Free: three habits, the Next Up widget, the last 90 days")
                            .font(.ui(14, .heavy)).foregroundStyle(Ink.white)
                    }
                    if !purchases.unlocked {
                        LimeButton(title: "Unlock for \(purchases.priceText), once", icon: "infinity") { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { router.paywall = .settings } }
                    }
                    GreyButton(title: purchases.busy == "restore" ? "Restoring…" : "Restore purchases", icon: "arrow.clockwise") { Task { await purchases.restore() } }
                    if let m = purchases.message { Text(m).font(.ui(12, .medium)).foregroundStyle(Ink.amber) }
                }.tile()

                Button { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { router.shop = true } } label: {
                    HStack(spacing: 12) {
                        HStack(spacing: 3) { ForEach(Palette.all.prefix(5)) { p in RoundedRectangle(cornerRadius: 4).fill(p.accent).frame(width: 12, height: 26) } }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Themes, icons and celebrations").font(.ui(14, .heavy)).foregroundStyle(Ink.white)
                            Text("Now: \(Palette.current.name)").font(.ui(12, .medium)).foregroundStyle(Ink.grey)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .black)).foregroundStyle(Ink.lime)
                    }.tile(padding: 14)
                }.buttonStyle(Press())

                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow("Daily check-in")
                    Toggle(isOn: $checkIn) { Text("One reminder a day, if anything is left").font(.ui(14, .semibold)).foregroundStyle(Ink.white) }.tint(Ink.lime)
                        .onChange(of: checkIn) { _, on in
                            Reminders.checkInOn = on
                            Task { if on { _ = await Reminders.ask() }; Reminders.sync(store, pro: purchases.unlocked) }
                        }
                    if checkIn {
                        DatePicker("At", selection: $checkInAt, displayedComponents: .hourAndMinute).font(.ui(14, .semibold)).foregroundStyle(Ink.white).tint(Ink.lime)
                            .onChange(of: checkInAt) { _, d in
                                Reminders.checkInMinutes = Day.cal.component(.hour, from: d) * 60 + Day.cal.component(.minute, from: d)
                                Reminders.sync(store, pro: purchases.unlocked)
                            }
                    }
                    Text(purchases.unlocked ? "Per-habit reminders are in each habit's editor." : "Free. A reminder per habit, with a Done button, comes with Unlimited.").font(.ui(11, .medium)).foregroundStyle(Ink.dim)
                }.tile()

                VStack(alignment: .leading, spacing: 12) {
                    HStack { Eyebrow("Streak protection"); Spacer() }
                    row("snowflake", Ink.ice, "\(store.freezesLeft(pro: purchases.unlocked)) of \(purchases.unlocked ? 3 : 1) freezes left this month", "Hold a missed square in Week to use one.")
                    row("bandage.fill", Ink.patch, store.repairCredits > 0 ? "\(store.repairCredits) Streak Repair\(store.repairCredits == 1 ? "" : "s") banked" : "Streak Repair, \(purchases.price(Purchases.repairID)) each", "Patch a missed day in gold when the freezes run out.")
                }.tile()

                VStack(alignment: .leading, spacing: 12) {
                    HStack { Eyebrow("Your data"); if !purchases.unlocked { ProTag() } }
                    Toggle(isOn: Binding(get: { icloud }, set: { on in
                        if on && !purchases.unlocked { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { router.paywall = .sync }; return }
                        icloud = on; CloudSync.enabled = on; if on { CloudSync.push(store) }
                    })) { Text("Back up to iCloud").font(.ui(14, .semibold)).foregroundStyle(Ink.white) }.tint(Ink.lime)
                    if icloud, let d = CloudSync.lastBackup { Text("Last backup \(d.formatted(.relative(presentation: .named)))").font(.ui(11, .medium)).foregroundStyle(Ink.dim) }
                    if purchases.unlocked, let csvURL {
                        ShareLink(item: csvURL) { Label("Export every day as CSV", systemImage: "tablecells").font(.ui(14, .heavy)).foregroundStyle(Ink.lime) }
                    } else if !purchases.unlocked {
                        Button { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { router.paywall = .export } } label: { Label("Export every day as CSV", systemImage: "tablecells").font(.ui(14, .heavy)).foregroundStyle(Ink.grey) }.buttonStyle(.plain)
                    }
                    if purchases.unlocked {
                        Toggle(isOn: $watermark) { Text("Chain name on shared images").font(.ui(14, .semibold)).foregroundStyle(Ink.white) }.tint(Ink.lime)
                            .onChange(of: watermark) { _, on in ShareCard.watermarkOn = on }
                    }
                    GreyButton(title: "Reorder and archive habits", icon: "line.3.horizontal") { manage = true }
                }.tile()

                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("Widgets and Siri")
                    Text("Touch and hold your Home Screen, tap Edit, then Add Widget, and pick Chain. Next Up is free; Today, Quilt and the Lock Screen line come with Unlimited.").font(.ui(13, .medium)).foregroundStyle(Ink.grey)
                    Text("Say \"Log Read in Chain\" to Siri, or use the Log a habit shortcut.").font(.ui(13, .medium)).foregroundStyle(Ink.grey)
                }.tile()

                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow("About")
                    Text("Chain keeps everything on this iPhone, plus your own iCloud if you turn backup on. No account, no ads, no tracking.").font(.ui(13, .medium)).foregroundStyle(Ink.grey)
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")").font(.num(12, .bold)).foregroundStyle(Ink.dim)
                }.tile()
            }.padding(18)
        }
        .sheet(isPresented: $manage) { HabitsManager().presentationBackground(Ink.bg2).presentationDetents([.large]) }
        .task {
            await purchases.loadProducts()
            let u = URL.temporaryDirectory.appending(path: "Chain export \(Day.today).csv")
            try? store.csv().write(to: u, atomically: true, encoding: .utf8)
            csvURL = u
        }
    }
    func row(_ icon: String, _ tint: Color, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14, weight: .black)).foregroundStyle(Ink.bg).frame(width: 32, height: 32).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint))
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.ui(14, .heavy)).foregroundStyle(Ink.white); Text(detail).font(.ui(12, .medium)).foregroundStyle(Ink.grey) }
        }
    }
}

struct HabitsManager: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        @Bindable var store = store
        NavigationStack {
            List {
                Section("Habits") {
                    ForEach(store.habits.filter { !$0.archived }) { h in Text(h.emoji + "  " + h.name).font(.ui(15, .heavy)) }
                        .onMove { from, to in
                            var live = store.habits.filter { !$0.archived }
                            live.move(fromOffsets: from, toOffset: to)
                            store.habits = live + store.habits.filter(\.archived); store.save()
                        }
                }
                let arch = store.habits.filter(\.archived)
                if !arch.isEmpty {
                    Section("Archived") {
                        ForEach(arch) { h in
                            HStack { Text(h.emoji + "  " + h.name).font(.ui(15, .heavy)).foregroundStyle(.secondary); Spacer()
                                Button("Restore") { if let i = store.habits.firstIndex(where: { $0.id == h.id }) { store.habits[i].archived = false; store.save() } }.tint(Ink.lime)
                            }
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .navigationTitle("Order")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.tint(Ink.lime) } }
        }
    }
}

// MARK: Shop

/// The 99-cent corner: colour themes with matching icons, and the celebration pack.
struct ShopSheet: View {
    @Environment(Purchases.self) private var purchases
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var current = Palette.current.id
    @State private var celebration = Celebration.Style.saved
    @State private var preview = 0
    var body: some View {
        ZStack(alignment: .topTrailing) {
            CharcoalBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow("Make it yours")
                        Text("Themes.").font(.big(32)).foregroundStyle(Ink.white)
                        Text("Each one recolours the whole app, the widgets and the app icon. \(purchases.price(Purchases.themeID("ember"))) each, yours for good.").font(.ui(14, .medium)).foregroundStyle(Ink.grey)
                    }.padding(.top, 50)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(Palette.all) { p in themeCard(p) }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Celebration pack").font(.ui(17, .heavy)).foregroundStyle(Ink.white)
                                Text("Fireworks and confetti for every clean sweep. Stitch stays free.").font(.ui(12, .medium)).foregroundStyle(Ink.grey)
                            }
                            Spacer()
                            if !purchases.ownsCelebrations {
                                priceButton(Purchases.celebrateID)
                            }
                        }
                        HStack(spacing: 8) {
                            ForEach(Celebration.Style.allCases, id: \.self) { s in
                                let ok = s == .stitch || purchases.ownsCelebrations
                                Button {
                                    preview += 1
                                    if ok { celebration = s; UserDefaults.standard.set(s.rawValue, forKey: "chain.celebration") }
                                } label: {
                                    HStack(spacing: 4) {
                                        if !ok { Image(systemName: "lock.fill").font(.system(size: 10, weight: .black)) }
                                        Text(s.title).font(.ui(13, .heavy))
                                    }
                                    .foregroundStyle(celebration == s && ok ? Ink.bg : Ink.grey).frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(celebration == s && ok ? Ink.lime : Ink.card2))
                                }.buttonStyle(Press())
                            }
                        }
                    }.tile()
                    Text("Purchases are one-time and restore on any of your devices from Settings.").font(.ui(12, .medium)).foregroundStyle(Ink.dim).frame(maxWidth: .infinity).multilineTextAlignment(.center)
                    if let m = purchases.message { Text(m).font(.ui(12, .medium)).foregroundStyle(Ink.amber).frame(maxWidth: .infinity) }
                }.padding(.horizontal, 18).padding(.bottom, 30)
            }
            Celebration(trigger: preview, style: purchases.ownsCelebrations ? celebration : .stitch).allowsHitTesting(false).ignoresSafeArea()
            CloseButton { dismiss() }.padding(.trailing, 18).padding(.top, 16)
        }
        .task { await purchases.loadProducts() }
    }

    func themeCard(_ p: Palette) -> some View {
        let owned = purchases.ownsTheme(p.id), on = current == p.id
        return Button {
            if owned { use(p) } else { Task { if await purchases.buy(Purchases.themeID(p.id)) { use(p) } } }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Canvas { ctx, size in
                    let cols = 7, rows = 3, cell = size.width / CGFloat(cols), s = cell - 3
                    for c in 0..<cols { for r in 0..<rows {
                        let i = c * rows + r
                        let col = [5, 13, 17].contains(i) ? Ink.hole : i % 4 == 0 ? p.mid : p.accent
                        ctx.fill(Path(roundedRect: CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: s, height: s), cornerRadius: 3), with: .color(col))
                    } }
                }.frame(height: 50)
                HStack {
                    Text(p.name).font(.ui(16, .heavy)).foregroundStyle(Ink.white)
                    Spacer()
                    if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(p.accent) }
                    else if owned { Text("Use").font(.ui(12, .heavy)).foregroundStyle(p.accent) }
                    else if purchases.busy == Purchases.themeID(p.id) { ProgressView().tint(p.accent) }
                    else { Text(purchases.price(Purchases.themeID(p.id))).font(.ui(12, .heavy)).foregroundStyle(Ink.bg).padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(p.accent)) }
                }
                Text(p.blurb).font(.ui(11, .medium)).foregroundStyle(Ink.grey).lineLimit(2, reservesSpace: true)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Ink.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(on ? p.accent : Ink.line, lineWidth: on ? 2 : 1))
        }.buttonStyle(Press()).disabled(purchases.busy != nil)
    }

    func priceButton(_ id: String) -> some View {
        Button { Task { await purchases.buy(id) } } label: {
            Group { if purchases.busy == id { ProgressView().tint(Ink.bg) } else { Text(purchases.price(id)).font(.ui(13, .heavy)) } }
                .foregroundStyle(Ink.bg).padding(.horizontal, 14).padding(.vertical, 8).background(Capsule().fill(Ink.lime))
        }.buttonStyle(Press()).disabled(purchases.busy != nil)
    }

    func use(_ p: Palette) {
        Palette.apply(p.id)
        AppDelegate.styleSegments()
        current = p.id
        if !router.demo, UIApplication.shared.supportsAlternateIcons, UIApplication.shared.alternateIconName != p.icon {
            UIApplication.shared.setAlternateIconName(p.icon)
        }
        WidgetCenter.shared.reloadAllTimelines()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        router.themeTick += 1
    }
}

// MARK: Onboarding

struct Onboarding: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(Purchases.self) private var purchases
    @State private var page = 0
    @State private var picked: [Int] = []
    @State private var remind = true
    @State private var at = Day.cal.date(bySettingHour: 20, minute: 0, second: 0, of: .now) ?? .now
    @State private var lit = 0

    struct Starter { let name: String; let emoji: String; let kind: Kind; let part: Part; var freq: Frequency = .daily; var perWeek = 3 }
    static let starters: [(String, [Starter])] = [
        ("Mornings", [Starter(name: "Make the bed", emoji: "🛏️", kind: .build, part: .morning), Starter(name: "Drink a glass of water", emoji: "💧", kind: .build, part: .morning), Starter(name: "Move for 20 minutes", emoji: "🏃", kind: .build, part: .morning)]),
        ("Mind", [Starter(name: "Read 10 pages", emoji: "📖", kind: .build, part: .evening), Starter(name: "Meditate 5 minutes", emoji: "🧘", kind: .build, part: .morning), Starter(name: "Journal one line", emoji: "✍️", kind: .build, part: .evening)]),
        ("Body", [Starter(name: "Workout", emoji: "💪", kind: .build, part: .afternoon, freq: .weekly, perWeek: 3), Starter(name: "Eat a vegetable", emoji: "🥗", kind: .build, part: .anytime), Starter(name: "In bed by 11", emoji: "😴", kind: .build, part: .evening)]),
        ("Quit", [Starter(name: "No smoking", emoji: "🚭", kind: .quit, part: .anytime), Starter(name: "No alcohol", emoji: "🍺", kind: .quit, part: .anytime), Starter(name: "No doomscrolling", emoji: "📵", kind: .quit, part: .anytime)]),
    ]
    var flat: [Starter] { Onboarding.starters.flatMap(\.1) }

    var body: some View {
        ZStack {
            CharcoalBackground()
            switch page {
            case 0: hello
            case 1: pick
            default: reminder
            }
        }
        .animation(.snappy, value: page)
    }

    private var hello: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Canvas { ctx, size in
                let cols = 10, rows = 7, cell = size.width / CGFloat(cols), s = cell - 5
                for c in 0..<cols { for r in 0..<rows {
                    let i = c * rows + r
                    let on = i < lit && ![12, 33, 47].contains(i)
                    ctx.fill(Path(roundedRect: CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: s, height: s), cornerRadius: 5), with: .color(on ? (c > 6 ? Ink.lime : Ink.lime2) : Ink.hole))
                } }
            }.aspectRatio(10.0 / 7.0, contentMode: .fit)
            VStack(alignment: .leading, spacing: 10) {
                Text("Don't break\nthe chain.").font(.big(40)).foregroundStyle(Ink.white)
                Text("Do the thing, tick the square. Every day you do, the chain gets longer, and you won't want to break it.").font(.ui(16, .medium)).foregroundStyle(Ink.grey)
            }
            Spacer()
            LimeButton(title: "Pick your first habits", icon: "arrow.right") { page = 1 }
        }
        .padding(24)
        .task { for i in 1...70 { try? await Task.sleep(for: .milliseconds(18)); withAnimation(.snappy(duration: 0.2)) { lit = i } } }
    }

    private var pick: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Start small.").font(.big(32)).foregroundStyle(Ink.white).padding(.top, 30)
            Text("Pick up to three. You can change everything later.").font(.ui(14, .medium)).foregroundStyle(Ink.grey)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(Onboarding.starters.enumerated()), id: \.offset) { gi, g in
                        Eyebrow(g.0)
                        ForEach(Array(g.1.enumerated()), id: \.offset) { si, s in
                            let idx = Onboarding.starters.prefix(gi).reduce(0) { $0 + $1.1.count } + si
                            let on = picked.contains(idx)
                            Button {
                                if on { picked.removeAll { $0 == idx } } else if picked.count < 3 { picked.append(idx) }
                                UISelectionFeedbackGenerator().selectionChanged()
                            } label: {
                                HStack(spacing: 12) {
                                    Text(s.emoji).font(.system(size: 22))
                                    Text(s.name).font(.ui(16, .heavy)).foregroundStyle(Ink.white)
                                    Spacer()
                                    Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: 22, weight: .bold)).foregroundStyle(on ? Ink.lime : Ink.dim)
                                }.tile(padding: 14)
                            }.buttonStyle(Press()).opacity(!on && picked.count >= 3 ? 0.5 : 1)
                        }
                    }
                }.padding(.bottom, 10)
            }
            LimeButton(title: picked.isEmpty ? "I'll make my own" : "Start \(picked.count) chain\(picked.count == 1 ? "" : "s")", icon: "arrow.right") {
                for i in picked {
                    let s = flat[i]
                    store.habits.append(Habit(name: s.name, emoji: s.emoji, frequency: s.freq, perWeek: s.perWeek, start: Day.today, kind: s.kind, part: s.part))
                }
                store.save()
                page = 2
            }
        }.padding(.horizontal, 22).padding(.bottom, 20)
    }

    private var reminder: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Image(systemName: "bell.badge.fill").font(.system(size: 44, weight: .bold)).foregroundStyle(Ink.lime)
            Text("A nudge, once a day.").font(.big(32)).foregroundStyle(Ink.white)
            Text("If anything is still left, Chain reminds you at this time. Nothing else, ever.").font(.ui(15, .medium)).foregroundStyle(Ink.grey)
            DatePicker("Remind me at", selection: $at, displayedComponents: .hourAndMinute).font(.ui(16, .heavy)).foregroundStyle(Ink.white).tint(Ink.lime).tile(padding: 14)
            Spacer()
            LimeButton(title: "Turn it on", icon: "bell.fill") {
                Reminders.checkInOn = true
                Reminders.checkInMinutes = Day.cal.component(.hour, from: at) * 60 + Day.cal.component(.minute, from: at)
                Task { _ = await Reminders.ask(); Reminders.sync(store, pro: purchases.unlocked); finish() }
            }
            Button { finish() } label: { Text("Not now").font(.ui(14, .heavy)).foregroundStyle(Ink.grey).frame(maxWidth: .infinity) }.buttonStyle(.plain)
        }.padding(24)
    }

    func finish() {
        UserDefaults.standard.set(true, forKey: "chain.onboarded")
        router.onboarding = false
        if store.active.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { router.creating = true } }
    }
}

// MARK: Screenshot-only

/// The widgets on a home screen, for the App Store screenshot. The real widgets draw the same views.
struct WidgetShowcase: View {
    @Environment(Store.self) private var store
    var body: some View {
        let snap = Snapshot.make(store, unlocked: true)
        ZStack {
            LinearGradient(colors: [Ink.lime3, Color(red: 0.05, green: 0.06, blue: 0.08), Color(red: 0.08, green: 0.05, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            VStack(spacing: 22) {
                VStack(spacing: 2) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())).font(.ui(17, .semibold)).foregroundStyle(.white.opacity(0.8))
                    Text("9:41").font(.system(size: 84, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.9))
                    LockRectView(snap: snap).foregroundStyle(.white).frame(width: 170).padding(.top, 4)
                }.padding(.top, 50)
                HStack(spacing: 22) {
                    widget(NextUpView(snap: snap), w: 170, h: 170)
                    VStack(spacing: 14) {
                        ForEach(0..<2, id: \.self) { _ in
                            HStack(spacing: 14) { ForEach(0..<2, id: \.self) { _ in RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.12)).frame(width: 64, height: 64) } }
                        }
                    }
                }
                widget(TodayListView(snap: snap, limit: 6, large: true), w: 364, h: 382)
                Spacer()
            }
        }
    }
    func widget<V: View>(_ v: V, w: CGFloat, h: CGFloat) -> some View {
        v.padding(16).frame(width: w, height: h, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Ink.bg))
            .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
    }
}
