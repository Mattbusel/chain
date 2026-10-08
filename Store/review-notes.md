# App Review notes

---

No account, login or network connection is required.

WHAT IS NEW IN 1.2: Home Screen and Lock Screen widgets (WidgetKit extension; rows are interactive buttons), amount habits, quit habits, Apple Health auto-complete (read-only), freezes, pauses, per-habit reminders with a Done action, notes, Siri/Shortcuts (Log a habit), optional iCloud key-value backup, CSV export, colour themes with alternate app icons, and seven new in-app purchases.

IN-APP PURCHASES (StoreKit 2, all optional, Restore in Settings):
- Chain Unlimited (existing non-consumable): add three habits, tap New habit again; also from the gear (Settings), the Year tab lock banner and the locked controls marked UNLIMITED in the editor.
- Streak Repair, $0.99 consumable: when a chain of 2+ days breaks, Today shows a "chain broke" banner and the rescue sheet opens. It offers a free freeze if one is left this month, then Streak Repair, which patches the missed day. Also: Week tab, hold a missed square, Streak Repair. To see it on a fresh install: add a habit, open Week, tick the two days before yesterday, leave yesterday empty, then relaunch.
- Ember, Tide, Bloom, Gold, Violet themes ($0.99 each, non-consumable) and Celebration Pack ($0.99, non-consumable): Settings > Themes, icons and celebrations. A bought theme recolours the app and widgets and switches the app icon (alternate icons). Lime is free.

APPLE HEALTH: read-only. In the habit editor, turn on Amount (Unlimited), then "Fill it from Apple Health" and choose Steps, Exercise minutes, Mindful minutes or Workouts. Chain asks for read permission for that one type, reads today's total when the app opens, and ticks the habit off at the target. Nothing is written to Health, nothing leaves the device, no Health data is used for advertising.

WIDGETS: Next Up (small, free), Today (medium/large, Unlimited), Lock Screen ring (free) and line (Unlimited). Data is shared with the widget through the app group group.com.mattbusel.chainhabits.

ICLOUD: off by default. Settings > Back up to iCloud (Unlimited) stores one copy of the user's data in their own iCloud key-value store.

REMINDERS: a free daily check-in (Settings, or the last onboarding page) and per-habit times (Unlimited). Permission is only asked when one is turned on.

HOW TO USE: on first launch, pick up to three starter habits. Tap a habit's square to tick it (amount habits add a step per tap). Tap the habit's name for its detail page; hold the row for notes and edit. Week logs any day; Year shows the quilt; Stats the numbers.

PRIVACY: no data is collected. No accounts, analytics, ads or third-party SDKs.

2. PURPOSE AND TARGET AUDIENCE
A personal habit tracker for a general audience, rated 4+. Free with optional one-time purchases; no subscriptions.

3. SETUP AND ACCESS
No setup or credentials.

4. EXTERNAL SERVICES
None besides Apple frameworks: SwiftUI, WidgetKit, AppIntents, StoreKit 2, HealthKit (read-only), UserNotifications (local), NSUbiquitousKeyValueStore (optional backup).

5. REGIONAL DIFFERENCES
None.

6. REGULATED INDUSTRY / PROTECTED MATERIAL
Not applicable. All art, text and code are my own work.
