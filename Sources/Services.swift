import AppIntents
import HealthKit
import SwiftUI
import UserNotifications
import WidgetKit

// MARK: Reminders

/// Reminders are scheduled a week ahead, one notification per habit per day, so a habit already
/// done today can have today's taken back. Free gets one daily check-in; Unlimited gets a time per
/// habit, with a Done button on the notification.
enum Reminders {
    static let habitCategory = "CHAIN_HABIT"
    static let doneAction = "DONE"
    static var checkInOn: Bool {
        get { UserDefaults.standard.bool(forKey: "chain.checkin") }
        set { UserDefaults.standard.set(newValue, forKey: "chain.checkin") }
    }
    static var checkInMinutes: Int {
        get { UserDefaults.standard.object(forKey: "chain.checkinAt") as? Int ?? 20 * 60 }
        set { UserDefaults.standard.set(newValue, forKey: "chain.checkinAt") }
    }

    static func registerCategories() {
        let done = UNNotificationAction(identifier: doneAction, title: "Done ✓", options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: habitCategory, actions: [done], intentIdentifiers: [], options: [])
        ])
    }

    static func ask() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func sync(_ store: Store, pro: Bool) {
        let c = UNUserNotificationCenter.current()
        // Per-habit reminders are Unlimited; ones set up before 1.2 (when they shipped with the unlock) keep working.
        let habits = store.active.filter { $0.remind && $0.kind == .build }
        let wantHabits = pro ? habits : []
        guard !wantHabits.isEmpty || checkInOn else { c.removeAllPendingNotificationRequests(); return }
        let days = max(2, min(7, 60 / max(1, wantHabits.count + (checkInOn ? 1 : 0))))
        let now = Date.now
        var requests: [UNNotificationRequest] = []
        for offset in 0..<days {
            let k = Day.add(Day.today, offset)
            let base = Day.date(k)
            for h in wantHabits where store.due(h, k) {
                if offset == 0 && store.satisfiedToday(h) { continue }
                guard let fire = Day.cal.date(bySettingHour: h.remindHour, minute: h.remindMinute, second: 0, of: base), fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = h.emoji + " " + h.name
                let s = store.streak(h)
                content.body = h.target > 1 ? "\(h.target.formatted()) \(h.unit) today. " + (s > 0 ? "Keep the \(s)-day chain." : "Start a chain.") : s > 0 ? "Keep the \(s)-day chain." : "Start a chain today."
                content.sound = .default
                content.categoryIdentifier = habitCategory
                content.userInfo = ["habit": h.id.uuidString, "day": k]
                requests.append(UNNotificationRequest(identifier: "chain-\(h.id)-\(k)", content: content,
                                                      trigger: UNCalendarNotificationTrigger(dateMatching: Day.cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)))
            }
            if checkInOn {
                let due = store.dueToday
                let left = offset == 0 ? due.filter { !store.satisfiedToday($0) } : store.active.filter { store.due($0, k) }
                if left.isEmpty { continue }
                guard let fire = Day.cal.date(bySettingHour: checkInMinutes / 60, minute: checkInMinutes % 60, second: 0, of: base), fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Chain"
                content.body = offset == 0
                    ? "\(left.count) left today: " + left.prefix(3).map { $0.emoji + " " + $0.name }.joined(separator: ", ") + (left.count > 3 ? "…" : "")
                    : "\(left.count) habit\(left.count == 1 ? "" : "s") today. Keep the chain."
                content.sound = .default
                requests.append(UNNotificationRequest(identifier: "chain-checkin-\(k)", content: content,
                                                      trigger: UNCalendarNotificationTrigger(dateMatching: Day.cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)))
            }
        }
        c.removeAllPendingNotificationRequests()
        for r in requests { c.add(r) }
    }
}

/// The notification Done button, and banners while the app is open.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Reminders.registerCategories()
        AppDelegate.styleSegments()
        return true
    }
    /// Segmented pickers in the accent, with dark text on the chosen segment so it reads.
    static func styleSegments() {
        let a = UISegmentedControl.appearance()
        a.selectedSegmentTintColor = UIColor(Ink.lime)
        a.backgroundColor = UIColor(Ink.card)
        a.setTitleTextAttributes([.foregroundColor: UIColor(Ink.bg), .font: UIFont.systemFont(ofSize: 13, weight: .heavy)], for: .selected)
        a.setTitleTextAttributes([.foregroundColor: UIColor(Ink.grey), .font: UIFont.systemFont(ofSize: 13, weight: .semibold)], for: .normal)
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == Reminders.doneAction,
              let id = response.notification.request.content.userInfo["habit"] as? String,
              let day = response.notification.request.content.userInfo["day"] as? String else { return }
        let s = Store(demo: false)
        guard let h = s.habits.first(where: { $0.id.uuidString == id }) else { return }
        s.markDone(h, day)
        s.saveNow()
        await MainActor.run {
            WidgetCenter.shared.reloadAllTimelines()
            NotificationCenter.default.post(name: .chainExternalChange, object: nil)
        }
    }
}

// MARK: Apple Health

