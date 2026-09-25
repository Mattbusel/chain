import SwiftUI

// MARK: Today

struct TodayView: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(Purchases.self) private var purchases
    var body: some View {
        let t = Day.today
        let due = store.habits.filter { store.due($0, t) }
        let n = due.filter { store.satisfiedToday($0) }.count
        let frac = due.isEmpty ? 0 : Double(n) / Double(due.count)
        Page {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(greeting).font(.big(30)).foregroundStyle(Ink.white)
                    (Text("\(n) of \(due.count)").foregroundStyle(Ink.lime) + Text(" done.").foregroundStyle(Ink.white)).font(.big(30))
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()) + (frac == 1 && !due.isEmpty ? " · Clean sweep." : n == 0 ? " · Start with the easiest one." : " · Keep the chain.")).font(.ui(13, .medium)).foregroundStyle(Ink.grey)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Button { router.settings = true } label: {
                        Image(systemName: "gearshape.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Ink.dim)
                            .frame(width: 32, height: 32).background(Circle().fill(Ink.card))
                    }.buttonStyle(.plain).accessibilityLabel("Settings")
                    Ring(fraction: frac)
                }
            }
            .padding(.top, 14)
            ForEach(due) { h in HabitRow(habit: h) }
            if due.isEmpty {
                VStack(spacing: 10) {
                    Text("Nothing due today.").font(.ui(16, .heavy)).foregroundStyle(Ink.white)
                    Text(store.habits.isEmpty ? "Add a habit. Start with something you can do in two minutes." : "Enjoy it.").font(.ui(13, .medium)).foregroundStyle(Ink.grey)
                }.frame(maxWidth: .infinity).tile(padding: 24)
            }
            LimeButton(title: "New habit", icon: "plus") { router.newHabit(store, purchases) }
            if !purchases.unlocked {
                Button { router.paywall = .habits } label: {
                    HStack(spacing: 6) {
                        ForEach(0..<Purchases.freeHabits, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3).fill(i < store.habits.count ? Ink.lime : Ink.hole).frame(width: 12, height: 12)
                        }
                        Text("\(min(store.habits.count, Purchases.freeHabits)) of \(Purchases.freeHabits) free habits").font(.ui(12, .heavy)).foregroundStyle(Ink.grey)
                        Spacer()
                        Text("Unlimited").font(.ui(12, .heavy)).foregroundStyle(Ink.lime)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .black)).foregroundStyle(Ink.lime)
                    }.padding(.horizontal, 4)
                }.buttonStyle(.plain)
            }
        }
    }
    var greeting: String { let h = Calendar.current.component(.hour, from: .now); return h < 12 ? "Morning." : h < 18 ? "Afternoon." : "Evening." }
}

struct HabitRow: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    let habit: Habit
    var body: some View {
        let t = Day.today, dn = store.done(habit, t)
        HStack(spacing: 14) {
            Button {
                withAnimation(.snappy(duration: 0.3)) { store.toggle(habit, t) }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(dn ? Ink.lime : Ink.bg2)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(dn ? Ink.lime : Ink.line2, lineWidth: 2))
                    if dn { Image(systemName: "checkmark").font(.system(size: 24, weight: .black)).foregroundStyle(Ink.bg) } else { Text(habit.emoji).font(.system(size: 24)) }
                }
                .frame(width: 56, height: 56)
                .scaleEffect(dn ? 1.0 : 0.96)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                Text(habit.name).font(.ui(17, .heavy)).foregroundStyle(Ink.white)
                Text(subtitle).font(.ui(12, .medium)).foregroundStyle(Ink.dim)
                HStack(spacing: 3) {
                    ForEach(0..<14, id: \.self) { i in
                        let k = Day.add(t, i - 13)
                        RoundedRectangle(cornerRadius: 3).fill(!store.due(habit, k) ? Ink.line : store.done(habit, k) ? Ink.lime : Ink.hole).frame(width: 12, height: 12)
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(k == t ? Ink.dim : .clear))
                    }
                }.padding(.top, 4)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(store.streak(habit))").font(.num(24)).foregroundStyle(Ink.white)
                Text(habit.frequency == .weekly ? "wk streak" : "day streak").font(.ui(10, .heavy)).foregroundStyle(Ink.dim)
            }
        }
        .tile(padding: 12)
        .background(Group { if dn { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Ink.lime.opacity(0.06)) } })
        .contentShape(Rectangle())
        .onLongPressGesture { router.editing = habit }
    }
    var subtitle: String {
        switch habit.frequency {
        case .daily: return "every day · hold to edit"
        case .days: return habit.days.sorted().map { Day.names[$0] }.joined(separator: " · ")
        case .weekly: return "\(habit.perWeek)× a week · \(store.weekHits(habit, Day.today)) so far"
        }
    }
}

