import SwiftUI

// MARK: Today

struct TodayView: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(Purchases.self) private var purchases
    var body: some View {
        let due = store.dueToday
        let n = store.doneToday
        let frac = due.isEmpty ? 0 : Double(n) / Double(due.count)
        let quits = store.active.filter { $0.kind == .quit }
        let grouped = Set(due.map(\.part)).count > 1
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
            if let r = store.rescues().first { RescueBanner(rescue: r) }
            if grouped {
                ForEach(Part.allCases.filter { p in p != .anytime } + [.anytime], id: \.self) { p in
                    let hs = due.filter { $0.part == p }
                    if !hs.isEmpty {
                        SectionHead(title: p.title, icon: p.icon, trailing: "\(hs.filter { store.satisfiedToday($0) }.count)/\(hs.count)")
                        ForEach(ordered(hs)) { h in HabitRow(habit: h) }
                    }
                }
            } else {
                ForEach(ordered(due)) { h in HabitRow(habit: h) }
            }
            if due.isEmpty && quits.isEmpty {
                VStack(spacing: 10) {
                    Text("Nothing due today.").font(.ui(16, .heavy)).foregroundStyle(Ink.white)
                    Text(store.active.isEmpty ? "Add a habit. Start with something you can do in two minutes." : "Enjoy it.").font(.ui(13, .medium)).foregroundStyle(Ink.grey)
                }.frame(maxWidth: .infinity).tile(padding: 24)
            }
            if !quits.isEmpty {
                SectionHead(title: "Clean streaks", icon: "shield.fill")
                ForEach(quits) { h in QuitRow(habit: h) }
            }
            LimeButton(title: "New habit", icon: "plus") { router.newHabit(store, purchases) }
            if !purchases.unlocked {
                Button { router.paywall = .habits } label: {
                    HStack(spacing: 6) {
                        ForEach(0..<Purchases.freeHabits, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3).fill(i < store.active.count ? Ink.lime : Ink.hole).frame(width: 12, height: 12)
                        }
                        Text("\(min(store.active.count, Purchases.freeHabits)) of \(Purchases.freeHabits) free habits").font(.ui(12, .heavy)).foregroundStyle(Ink.grey)
                        Spacer()
                        Text("Unlimited").font(.ui(12, .heavy)).foregroundStyle(Ink.lime)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .black)).foregroundStyle(Ink.lime)
                    }.padding(.horizontal, 4)
                }.buttonStyle(.plain)
            }
        }
    }
    /// Still to do first, done ones sink.
    func ordered(_ hs: [Habit]) -> [Habit] { hs.filter { !store.satisfiedToday($0) } + hs.filter { store.satisfiedToday($0) } }
    var greeting: String { let h = Calendar.current.component(.hour, from: .now); return h < 12 ? "Morning." : h < 18 ? "Afternoon." : "Evening." }
}

