import SwiftUI
import UserNotifications

@main
struct ChainApp: App {
    @State private var store: Store
    @State private var router = Router()
    @State private var purchases: Purchases
    init() {
        let a = ProcessInfo.processInfo.arguments
        let demo = a.contains("-shot") || a.contains("-demoAutoplay")
        _store = State(initialValue: Store(demo: demo))
        _purchases = State(initialValue: Purchases(demo: demo))
    }
    var body: some Scene {
        WindowGroup {
            RootView().environment(store).environment(router).environment(purchases).preferredColorScheme(.dark).tint(Ink.lime)
                .onAppear { purchases.start(); router.applyShotArgs(store); Autopilot.shared.run(store, router) }
        }
    }
}

enum Tab: String, CaseIterable {
    case today = "Today", week = "Week", year = "Year", stats = "Stats"
    var icon: String {
        switch self {
        case .today: return "checkmark.square.fill"
        case .week: return "calendar"
        case .year: return "square.grid.3x3.fill"
        case .stats: return "chart.bar.fill"
        }
    }
}

@Observable
final class Router {
    var tab: Tab = .today
    var editing: Habit? = nil
    var creating = false
    var paywall: Locked? = nil
    var settings = false
    /// The one door for a new habit: free keeps three.
    @MainActor func newHabit(_ s: Store, _ p: Purchases) {
        if s.habits.count >= Purchases.freeHabits && !p.unlocked { paywall = .habits } else { creating = true }
    }
    func applyShotArgs(_ s: Store) {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-shot"), i + 1 < a.count else { return }
        switch a[i + 1] {
        case "week": tab = .week
        case "year": tab = .year
        case "stats": tab = .stats
        case "edit": editing = s.habits.first
        case "paywall": paywall = .habits
        case "done": for h in s.habits where s.due(h, Day.today) && !s.done(h, Day.today) { s.log[Day.today, default: []].append(h.id) }
        default: break
        }
    }
}

struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    var body: some View {
        @Bindable var router = router
        ZStack(alignment: .bottom) {
            CharcoalBackground()
            Group {
                switch router.tab {
                case .today: TodayView()
                case .week: WeekView()
                case .year: YearView()
                case .stats: StatsView()
                }
            }
            QuiltTabBar(selection: $router.tab).padding(.bottom, 2)
        }
        .sheet(item: $router.editing) { h in HabitEditor(habit: h, isNew: false).presentationBackground(Ink.bg2).presentationDetents([.large]) }
        .sheet(isPresented: $router.creating) { HabitEditor(habit: Habit(name: "", start: Day.today), isNew: true).presentationBackground(Ink.bg2).presentationDetents([.large]) }
        .sheet(item: $router.paywall) { r in Paywall(reason: r).presentationBackground(Ink.bg).presentationDetents([.large]) }
        .sheet(isPresented: $router.settings) { SettingsSheet().presentationBackground(Ink.bg2).presentationDetents([.medium, .large]) }
    }
}

struct Page<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) { content }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 110)
        }
    }
}

enum Reminders {
    static func sync(_ store: Store) {
        let c = UNUserNotificationCenter.current()
        c.removeAllPendingNotificationRequests()
        let want = store.habits.filter { $0.remind }
        guard !want.isEmpty else { return }
        c.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            for h in want {
                let content = UNMutableNotificationContent()
                content.title = h.emoji + " " + h.name
                content.body = "Keep the chain."
                var dc = DateComponents(); dc.hour = h.remindHour; dc.minute = 0
                c.add(UNNotificationRequest(identifier: "chain-\(h.id)", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)))
            }
        }
    }
}