// MARK: Week

struct WeekView: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(Purchases.self) private var purchases
    var body: some View {
        @Bindable var store = store
        let ws = Day.add(Day.weekStart(Day.today), 7 * store.weekOffset)
        let days = (0..<7).map { Day.add(ws, $0) }
        Page {
            HStack(alignment: .lastTextBaseline) {
                Text("Week.").font(.big(30)).foregroundStyle(Ink.white)
                Spacer()
                Button {
                    // Free keeps the last 30 days: this week and the four before it.
                    if !purchases.unlocked && store.weekOffset <= -4 { router.paywall = .history } else { store.weekOffset -= 1 }
                } label: { Image(systemName: "chevron.left").font(.system(size: 14, weight: .black)).foregroundStyle(Ink.grey).frame(width: 34, height: 34).background(Circle().fill(Ink.card)) }.buttonStyle(.plain)
                Text(Day.date(ws).formatted(.dateTime.month(.abbreviated).day()) + " – " + Day.date(days[6]).formatted(.dateTime.month(.abbreviated).day())).font(.ui(13, .heavy)).foregroundStyle(Ink.grey)
                Button { if store.weekOffset < 0 { store.weekOffset += 1 } } label: { Image(systemName: "chevron.right").font(.system(size: 14, weight: .black)).foregroundStyle(store.weekOffset < 0 ? Ink.grey : Ink.dim).frame(width: 34, height: 34).background(Circle().fill(Ink.card)) }.buttonStyle(.plain)
            }.padding(.top, 14)
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    Text("").frame(width: 92, alignment: .leading)
                    ForEach(days, id: \.self) { d in
                        VStack(spacing: 1) { Text(Day.names[Day.dow(d)]).font(.ui(10, .heavy)); Text(String(d.suffix(2))).font(.num(11, .bold)) }
                            .foregroundStyle(d == Day.today ? Ink.lime : Ink.dim).frame(maxWidth: .infinity)
                    }
                }.padding(.bottom, 8)
                ForEach(store.habits) { h in
                    HStack(spacing: 4) {
                        HStack(spacing: 6) { Text(h.emoji).font(.system(size: 13)); Text(h.name).font(.ui(12, .heavy)).foregroundStyle(Ink.white).lineLimit(2) }.frame(width: 92, alignment: .leading)
                        ForEach(days, id: \.self) { d in
                            let dn = store.done(h, d), na = !store.due(h, d) || d > Day.today
                            Button { if d <= Day.today { store.toggle(h, d) } } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(dn ? Ink.lime : Ink.bg2)
                                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(dn ? Ink.lime : d == Day.today ? Ink.dim : Ink.line2))
                                    if dn { Image(systemName: "checkmark").font(.system(size: 13, weight: .black)).foregroundStyle(Ink.bg) }
                                }.frame(height: 36).opacity(na && !dn ? 0.3 : 1)
                            }.buttonStyle(.plain)
                        }
                    }.padding(.vertical, 5)
                }
            }.tile(padding: 12)
            Text("Tap any square to log or undo a day. Faded squares are days a habit is not due.").font(.ui(12, .medium)).foregroundStyle(Ink.dim)
        }
    }
}

// MARK: Year

struct YearView: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(Purchases.self) private var purchases
    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: 4) {
                Text("The year.").font(.big(30)).foregroundStyle(Ink.white)
                Text("Every day, every habit. The colour is the chain; a hole is a hole.").font(.ui(13, .medium)).foregroundStyle(Ink.grey)
            }.padding(.top, 14)
            if !purchases.unlocked && !store.habits.isEmpty {
                Button { router.paywall = .history } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill").font(.system(size: 14, weight: .black)).foregroundStyle(Ink.bg)
                            .frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Ink.lime))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Free shows the last 30 days").font(.ui(14, .heavy)).foregroundStyle(Ink.white)
                            Text("Unlock the whole quilt, back to day one.").font(.ui(12, .medium)).foregroundStyle(Ink.grey)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .black)).foregroundStyle(Ink.lime)
                    }.tile(padding: 12)
                }.buttonStyle(.plain)
            }
            ForEach(store.habits) { h in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(h.emoji + " " + h.name).font(.ui(15, .heavy)).foregroundStyle(Ink.white)
                        Spacer()
                        Text("\(store.total(h)) done · best \(store.best(h)) · \(Int((store.rate(h, days: 365) * 100).rounded()))%").font(.num(11, .bold)).foregroundStyle(Ink.dim)
                    }
                    Quilt(habit: h, locked: !purchases.unlocked)
                }.tile()
            }
            if store.habits.isEmpty { Text("Add a habit and this fills in day by day.").font(.ui(14, .medium)).foregroundStyle(Ink.grey).tile() }
        }
    }
}