/// Read-only. Today's steps, exercise minutes, mindful minutes and workouts, compared with a habit's target.
/// Nothing is written to Health and nothing leaves the phone.
@MainActor
enum Health {
    static let store = HKHealthStore()
    static var available: Bool { HKHealthStore.isHealthDataAvailable() }

    static func type(_ m: HealthMetric) -> HKObjectType {
        switch m {
        case .steps: return HKQuantityType(.stepCount)
        case .exercise: return HKQuantityType(.appleExerciseTime)
        case .mindful: return HKCategoryType(.mindfulSession)
        case .workouts: return HKObjectType.workoutType()
        }
    }

    static func authorize(_ metrics: [HealthMetric]) async -> Bool {
        guard available, !metrics.isEmpty else { return false }
        do { try await store.requestAuthorization(toShare: [], read: Set(metrics.map(type))); return true } catch { return false }
    }

    static func today(_ m: HealthMetric) async -> Double {
        let start = Calendar.current.startOfDay(for: .now)
        let p = HKQuery.predicateForSamples(withStart: start, end: .now)
        do {
            switch m {
            case .steps, .exercise:
                let t = HKQuantityType(m == .steps ? .stepCount : .appleExerciseTime)
                let d = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: t, predicate: p), options: .cumulativeSum)
                return try await d.result(for: store)?.sumQuantity()?.doubleValue(for: m == .steps ? .count() : .minute()) ?? 0
            case .mindful:
                let d = HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.mindfulSession), predicate: p)], sortDescriptors: [])
                return try await d.result(for: store).reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) / 60 }
            case .workouts:
                let d = HKSampleQueryDescriptor(predicates: [.workout(p)], sortDescriptors: [])
                return Double(try await d.result(for: store).count)
            }
        } catch { return 0 }
    }

    /// Bring every Health-linked habit up to date for today. Never lowers a count the person entered.
    static func sync(_ s: Store) async {
        let linked = s.active.filter { $0.health != nil }
        guard available, !linked.isEmpty else { return }
        var changed = false
        for h in linked {
            guard let m = h.health else { continue }
            let v = Int(await today(m))
            if v > s.count(h, Day.today) { s.setCount(h, Day.today, v); changed = true }
        }
        if changed { s.save() }
    }
}

// MARK: iCloud

/// A copy of the whole file in iCloud key-value storage: a new phone picks every chain back up.
/// Last writer wins, which is right for one person on one phone at a time.
enum CloudSync {
    static let kv = NSUbiquitousKeyValueStore.default
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "chain.icloud") }
        set { UserDefaults.standard.set(newValue, forKey: "chain.icloud") }
    }
    static var lastBackup: Date? {
        let t = kv.double(forKey: "stamp"); return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }
    static func push(_ s: Store) {
        guard enabled, let d = s.encoded(), d.count < 950_000 else { return }
        kv.set(d, forKey: "disk")
        kv.set(s.stamp, forKey: "stamp")
        kv.synchronize()
    }
    /// True when the copy in iCloud was newer and has replaced what is on the phone.
    @discardableResult static func pull(_ s: Store) -> Bool {
        guard enabled else { return false }
        kv.synchronize()
        guard let d = kv.data(forKey: "disk"), kv.double(forKey: "stamp") > s.stamp + 1, s.apply(d) else { return false }
        s.saveNow()
        return true
    }
}

// MARK: Siri and Shortcuts

struct HabitEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Habit"
    static var defaultQuery = HabitQuery()
    let id: UUID
    let name: String
    let emoji: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(emoji) \(name)") }
}

struct HabitQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [HabitEntity] {
        Store(demo: false).active.filter { identifiers.contains($0.id) }.map { HabitEntity(id: $0.id, name: $0.name, emoji: $0.emoji) }
    }
    func suggestedEntities() async throws -> [HabitEntity] {
        Store(demo: false).active.filter { $0.kind == .build }.map { HabitEntity(id: $0.id, name: $0.name, emoji: $0.emoji) }
    }
}

struct LogHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a habit"
    static var description = IntentDescription("Ticks a Chain habit off for today.")
    @Parameter(title: "Habit") var habit: HabitEntity
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let s = Store(demo: false)
        guard let h = s.habits.first(where: { $0.id == habit.id }) else { return .result(dialog: "That habit isn't in Chain any more.") }
        s.markDone(h, Day.today)
        s.saveNow()
        await MainActor.run {
            WidgetCenter.shared.reloadAllTimelines()
            NotificationCenter.default.post(name: .chainExternalChange, object: nil)
        }
        let n = s.streak(h)
        return .result(dialog: "\(h.emoji) \(h.name) is done. \(n > 1 ? "That's a \(n)-day chain." : "Chain started.")")
    }
}

struct ChainShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogHabitIntent(), phrases: [
            "Log \(\.$habit) in \(.applicationName)",
            "Check off \(\.$habit) in \(.applicationName)",
            "Log a habit in \(.applicationName)",
        ], shortTitle: "Log a habit", systemImageName: "checkmark.square.fill")
    }
}