struct HabitRow: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    let habit: Habit
    var body: some View {
        let t = Day.today, dn = store.done(habit, t), p = store.progress(habit, t)
        HStack(spacing: 14) {
            Button {
                let before = store.doneToday
                withAnimation(.snappy(duration: 0.3)) { store.toggle(habit, t) }
                let after = store.doneToday
                if after > before && after == store.dueToday.count {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    router.celebrating += 1
                } else {
                    UIImpactFeedbackGenerator(style: habit.isAmount && !store.done(habit, t) ? .light : .medium).impactOccurred()
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(dn ? Ink.lime : Ink.bg2)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(dn ? Ink.lime : Ink.line2, lineWidth: 2))
                    if !dn && p > 0 {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).trim(from: 0, to: p)
                            .stroke(Ink.lime, style: StrokeStyle(lineWidth: 3.5, lineCap: .round)).animation(.snappy, value: p)
                    }
                    if dn { Image(systemName: "checkmark").font(.system(size: 24, weight: .black)).foregroundStyle(Ink.bg) } else { Text(habit.emoji).font(.system(size: 24)) }
                }
                .frame(width: 56, height: 56)
                .scaleEffect(dn ? 1.0 : 0.96)
            }.buttonStyle(.plain)
                .accessibilityLabel(dn ? "\(habit.name), done" : "Tick off \(habit.name)")
            Button { router.detail = habit } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(habit.name).font(.ui(17, .heavy)).foregroundStyle(dn ? Ink.grey : Ink.white).lineLimit(1)
                        Text(subtitle).font(.ui(12, .medium)).foregroundStyle(habit.isAmount && !dn ? Ink.lime : Ink.dim).lineLimit(1)
                        HStack(spacing: 3) {
                            ForEach(0..<14, id: \.self) { i in
                                let k = Day.add(t, i - 13)
                                RoundedRectangle(cornerRadius: 3).fill(store.square(habit, k).color).frame(width: 12, height: 12)
                                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(k == t ? Ink.dim : .clear))
                            }
                        }.padding(.top, 4)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(store.streak(habit))").font(.num(24)).foregroundStyle(Ink.white).contentTransition(.numericText())
                        Text(habit.frequency == .weekly ? "wk chain" : "day chain").font(.ui(10, .heavy)).foregroundStyle(Ink.dim)
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .tile(padding: 12)
        .background(Group { if dn { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Ink.lime.opacity(0.06)) } })
        .contextMenu {
            Button { router.detail = habit } label: { Label("Details", systemImage: "chart.bar.fill") }
            Button { router.noting = habit } label: { Label(store.note(habit, t).isEmpty ? "Add a note" : "Edit note", systemImage: "note.text") }
            if habit.isAmount && store.count(habit, t) > 0 { Button { store.setCount(habit, t, 0); store.save() } label: { Label("Reset today", systemImage: "arrow.counterclockwise") } }
            Button { router.editing = habit } label: { Label("Edit", systemImage: "pencil") }
        }
    }
    var subtitle: String {
        let t = Day.today
        if habit.isAmount {
            let c = store.count(habit, t)
            return "\(c.formatted()) of \(habit.target.formatted()) \(habit.unit)" + (habit.health != nil ? " · from Health" : " · tap +\(habit.step)")
        }
        switch habit.frequency {
        case .daily: return store.note(habit, t).isEmpty ? "every day" : "📝 " + store.note(habit, t)
        case .days: return habit.days.sorted().map { Day.names[$0] }.joined(separator: " · ")
        case .weekly: return "\(habit.perWeek)× a week · \(store.weekHits(habit, t)) so far"
        }
    }
}

/// A habit being quit: the clean days count up, a slip resets them.
struct QuitRow: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    let habit: Habit
    @State private var confirm = false
    var body: some View {
        let days = store.cleanDays(habit), slipped = store.done(habit, Day.today)
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Ink.lime.opacity(0.12))
                Text(habit.emoji).font(.system(size: 24))
            }.frame(width: 56, height: 56)
            Button { router.detail = habit } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(habit.name).font(.ui(17, .heavy)).foregroundStyle(Ink.white).lineLimit(1)
                    Text(slipped ? "Slipped today. Tomorrow is day one." : "Best: \(store.bestClean(habit)) days").font(.ui(12, .medium)).foregroundStyle(slipped ? Ink.red : Ink.dim)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(days)").font(.num(24)).foregroundStyle(Ink.lime)
                Text(days == 1 ? "day clean" : "days clean").font(.ui(10, .heavy)).foregroundStyle(Ink.dim)
            }
        }
        .tile(padding: 12)
        .contextMenu {
            Button(role: slipped ? nil : .destructive) { if slipped { store.toggle(habit, Day.today) } else { confirm = true } } label: {
                Label(slipped ? "Undo today's slip" : "I slipped today", systemImage: slipped ? "arrow.uturn.backward" : "exclamationmark.circle")
            }
            Button { router.editing = habit } label: { Label("Edit", systemImage: "pencil") }
        }
        .confirmationDialog("Log a slip?", isPresented: $confirm, titleVisibility: .visible) {
            Button("I slipped today", role: .destructive) { store.toggle(habit, Day.today) }
        } message: { Text("The \(days)-day count starts again. Your best stays on record.") }
    }
}