/// 26 weeks of squares, one row per weekday, stitched like a quilt.
struct Quilt: View {
    @Environment(Store.self) private var store
    let habit: Habit
    var locked = false
    var body: some View {
        let end = Day.today
        let start = Day.add(Day.weekStart(end), -25 * 7)
        Canvas { ctx, size in
            let cols = 26.0
            let cell = (size.width - 22) / cols
            let s = max(2, cell - 3)
            var d = start
            var col = 0
            while d <= end {
                let r = Day.dow(d)
                let x = 22 + Double(col) * cell, y = Double(r) * cell
                let rect = CGRect(x: x, y: y, width: s, height: s)
                let hidden = locked && Day.diff(d, end) >= Purchases.freeHistoryDays
                let colour: Color = hidden ? Ink.line.opacity(0.5) : d < habit.start ? Ink.line.opacity(0.4) : store.done(habit, d) ? Ink.lime : store.due(habit, d) ? Ink.hole : Ink.line
                ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(colour))
                if !hidden && store.done(habit, d) {
                    // Stitches: a little cross on done days, the quilt look.
                    var p = Path()
                    p.move(to: CGPoint(x: rect.minX + 2, y: rect.minY + 2)); p.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.maxY - 2))
                    ctx.stroke(p, with: .color(Ink.lime2.opacity(0.5)), lineWidth: 1)
                }
                if r == 6 { col += 1 }
                d = Day.add(d, 1)
            }
            for (i, n) in ["M", "W", "F", "S"].enumerated() {
                let row = [0, 2, 4, 6][i]
                ctx.draw(Text(n).font(.ui(9, .heavy)).foregroundStyle(Ink.dim), at: CGPoint(x: 8, y: Double(row) * cell + s / 2))
            }
        }
        .frame(height: 7 * ((UIScreen.main.bounds.width - 32 - 32 - 22) / 26))
    }
}

// MARK: Stats

struct StatsView: View {
    @Environment(Store.self) private var store
    var body: some View {
        let hs = store.habits
        let avg30 = hs.isEmpty ? 0 : hs.reduce(0) { $0 + store.rate($1, days: 30) } / Double(hs.count)
        let bestS = hs.map { store.best($0) }.max() ?? 0
        let wd = store.weekdayRates()
        Page {
            Text("Stats.").font(.big(30)).foregroundStyle(Ink.white).padding(.top, 14)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                stat("\(store.totalDone)", "check-ins, all time")
                stat("\(Int((avg30 * 100).rounded()))%", "completion, 30 days")
                stat("\(bestS)", "longest chain ever")
                stat("\(store.perfectDays(30))", "perfect days in 30")
            }
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("Per habit")
                ForEach(hs) { h in
                    HStack(spacing: 10) {
                        Text(h.emoji).font(.system(size: 16))
                        Text(h.name).font(.ui(13, .heavy)).foregroundStyle(Ink.white).lineLimit(1)
                        Spacer()
                        col("\(store.streak(h))", "now"); col("\(store.best(h))", "best"); col("\(Int((store.rate(h, days: 30) * 100).rounded()))%", "30d"); col("\(store.total(h))", "total")
                    }.padding(.vertical, 6)
                }
            }.tile()
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("Best days of the week, last 90")
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(0..<7, id: \.self) { i in
                        VStack(spacing: 4) {
                            Text("\(Int((wd[i] * 100).rounded()))").font(.num(10, .bold)).foregroundStyle(Ink.grey)
                            RoundedRectangle(cornerRadius: 5).fill(wd[i] >= 0.8 ? Ink.lime : wd[i] >= 0.5 ? Ink.lime2 : Ink.hole).frame(height: max(4, 70 * wd[i]))
                            Text(Day.names[i]).font(.ui(10, .heavy)).foregroundStyle(Ink.dim)
                        }.frame(maxWidth: .infinity)
                    }
                }.frame(height: 110, alignment: .bottom)
            }.tile()
        }
    }
    func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(v).font(.num(28)).foregroundStyle(Ink.lime); Text(l).font(.ui(11, .heavy)).foregroundStyle(Ink.dim) }.frame(maxWidth: .infinity, alignment: .leading).tile(padding: 14)
    }
    func col(_ v: String, _ l: String) -> some View {
        VStack(spacing: 0) { Text(v).font(.num(13, .bold)).foregroundStyle(Ink.white); Text(l).font(.ui(9, .heavy)).foregroundStyle(Ink.dim) }.frame(width: 40)
    }
}

