import StoreKit
import SwiftUI
import TipKit
import WidgetKit

/// Screenshot, review-recording and app-preview runs: fixed demo data, no prompts.
enum DemoRun {
    static let args = ProcessInfo.processInfo.arguments
    static var on: Bool { args.contains("-shot") || args.contains("-demoAutoplay") || args.contains("-preview") }
}

@main
struct ChainApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var phase
    @State private var store: Store
    @State private var router = Router()
    @State private var purchases: Purchases
    init() {
        let a = ProcessInfo.processInfo.arguments
        let demo = DemoRun.on
        if demo { Palette.current = Palette.byID(a.contains("ember") ? "ember" : "lime") }
        let s = Store(demo: demo)
        if a.contains("rescue") { Demo.breakYesterday(s) }
        _store = State(initialValue: s)
        _purchases = State(initialValue: Purchases(demo: demo))
        if !demo {
            TypeScale.on = true
            try? Tips.configure([.displayFrequency(.immediate)])
        }
    }
    var body: some Scene {
        WindowGroup {
            RootView().environment(store).environment(router).environment(purchases).preferredColorScheme(.dark).tint(Ink.lime)
                .onAppear {
                    purchases.onRepair = { [store] in store.repairCredits += 1; store.save() }
                    purchases.onFreezes = { [store] in store.bonusFreezes += Purchases.packFreezes; store.save() }
                    purchases.onPlus = { [store] in store.refillPlus() }
                    store.didSave = { [store, purchases] in
                        CloudSync.push(store)
                        WidgetCenter.shared.reloadAllTimelines()
                        Reminders.sync(store, pro: purchases.unlocked)
                    }
                    purchases.start()
                    router.applyShotArgs(store)
                    Autopilot.shared.run(store, router)
                    if !router.demo { ChainShortcuts.updateAppShortcutParameters() }
                }
                .onOpenURL { router.open($0) }
                .onReceive(NotificationCenter.default.publisher(for: .chainExternalChange)) { _ in store.load() }
                .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
                    if CloudSync.pull(store) { WidgetCenter.shared.reloadAllTimelines() }
                }
                .onChange(of: phase) { _, p in
                    guard p == .active, !router.demo else { return }
                    // A widget, Siri or a notification may have written the file while Chain was away.
                    store.load()
                    CloudSync.pull(store)
                    Task {
                        await Health.sync(store)
                        Reminders.sync(store, pro: purchases.unlocked)
                        if let r = store.checkWins().first, router.moment == nil { router.moment = .won(r) }
                        router.checkRescue(store)
                    }
                }
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
    var detail: Habit? = nil
    var paywall: Locked? = nil
    var settings = false
    var shop = false
    var rescue: Rescue? = nil
    var noting: Habit? = nil
    var challenges = false
    var insights = false
    var moment: Moment? = nil
    var celebrating = 0
    var onboarding = false
    var showcase = false
    /// Bumped when the theme changes, so every view redraws in the new colour.
    var themeTick = 0
    let demo = DemoRun.on

    /// The one door for a new habit: free keeps three (the month's challenge habit doesn't count).
    @MainActor func newHabit(_ s: Store, _ p: Purchases) {
        if s.counted.count >= Purchases.freeHabits && !p.unlocked { paywall = .habits } else { creating = true }
    }
    /// chainhabits://challenge, ://plus, ://insights, ://today, ://week, ://year, ://stats, ://new
    func open(_ url: URL) {
        guard url.scheme == "chainhabits" else { return }
        let what = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch what {
        case "challenge", "challenges": tab = .today; challenges = true
        case "plus": paywall = .plus
        case "insights": tab = .stats; insights = true
        case "week": tab = .week
        case "year": tab = .year
        case "stats": tab = .stats
        case "new": creating = true
        default: tab = .today
        }
    }
    /// Offer to save a chain that broke, once per chain and day.
    func checkRescue(_ s: Store) {
        guard rescue == nil, !onboarding else { return }
        let seen = Set(UserDefaults.standard.stringArray(forKey: "chain.rescueSeen") ?? [])
        guard let r = s.rescues().sorted(by: { $0.lost > $1.lost }).first(where: { !seen.contains($0.id) }) else { return }
        UserDefaults.standard.set(Array(seen.union([r.id]).suffix(200)), forKey: "chain.rescueSeen")
        rescue = r
    }
    func applyShotArgs(_ s: Store) {
        let a = ProcessInfo.processInfo.arguments
        if !demo && s.habits.isEmpty && !UserDefaults.standard.bool(forKey: "chain.onboarded") { onboarding = true }
        guard let i = a.firstIndex(of: "-shot"), i + 1 < a.count else { return }
        switch a[i + 1] {
        case "week": tab = .week
        case "year": tab = .year
        case "stats": tab = .stats
        case "edit": editing = s.habits[1]
        case "detail": detail = s.habits[0]
        case "quit": detail = s.habits.first { $0.kind == .quit }
        case "paywall": paywall = .widgets
        case "plus": paywall = .plus
        case "themes": shop = true
        case "settings": settings = true
        case "rescue": rescue = s.rescues().first
        case "onboarding": onboarding = true
        case "widgets": showcase = true
        case "challenges": challenges = true
        case "insights": tab = .stats; insights = true
        case "milestone": moment = .streak(s.habits[0], s.streak(s.habits[0]))
        case "done": for h in s.dueToday where !s.satisfiedToday(h) { s.markDone(h, Day.today) }; celebrating += 1
        default: break
        }
    }
}

struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(Purchases.self) private var purchases
    @Environment(\.requestReview) private var requestReview
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
            Celebration(trigger: router.celebrating, style: purchases.ownsCelebrations ? Celebration.Style.saved : .stitch)
                .allowsHitTesting(false).ignoresSafeArea()
            if router.showcase { WidgetShowcase() }
        }
        .id(router.themeTick)
        .sheet(item: $router.editing) { h in HabitEditor(habit: h, isNew: false).presentationBackground(Ink.bg2).presentationDetents([.large]) }
        .sheet(isPresented: $router.creating) { HabitEditor(habit: Habit(name: "", start: Day.today), isNew: true).presentationBackground(Ink.bg2).presentationDetents([.large]) }
        .sheet(item: $router.detail) { h in HabitDetail(habitID: h.id).presentationBackground(Ink.bg).presentationDetents([.large]) }
        .sheet(item: $router.paywall) { r in Paywall(reason: r).presentationBackground(Ink.bg).presentationDetents([.large]) }
        .sheet(isPresented: $router.settings) { SettingsSheet().presentationBackground(Ink.bg2).presentationDetents([.large]) }
        .sheet(isPresented: $router.shop) { ShopSheet().presentationBackground(Ink.bg).presentationDetents([.large]) }
        .sheet(isPresented: $router.challenges) { ChallengesSheet().presentationBackground(Ink.bg).presentationDetents([.large]) }
        .sheet(isPresented: $router.insights) { InsightsSheet().presentationBackground(Ink.bg).presentationDetents([.large]) }
        .sheet(item: $router.moment, onDismiss: { if !router.demo { ReviewAsk.maybe(requestReview) } }) { m in
            MomentSheet(moment: m).presentationBackground(Ink.bg).presentationDetents([.large])
        }
        .sheet(item: $router.rescue) { r in RescueSheet(rescue: r).presentationBackground(Ink.bg).presentationDetents([.medium, .large]) }
        .sheet(item: $router.noting) { h in NoteSheet(habit: h).presentationBackground(Ink.bg2).presentationDetents([.height(320)]) }
        .fullScreenCover(isPresented: $router.onboarding) { Onboarding() }
        .task {
            if !router.demo {
                await Health.sync(store)
                Reminders.sync(store, pro: purchases.unlocked)
                try? await Task.sleep(for: .seconds(1))
                router.checkRescue(store)
            }
        }
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