/// Today's prompt when a chain broke and can still be saved.
struct RescueBanner: View {
    @Environment(Router.self) private var router
    let rescue: Rescue
    var body: some View {
        Button { router.rescue = rescue } label: {
            HStack(spacing: 12) {
                Image(systemName: "bandage.fill").font(.system(size: 15, weight: .black)).foregroundStyle(Ink.bg)
                    .frame(width: 36, height: 36).background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Ink.patch))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your \(rescue.lost)-day \(rescue.habit.name) chain broke").font(.ui(14, .heavy)).foregroundStyle(Ink.white).lineLimit(1)
                    Text("Missed \(Day.date(rescue.day).formatted(.dateTime.weekday(.wide))). There's still time to save it.").font(.ui(12, .medium)).foregroundStyle(Ink.grey)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .black)).foregroundStyle(Ink.patch)
            }.tile(padding: 12)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Ink.patch.opacity(0.5)))
        }.buttonStyle(Press())
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
        let builds = store.active.filter { $0.kind == .build }
        Page {
            HStack(alignment: .lastTextBaseline) {
                Text("Week.").font(.big(30)).foregroundStyle(Ink.white)
                Spacer()
                Button {
                    // Free keeps the last 90 days: this week and the twelve before it.
                    if !purchases.unlocked && store.weekOffset <= -12 { router.paywall = .history } else { store.weekOffset -= 1 }
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
                ForEach(builds) { h in
                    HStack(spacing: 4) {
                        HStack(spacing: 6) { Text(h.emoji).font(.system(size: 13)); Text(h.name).font(.ui(12, .heavy)).foregroundStyle(Ink.white).lineLimit(2) }.frame(width: 92, alignment: .leading)
                        ForEach(days, id: \.self) { d in WeekCell(habit: h, day: d) }
                    }.padding(.vertical, 5)
                }
            }.tile(padding: 12)
            HStack(spacing: 14) {
                legend(Ink.lime, "done"); legend(Ink.ice, "frozen"); legend(Ink.patch, "repaired"); legend(Ink.hole, "missed")
            }.padding(.horizontal, 4)
            Text("Tap a square to log or undo a day. Hold a missed one to freeze or repair it.").font(.ui(12, .medium)).foregroundStyle(Ink.dim)
        }
    }
    func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) { RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 10, height: 10); Text(t).font(.ui(11, .heavy)).foregroundStyle(Ink.dim) }
    }
}