// MARK: Editor

struct HabitEditor: View {
    @Environment(Store.self) private var store
    @Environment(Purchases.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @State var habit: Habit
    @State private var paywall: Locked? = nil
    let isNew: Bool
    static let emojis = ["📖", "🏃", "💧", "🧘", "💪", "🥗", "😴", "✍️", "🎸", "🧹", "💊", "🚭", "🌱", "🧠", "📵", "🦷", "🚶", "🎯", "🧺", "☀️"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(isNew ? "New habit." : "Edit habit.").font(.big(26)).foregroundStyle(Ink.white).padding(.top, 22)
                TextField("Read 20 pages", text: $habit.name).font(.ui(20, .heavy)).foregroundStyle(Ink.white).padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Ink.card))
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("Icon")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 10), spacing: 6) {
                        ForEach(HabitEditor.emojis, id: \.self) { e in
                            Button { habit.emoji = e } label: { Text(e).font(.system(size: 20)).frame(height: 34).frame(maxWidth: .infinity).background(RoundedRectangle(cornerRadius: 8).fill(habit.emoji == e ? Ink.lime.opacity(0.25) : .clear)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(habit.emoji == e ? Ink.lime : .clear)) }.buttonStyle(.plain)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("How often")
                    Picker("", selection: $habit.frequency) { Text("Every day").tag(Frequency.daily); Text("Certain days").tag(Frequency.days); Text("N a week").tag(Frequency.weekly) }.pickerStyle(.segmented)
                    if habit.frequency == .days {
                        HStack(spacing: 6) {
                            ForEach(0..<7, id: \.self) { i in
                                Button { if let j = habit.days.firstIndex(of: i) { habit.days.remove(at: j) } else { habit.days.append(i) } } label: {
                                    Text(Day.names[i]).font(.ui(12, .heavy)).foregroundStyle(habit.days.contains(i) ? Ink.bg : Ink.grey).frame(maxWidth: .infinity).frame(height: 36)
                                        .background(RoundedRectangle(cornerRadius: 9).fill(habit.days.contains(i) ? Ink.lime : Ink.card))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    if habit.frequency == .weekly {
                        Stepper("\(habit.perWeek) times a week", value: $habit.perWeek, in: 1...7).font(.ui(14, .semibold)).foregroundStyle(Ink.white)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("Reminder")
                    Toggle(isOn: Binding(get: { habit.remind }, set: { on in
                        // Reminders come with Unlimited; one already set keeps working either way.
                        if on && !purchases.unlocked { paywall = .reminders } else { habit.remind = on }
                    })) { Text("Remind me every day").font(.ui(14, .semibold)).foregroundStyle(Ink.white) }.tint(Ink.lime)
                    if habit.remind {
                        Picker("At", selection: $habit.remindHour) { ForEach([7, 8, 9, 12, 17, 18, 19, 20, 21, 22], id: \.self) { h in Text(String(format: "%02d:00", h)).tag(h) } }.pickerStyle(.segmented)
                    }
                }
                Spacer(minLength: 10)
                HStack(spacing: 8) {
                    if !isNew { GreyButton(title: "Delete", icon: "trash") { store.habits.removeAll { $0.id == habit.id }; for k in store.log.keys { store.log[k]?.removeAll { $0 == habit.id } }; store.save(); Reminders.sync(store); dismiss() } }
                    LimeButton(title: "Save") {
                        let name = habit.name.trimmingCharacters(in: .whitespaces); guard !name.isEmpty else { return }
                        var h = habit; h.name = name
                        if let i = store.habits.firstIndex(where: { $0.id == h.id }) { store.habits[i] = h } else { store.habits.append(h) }
                        store.save(); Reminders.sync(store); dismiss()
                    }
                }
            }.padding(18)
        }
        .sheet(item: $paywall) { r in Paywall(reason: r).presentationBackground(Ink.bg).presentationDetents([.large]) }
    }
}
