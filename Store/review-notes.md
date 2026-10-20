# App Review notes

---

No account, login or network connection is required.

WHAT IS NEW IN 1.3: monthly challenges (Today > the month's challenge card), milestone sheets at 7/30/100/365-day streaks, Insights (Stats > Insights), an iOS 18 Control Center control "Log Next Habit" (ControlWidget in the widget extension), a Best Chain widget, an inline Lock Screen widget, App Shortcuts ("How's my chain in Chain", "Log next habit in Chain"), TipKit tips, the chainhabits:// URL scheme used by our In-App Events (chainhabits://challenge opens the challenges sheet), a new auto-renewable subscription group (Chain Plus) and a Freeze Pack consumable.

IN-APP PURCHASES (StoreKit 2, all optional; Restore purchases and Redeem code are on the paywall and in Settings):
- Chain Plus (NEW auto-renewable subscription group, monthly $2.99 and yearly $14.99 with a 1-week free trial): the paywall opens from Settings (gear on Today) > See plans, the "Go unlimited" line under the habits on Today (after three habits), Stats > Insights > See Insights with Plus, and the lock icons in the challenge Library (Today > challenge card). It shows both plans and the one-time Unlimited option with price, period, trial terms, auto-renewal text, Terms of Use (Apple standard EULA) and Privacy Policy links, Restore purchases and Redeem code. Plus = everything in Unlimited + 3 Streak Repairs added at the start of each subscribed month + 5 freezes a month + every theme and celebration + the whole challenge library + Insights. Once subscribed, Settings shows Manage subscription.
- Chain Unlimited (existing non-consumable, unchanged): add three habits, tap New habit again; also from Settings and the locked controls marked UNLIMITED.
- Freeze Pack, $0.99 consumable (NEW): 3 freezes that never expire. Settings > Streak protection > Freeze Pack, or the rescue sheet when a chain broke and no freezes are left this month.
- Streak Repair, $0.99 consumable: when a chain of 2+ days breaks, Today shows a "chain broke" banner and the rescue sheet opens. Also: Week tab, hold a missed square, Streak Repair.
- Ember, Tide, Bloom, Gold, Violet themes and Celebration Pack ($0.99 each, non-consumable): Settings > Themes, icons and celebrations.

CHALLENGES: the month's challenge (October: Outdoor October, November: No-Scroll November) is open to everyone: Today > challenge card > Join the challenge adds a daily habit until the end of the month; doing it on 4 of 5 days wins a badge. The other challenges in the Library are Chain Plus and run 30 days.

APPLE HEALTH: read-only. In the habit editor, turn on Amount (Unlimited), then "Fill it from Apple Health" and choose Steps, Exercise minutes, Mindful minutes or Workouts. Read permission for that one type; it ticks the habit off at the target. Nothing is written to Health or leaves the device.

WIDGETS: Next Up and Best Chain (small, free), Today (medium/large, Unlimited or Plus), Lock Screen ring and inline (free) and line (Unlimited or Plus), Control Center control Log Next Habit (free, iOS 18).

ICLOUD: off by default; Settings > Back up to iCloud stores one copy in the user's own iCloud key-value store.

REMINDERS: free daily check-in, per-habit times with Unlimited/Plus; permission asked only when turned on.

PRIVACY: no data is collected. No accounts, analytics, ads or third-party SDKs.

AUDIENCE: general, 4+. No setup or credentials. EXTERNAL SERVICES: none besides Apple frameworks: SwiftUI, WidgetKit (incl. ControlWidget), AppIntents, TipKit, StoreKit 2, HealthKit (read-only), UserNotifications (local), NSUbiquitousKeyValueStore (optional backup).

No regional differences. All art, text and code are my own work.