struct WeekCell: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(Purchases.self) private var purchases
    let habit: Habit
    let day: String
    var body: some View {
        let sq = store.square(habit, day), dn = store.done(habit, day)
        let na = !store.due(habit, day) || day > Day.today
        let missed: Bool = { if case .hole = sq { return true }; return false }()
        Button { if day <= Day.today { withAnimation(.snappy) { store.toggle(habit, day) } } } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(dn ? Ink.lime : sq.stitched || isFrozenOrRepaired(sq) ? sq.color : Ink.bg2)
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(dn ? Ink.lime : day == Day.today ? Ink.dim : Ink.line2))
                if dn { Image(systemName: "checkmark").font(.system(size: 13, weight: .black)).foregroundStyle(Ink.bg) }
                else if store.isFrozen(habit, day) { Image(systemName: "snowflake").font(.system(size: 12, weight: .black)).foregroundStyle(Ink.bg) }
                else if store.isRepaired(habit, day) { Image(systemName: "bandage.fill").font(.system(size: 11, weight: .black)).foregroundStyle(Ink.bg) }
                else if case .partial(let p) = sq { Text("\(Int(p * 100))").font(.num(10, .bold)).foregroundStyle(Ink.white) }
            }.frame(height: 36).opacity(na && !dn ? 0.3 : 1)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if missed {
                let left = store.freezesLeft(pro: purchases.unlocked)
                Button { store.freeze(habit, day) } label: { Label(left > 0 ? "Use a freeze (\(left) left this month)" : "No freezes left this month", systemImage: "snowflake") }.disabled(left == 0)
                Button { router.rescue = Rescue(habit: habit, day: day, lost: store.run(habit, from: Day.add(day, -1))) } label: { Label("Streak Repair…", systemImage: "bandage.fill") }
            }
            if store.isFrozen(habit, day) {
                Button { store.frozen[day]?.removeAll { $0 == habit.id }; store.save() } label: { Label("Remove freeze", systemImage: "xmark") }
            }
            if day <= Day.today { Button { router.noting = habit } label: { Label("Note", systemImage: "note.text") } }
        }
    }
    func isFrozenOrRepaired(_ s: Square) -> Bool { if case .frozen = s { return true }; if case .repaired = s { return true }; return false }
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
            if !purchases.unlocked && !store.active.isEmpty {
                Button { router.paywall = .history } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill").font(.system(size: 14, weight: .black)).foregroundStyle(Ink.bg)
                            .frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Ink.lime))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Free shows the last 90 days").font(.ui(14, .heavy)).foregroundStyle(Ink.white)
                            Text("Unlock the whole quilt, back to day one.").font(.ui(12, .medium)).foregroundStyle(Ink.grey)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .black)).foregroundStyle(Ink.lime)
                    }.tile(padding: 12)
                }.buttonStyle(.plain)
            }
            ForEach(store.active) { h in
                Button { router.detail = h } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(h.emoji + " " + h.name).font(.ui(15, .heavy)).foregroundStyle(Ink.white).lineLimit(1)
                            Spacer()
                            Text(h.kind == .quit ? "\(store.cleanDays(h)) clean · best \(store.bestClean(h))" : "\(store.total(h)) done · best \(store.best(h)) · \(Int((store.rate(h, days: 365) * 100).rounded()))%").font(.num(11, .bold)).foregroundStyle(Ink.dim)
                        }
                        Quilt(habit: h, locked: !purchases.unlocked)
                    }.tile()
                }.buttonStyle(Press())
            }
            if store.active.isEmpty { Text("Add a habit and this fills in day by day.").font(.ui(14, .medium)).foregroundStyle(Ink.grey).tile() }
        }
    }
}

/// Weeks of squares, one row per weekday, stitched like a quilt.
struct Quilt: View {
    @Environment(Store.self) private var store
    let habit: Habit
    var locked = false
    var weeks = 26
    /// The quilt's width: the screen less the page and tile padding.
    var width: CGFloat = UIScreen.main.bounds.width - 64
    var body: some View {
        let end = Day.today
        let start = Day.add(Day.weekStart(end), -(weeks - 1) * 7)
        Canvas { ctx, size in
            let cols = Double(weeks)
            let cell = (size.width - 22) / cols
            let s = max(2, cell - (weeks > 30 ? 2 : 3))
            var d = start
            var col = 0
            while d <= end {
                let r = Day.dow(d)
                let x = 22 + Double(col) * cell, y = Double(r) * cell
                let rect = CGRect(x: x, y: y, width: s, height: s)
                let hidden = locked && Day.diff(d, end) >= Purchases.freeHistoryDays
                let sq = store.square(habit, d)
                ctx.fill(Path(roundedRect: rect, cornerRadius: s * 0.22), with: .color(hidden ? Ink.line.opacity(0.5) : sq.color))
                if !hidden && sq.stitched && s > 6 {
                    // Stitches: a little cross on done days, the quilt look.
                    var p = Path()
                    p.move(to: CGPoint(x: rect.minX + 2, y: rect.minY + 2)); p.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.maxY - 2))
                    ctx.stroke(p, with: .color(Ink.lime3.opacity(0.6)), lineWidth: 1)
                }
                if r == 6 { col += 1 }
                d = Day.add(d, 1)
            }
            for (i, n) in ["M", "W", "F", "S"].enumerated() {
                let row = [0, 2, 4, 6][i]
                ctx.draw(Text(n).font(.ui(9, .heavy)).foregroundStyle(Ink.dim), at: CGPoint(x: 8, y: Double(row) * cell + s / 2))
            }
        }
        .frame(width: width, height: 7 * ((width - 22) / Double(weeks)))
    }
}

