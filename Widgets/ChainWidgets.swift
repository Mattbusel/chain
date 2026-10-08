import SwiftUI
import WidgetKit

@main
struct ChainWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextUpWidget()
        TodayWidget()
        LockWidget()
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let snap: Snapshot
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, snap: .placeholder) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let real = Snapshot.load()
        // The gallery preview shows a full day rather than an empty list on a fresh install.
        completion(Entry(date: .now, snap: context.isPreview && real.due == 0 ? .placeholder : real))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        completion(Timeline(entries: [Entry(date: .now, snap: Snapshot.load())], policy: .after(midnight)))
    }
}

/// Free: the next habit and one tap to tick it.
struct NextUpWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "nextup", provider: Provider()) { e in
            NextUpView(snap: e.snap).containerBackground(Ink.bg, for: .widget)
        }
        .configurationDisplayName("Next up")
        .description("The next habit due today. Tap the square to tick it off.")
        .supportedFamilies([.systemSmall])
    }
}

/// Chain Unlimited: the whole day, every row a button.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "today", provider: Provider()) { e in
            TodayFamilyView(snap: e.snap).containerBackground(Ink.bg, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Every habit due today, checkable right from your Home Screen. Large adds twelve weeks of the quilt.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TodayFamilyView: View {
    @Environment(\.widgetFamily) private var family
    let snap: Snapshot
    var body: some View {
        if !snap.unlocked { LockedWidgetView() }
        else if family == .systemLarge { TodayListView(snap: snap, limit: 7, large: true) }
        else { TodayListView(snap: snap, limit: 4) }
    }
}

/// Lock Screen: the ring is free, the line with the next habit comes with Unlimited.
struct LockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "lock", provider: Provider()) { e in
            LockFamilyView(snap: e.snap).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Lock Screen")
        .description("Today's count on your Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct LockFamilyView: View {
    @Environment(\.widgetFamily) private var family
    let snap: Snapshot
    var body: some View {
        if family == .accessoryCircular { LockCircularView(snap: snap) }
        else if snap.unlocked { LockRectView(snap: snap) }
        else { Text("Chain Unlimited unlocks this widget").font(.ui(12, .semibold)) }
    }
}
