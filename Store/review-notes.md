# App Review notes

---

No account, login or network connection is required.

WHAT IS NEW IN 1.1: Chain is now free to download, with one non-consumable in-app purchase, "Chain Unlimited" (com.mattbusel.chainhabits.unlimited). The free app keeps three habits and shows the last 30 days of each habit's year quilt; every other feature is free. Chain Unlimited unlocks unlimited habits, the full year quilt and reminders. It is a one-time purchase, not a subscription.

HOW TO SEE AND TEST THE PURCHASE (sandbox): on a fresh install, add three habits, then tap "New habit" a fourth time: the Chain Unlimited sheet opens with the price, "Unlock", and "Restore purchase". The same sheet opens from the "3 of 3 free habits" line on Today, from the lock banner on the Year tab, from the Reminder switch in the habit editor, and from the gear icon (Settings) on Today, which also has Restore purchase. After buying, the limits lift at once and the sheet says it is unlocked. People who paid for Chain before 1.1 are unlocked automatically (checked with AppTransaction in production only; sandbox always shows the paywall).

HOW TO USE: Tap "New habit" on the Today tab, name it, choose how often, save. Tap the habit's tile to log it for today; hold the row to edit. The Week tab logs any day; Year shows the heat map; Stats the numbers. The optional daily reminder asks for notification permission only when switched on in the editor.

PRIVACY: no data is collected. Everything is stored in a JSON file in the app's Documents folder on the device. Local notifications only, and only if the user turns a reminder on.

2. PURPOSE AND TARGET AUDIENCE
Chain is a personal habit tracker: log daily, weekday or N-per-week habits, see streaks and a year heat map per habit. Free with an optional one-time unlock. General audience; rated 4+.

3. SETUP AND ACCESS
No setup, login or credentials. A new install starts empty; add one habit and tap it.

4. EXTERNAL SERVICES, TOOLS AND PLATFORMS
None. No network requests, analytics, advertising or third-party frameworks. Built with SwiftUI, Foundation, StoreKit 2 (the one in-app purchase) and UserNotifications (local reminders only).

5. REGIONAL DIFFERENCES
None.

6. REGULATED INDUSTRY / PROTECTED MATERIAL
Not applicable. All art, text and code are my own work.