// MARK: Stats

struct StatsView: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(Purchases.self) private var purchases
    var body: some View {
        let hs = store.active.filter { $0.kind == .build }
        let avg30 = hs.isEmpty ? 0 : hs.reduce(0) { $0 + store.rate($1, days: 30) } / Double(hs.count)
        let bestS = hs.map { store.best($0) }.max() ?? 0
        let wd = store.weekdayRates()
        let bestDay = wd.enumerated().max { $0.element < $1.element }
        Page {
            Text("Stats.").font(.big(30)).foregroundStyle(Ink.white).padding(.top, 14)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                stat("\(store.totalDone)", "check-ins, all time")
                stat("\(Int((avg30 * 100).rounded()))%", "completion, 30 days")
                stat("\(bestS)", "longest chain ever")
                stat("\(store.perfectDays(30))", "perfect days in 30")
            }
            HStack(spacing: 10) {
                Image(systemName: "snowflake").font(.system(size: 15, weight: .black)).foregroundStyle(Ink.ice)
                Text("\(store.freezesLeft(pro: purchases.unlocked)) freeze\(store.freezesLeft(pro: purchases.unlocked) == 1 ? "" : "s") left this month").font(.ui(13, .heavy)).foregroundStyle(Ink.white)
                Spacer()
                if store.repairCredits > 0 {
                    Image(systemName: "bandage.fill").font(.system(size: 13, weight: .black)).foregroundStyle(Ink.patch)
                    Text("\(store.repairCredits) repair\(store.repairCredits == 1 ? "" : "s")").font(.ui(13, .heavy)).foregroundStyle(Ink.white)
                }
            }.tile(padding: 14)
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("Per habit")
                ForEach(store.active) { h in
                    Button { router.detail = h } label: {
                        HStack(spacing: 10) {
                            Text(h.emoji).font(.system(size: 16))
                            Text(h.name).font(.ui(13, .heavy)).foregroundStyle(Ink.white).lineLimit(1)
                            Spacer()
                            col("\(store.streak(h))", h.kind == .quit ? "clean" : "now"); col("\(store.best(h))", "best"); col("\(Int((store.rate(h, days: 30) * 100).rounded()))%", "30d"); col(h.kind == .quit ? "–" : "\(store.total(h))", "total")
                        }.padding(.vertical, 6).contentShape(Rectangle())
                    }.buttonStyle(.plain)
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
                if let b = bestDay, b.element > 0, let w = wd.enumerated().filter({ $0.element > 0 }).min(by: { $0.element < $1.element }), w.offset != b.offset {
                    Text("You're strongest on \(Day.names[b.offset])s and slip most on \(Day.names[w.offset])s. Make \(Day.names[w.offset]) the easy day.").font(.ui(12, .medium)).foregroundStyle(Ink.grey)
                }
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
    @State private var confirmDelete = false
    let isNew: Bool
    static let emojis = ["📖", "🏃", "💧", "🧘", "💪", "🥗", "😴", "✍️", "🎸", "🧹", "💊", "🚭", "🌱", "🧠", "📵", "🦷", "🚶", "🎯", "🧺", "☀️",
                         "🛏️", "🍎", "🚴", "🏊", "📚", "🎨", "💻", "🙏", "🍺", "🍬", "☕️", "🧴", "🐕", "💰", "📞", "🌙", "🧗", "🎹", "🗣️", "❤️"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(isNew ? "New habit." : "Edit habit.").font(.big(26)).foregroundStyle(Ink.white).padding(.top, 22)
                Picker("", selection: $habit.kind) { Text("Build a habit").tag(Kind.build); Text("Quit a habit").tag(Kind.quit) }.pickerStyle(.segmented)
                TextField(habit.kind == .quit ? "No smoking" : "Read 20 pages", text: $habit.name).font(.ui(20, .heavy)).foregroundStyle(Ink.white).padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Ink.card))
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("Icon")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 10), spacing: 6) {
                        ForEach(HabitEditor.emojis, id: \.self) { e in
                            Button { habit.emoji = e } label: { Text(e).font(.system(size: 20)).frame(height: 34).frame(maxWidth: .infinity).background(RoundedRectangle(cornerRadius: 8).fill(habit.emoji == e ? Ink.lime.opacity(0.25) : .clear)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(habit.emoji == e ? Ink.lime : .clear)) }.buttonStyle(.plain)
                        }
                    }
                }
                if habit.kind == .quit {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow("Clean since")
                        DatePicker("Clean since", selection: Binding(get: { Day.date(habit.start) }, set: { habit.start = Day.key($0) }), in: ...Date.now, displayedComponents: .date)
                            .labelsHidden().tint(Ink.lime)
                        Text("Chain counts the days since. Log a slip from Today if it happens; your best stays on record.").font(.ui(12, .medium)).foregroundStyle(Ink.dim)
                    }
                } else {
                    buildSections
                }
                Spacer(minLength: 10)
                HStack(spacing: 8) {
                    if !isNew {
                        GreyButton(title: habit.archived ? "Restore" : "Archive", icon: "archivebox") { habit.archived.toggle(); commit() }
                        GreyButton(title: "Delete", icon: "trash") { confirmDelete = true }
                    }
                    LimeButton(title: "Save") { commit() }
                }
            }.padding(18)
        }
        .sheet(item: $paywall) { r in Paywall(reason: r).presentationBackground(Ink.bg).presentationDetents([.large]) }
        .confirmationDialog("Delete \(habit.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete habit and its history", role: .destructive) {
                store.habits.removeAll { $0.id == habit.id }
                for k in store.log.keys { store.log[k]?.removeAll { $0 == habit.id } }
                store.save(); dismiss()
            }
        } message: { Text("Archive keeps the history and hides the habit. Delete removes both.") }
    }

    @ViewBuilder private var buildSections: some View {
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
            Eyebrow("Time of day")
            Picker("", selection: $habit.part) { ForEach(Part.allCases, id: \.self) { p in Text(p.title).tag(p) } }.pickerStyle(.segmented)
        }
        VStack(alignment: .leading, spacing: 10) {
            HStack { Eyebrow("Amount"); if !purchases.unlocked { ProTag() } }
            Toggle(isOn: Binding(get: { habit.target > 1 || habit.health != nil }, set: { on in
                if on && !purchases.unlocked { paywall = .amounts; return }
                if on { habit.target = 8; habit.unit = habit.unit.isEmpty ? "times" : habit.unit } else { habit.target = 1; habit.health = nil }
            })) { Text("Count toward a target").font(.ui(14, .semibold)).foregroundStyle(Ink.white) }.tint(Ink.lime)
            if habit.isAmount {
                if habit.health == nil {
                    HStack {
                        Stepper("Target \(habit.target)", value: $habit.target, in: 2...100_000, step: habit.target >= 1000 ? 500 : habit.target >= 100 ? 10 : 1).font(.ui(14, .semibold)).foregroundStyle(Ink.white)
                    }
                    HStack(spacing: 8) {
                        TextField("glasses", text: $habit.unit).font(.ui(15, .heavy)).foregroundStyle(Ink.white).padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Ink.card))
                        Stepper("+\(habit.step) a tap", value: $habit.step, in: 1...max(1, habit.target)).font(.ui(13, .semibold)).foregroundStyle(Ink.grey)
                    }
                }
                if Health.available {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Fill it from Apple Health").font(.ui(13, .heavy)).foregroundStyle(Ink.grey)
                        Picker("", selection: Binding(get: { habit.health }, set: { m in
                            habit.health = m
                            if let m { habit.target = m.defaultTarget; habit.unit = m.unit; habit.step = max(1, m.defaultTarget / 10); Task { _ = await Health.authorize([m]) } }
                        })) {
                            Text("Off").tag(HealthMetric?.none)
                            ForEach(HealthMetric.allCases) { m in Text(m.title).tag(HealthMetric?.some(m)) }
                        }.pickerStyle(.menu).tint(Ink.lime)
                        if let m = habit.health {
                            Stepper("\(habit.target.formatted()) \(m.unit) a day", value: $habit.target, in: 1...100_000, step: m == .steps ? 500 : m == .workouts ? 1 : 5).font(.ui(14, .semibold)).foregroundStyle(Ink.white)
                            Text("Chain reads today's \(m.title.lowercased()) from Health when you open it and ticks this off once you reach the target. Nothing is written to Health and nothing leaves your phone.").font(.ui(11, .medium)).foregroundStyle(Ink.dim)
                        }
                    }
                }
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            HStack { Eyebrow("Reminder"); if !purchases.unlocked { ProTag() } }
            Toggle(isOn: Binding(get: { habit.remind }, set: { on in
                // Per-habit reminders come with Unlimited; the free daily check-in lives in Settings.
                if on && !purchases.unlocked { paywall = .reminders } else { habit.remind = on; if on { Task { _ = await Reminders.ask() } } }
            })) { Text("Remind me at a set time").font(.ui(14, .semibold)).foregroundStyle(Ink.white) }.tint(Ink.lime)
            if habit.remind {
                DatePicker("At", selection: Binding(get: {
                    Day.cal.date(bySettingHour: habit.remindHour, minute: habit.remindMinute, second: 0, of: .now) ?? .now
                }, set: { d in
                    habit.remindHour = Day.cal.component(.hour, from: d); habit.remindMinute = Day.cal.component(.minute, from: d)
                }), displayedComponents: .hourAndMinute).font(.ui(14, .semibold)).foregroundStyle(Ink.white).tint(Ink.lime)
                Text("It has a Done button, and stays quiet on days you've already done it.").font(.ui(11, .medium)).foregroundStyle(Ink.dim)
            }
        }
        if !isNew {
            VStack(alignment: .leading, spacing: 8) {
                HStack { Eyebrow("Pause"); if !purchases.unlocked { ProTag() } }
                if let p = habit.pauses.last(where: { $0.to >= Day.today }) {
                    HStack {
                        Text("Paused \(Day.date(p.from).formatted(.dateTime.month(.abbreviated).day())) – \(Day.date(p.to).formatted(.dateTime.month(.abbreviated).day()))").font(.ui(14, .heavy)).foregroundStyle(Ink.ice)
                        Spacer()
                        GreyButton(title: "End pause") { habit.pauses.removeAll { $0 == p } }
                    }
                } else {
                    HStack(spacing: 8) {
                        ForEach([3, 7, 14], id: \.self) { n in
                            GreyButton(title: "\(n) days", icon: "airplane") {
                                if !purchases.unlocked { paywall = .pause; return }
                                habit.pauses.append(Pause(from: Day.today, to: Day.add(Day.today, n - 1)))
                            }
                        }
                    }
                    Text("Away or ill? Paused days aren't due, so the chain waits for you.").font(.ui(11, .medium)).foregroundStyle(Ink.dim)
                }
            }
        }
    }

    func commit() {
        let name = habit.name.trimmingCharacters(in: .whitespaces); guard !name.isEmpty else { return }
        var h = habit; h.name = name
        if h.kind == .quit { h.remind = false; h.target = 1; h.health = nil }
        if let i = store.habits.firstIndex(where: { $0.id == h.id }) { store.habits[i] = h } else { store.habits.append(h) }
        store.save()
        if h.health != nil { Task { await Health.sync(store) } }
        dismiss()
    }
}
