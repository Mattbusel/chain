import StoreKit
import SwiftUI
import WidgetKit

/// Chain is free for three habits and the last 90 days of the quilt. Chain Unlimited, one
/// non-consumable, lifts the limits and adds the power features, for good. Chain Plus, an
/// auto-renewable subscription (monthly or yearly), is everything in Unlimited plus the things
/// that keep coming: three Streak Repairs every month, five freezes a month, every theme and
/// celebration, the challenge library and Insights. On top of that, small 99-cent buys: Streak
/// Repair and Freeze Pack (consumables), five colour themes and the celebration pack.
/// People who paid for the app before it went free get Unlimited, forever.
@MainActor
@Observable
final class Purchases {
    nonisolated static let productID = "com.mattbusel.chainhabits.unlimited"
    nonisolated static let repairID = "com.mattbusel.chainhabits.repair"
    nonisolated static let freezesID = "com.mattbusel.chainhabits.freezes"
    nonisolated static let celebrateID = "com.mattbusel.chainhabits.celebrate"
    nonisolated static let plusMonthly = "com.mattbusel.chainhabits.plus.monthly"
    nonisolated static let plusYearly = "com.mattbusel.chainhabits.plus.yearly"
    nonisolated static let plusIDs = [plusYearly, plusMonthly]
    nonisolated static func themeID(_ id: String) -> String { "com.mattbusel.chainhabits.theme." + id }
    nonisolated static var allIDs: [String] {
        [productID, repairID, freezesID, celebrateID] + plusIDs + Palette.all.filter { $0.id != "lime" }.map { themeID($0.id) }
    }
    nonisolated static let freeHabits = 3
    nonisolated static let freeHistoryDays = 90
    /// Freezes in a Freeze Pack.
    nonisolated static let packFreezes = 3
    nonisolated static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    nonisolated static let privacy = URL(string: "https://tensorust.com/apps/chain/privacy/")!
    /// Build 1 was the only paid-era build. Anything a person first downloaded before the
    /// cutoff (the day the price went to free, plus a day for the price change to reach
    /// every storefront) came from the paid app.
    nonisolated static let firstFreeBuild = 2
    nonisolated static let paidCutoff = ISO8601DateFormatter().date(from: "2026-09-26T17:00:00Z")!

    private(set) var owned: Set<String>
    private(set) var grandfathered: Bool
    private(set) var products: [String: Product] = [:]
    /// Chain Plus is active right now (a current, unrevoked, unexpired subscription).
    private(set) var plus: Bool
    private(set) var plusProductID: String? = nil
    private(set) var plusRenewal: Date? = nil
    /// The 1-week free trial on yearly is for people who have never subscribed in this group.
    private(set) var trialEligible = true
    var busy: String? = nil
    var message: String?
    /// Called with each Streak Repair that clears, so the store can bank it.
    var onRepair: (() -> Void)?
    /// Called with each Freeze Pack that clears.
    var onFreezes: (() -> Void)?
    /// Called whenever Plus is found active: the store tops up the month's repairs once a month.
    var onPlus: (() -> Void)?
    private var updates: Task<Void, Never>?
    private let demo: Bool

    /// Owns Chain Unlimited for good (bought, or grandfathered from the paid era).
    var ownsUnlimited: Bool { owned.contains(Purchases.productID) || grandfathered }
    /// Everything Unlimited opens. Plus includes all of it.
    var unlocked: Bool { ownsUnlimited || plus }
    /// Freezes per month: 1 free, 3 with Unlimited, 5 with Plus.
    var freezeAllowance: Int { plus ? 5 : unlocked ? 3 : 1 }
    var product: Product? { products[Purchases.productID] }
    var priceText: String { price(Purchases.productID, fallback: "$4.99") }
    func price(_ id: String, fallback: String? = nil) -> String {
        let f = fallback ?? (id == Purchases.plusMonthly ? "$2.99" : id == Purchases.plusYearly ? "$14.99" : "$0.99")
        return products[id]?.displayPrice ?? (demo ? f : "…")
    }
    func ownsTheme(_ id: String) -> Bool { id == "lime" || plus || owned.contains(Purchases.themeID(id)) }
    var ownsCelebrations: Bool { plus || owned.contains(Purchases.celebrateID) }

    /// "year" or "month", from the product when it has loaded.
    func period(_ id: String) -> String {
        guard let p = products[id]?.subscription?.subscriptionPeriod else { return id == Purchases.plusYearly ? "year" : "month" }
        switch p.unit {
        case .day: return p.value == 1 ? "day" : "\(p.value) days"
        case .week: return p.value == 1 ? "week" : "\(p.value) weeks"
        case .month: return p.value == 1 ? "month" : "\(p.value) months"
        case .year: return p.value == 1 ? "year" : "\(p.value) years"
        @unknown default: return "period"
        }
    }
    /// The yearly intro offer in words, e.g. "1 week free". Nil when there is none or the person used it.
    var trialText: String? {
        guard trialEligible else { return nil }
        guard let o = products[Purchases.plusYearly]?.subscription?.introductoryOffer else { return demo ? "1 week free" : nil }
        guard o.paymentMode == .freeTrial else { return nil }
        let p = o.period
        let unit: String
        switch p.unit {
        case .day: unit = p.value == 7 ? "1 week" : "\(p.value) day" + (p.value == 1 ? "" : "s")
        case .week: unit = "\(p.value) week" + (p.value == 1 ? "" : "s")
        case .month: unit = "\(p.value) month" + (p.value == 1 ? "" : "s")
        case .year: unit = "\(p.value) year" + (p.value == 1 ? "" : "s")
        @unknown default: unit = "\(p.value)"
        }
        return unit + " free"
    }
    /// How much yearly saves over twelve months of monthly, as a whole percent.
    var yearlySaving: Int? {
        guard let m = products[Purchases.plusMonthly]?.price, let y = products[Purchases.plusYearly]?.price, m > 0 else { return demo ? 58 : nil }
        let monthly = NSDecimalNumber(decimal: m).doubleValue * 12, yearly = NSDecimalNumber(decimal: y).doubleValue
        let s = Int(((1 - yearly / monthly) * 100).rounded(.down))
        return s > 0 ? s : nil
    }

    init(demo: Bool) {
        self.demo = demo
        let d = UserDefaults.standard
        let a = ProcessInfo.processInfo.arguments
        if demo {
            // The store screenshots show the whole app on Plus; the paywall shot shows it locked.
            // The App Review recording shows the free app, so every door to the paywall is visible.
            let locked = a.contains("paywall") || a.contains("-demoAutoplay")
            owned = locked ? [] : Set(Purchases.allIDs.filter { !Purchases.plusIDs.contains($0) })
            plus = !locked
            grandfathered = false
        } else {
            owned = Set((d.array(forKey: "chain.owned") as? [String]) ?? (d.bool(forKey: "chain.unlimited") ? [Purchases.productID] : []))
            grandfathered = d.bool(forKey: "chain.grandfathered")
            plus = d.bool(forKey: "chain.plus")
        }
        if !demo { Shared.unlocked = unlocked }
    }

    func start() {
        guard !demo, updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let t) = result { self.credit(t); await t.finish() }
                await self.refreshEntitlement()
            }
        }
        // A purchase started from the App Store product page (promoted in-app purchases).
        Task { [weak self] in
            for await intent in PurchaseIntent.intents {
                guard let self else { return }
                self.products[intent.product.id] = intent.product
                _ = await self.buy(intent.product.id)
            }
        }
        Task {
            await refreshEntitlement()
            await checkPaidEra()
            await loadProducts()
            // A repair bought on a flaky connection may never have been finished.
            for await result in Transaction.unfinished {
                if case .verified(let t) = result { credit(t); await t.finish() }
            }
        }
    }

    func loadProducts() async {
        guard !demo else { return }
        if products.count < Purchases.allIDs.count, let ps = try? await Product.products(for: Purchases.allIDs) {
            for p in ps { products[p.id] = p }
        }
        if let sub = products[Purchases.plusYearly]?.subscription {
            trialEligible = await sub.isEligibleForIntroOffer
        }
    }
    /// Kept for the old call sites.
    func loadProduct() async { await loadProducts() }

    func refreshEntitlement() async {
        var has: Set<String> = []
        var sub: StoreKit.Transaction? = nil
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil else { continue }
            switch t.productType {
            case .nonConsumable:
                has.insert(t.productID)
            case .autoRenewable:
                if Purchases.plusIDs.contains(t.productID), (t.expirationDate ?? .distantFuture) > .now { sub = t }
            default:
                break
            }
        }
        // currentEntitlements works offline from StoreKit's own cache, so this is the truth,
        // including a refund taking an unlock away and a lapsed subscription.
        owned = has
        plus = sub != nil
        plusProductID = sub?.productID
        plusRenewal = sub?.expirationDate
        let d = UserDefaults.standard
        d.set(Array(has), forKey: "chain.owned")
        d.set(has.contains(Purchases.productID), forKey: "chain.unlimited")
        d.set(plus, forKey: "chain.plus")
        publish()
        if plus { onPlus?() }
    }

    private func publish() {
        Shared.unlocked = unlocked
        // A theme the person no longer owns (refund, lapsed Plus) falls back to lime.
        if !ownsTheme(Shared.theme) { Palette.apply("lime") }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Bank a consumable once per transaction, however many times StoreKit reports it.
    private func credit(_ t: StoreKit.Transaction) {
        guard t.productID == Purchases.repairID || t.productID == Purchases.freezesID, t.revocationDate == nil else { return }
        let d = UserDefaults.standard
        var seen = Set((d.array(forKey: "chain.credited") as? [String]) ?? [])
        guard !seen.contains(String(t.id)) else { return }
        seen.insert(String(t.id))
        d.set(Array(seen), forKey: "chain.credited")
        if t.productID == Purchases.repairID { onRepair?() } else { onFreezes?() }
    }

    /// Unlock for anyone whose first download of Chain was the paid app.
    /// Only in production: sandbox and Xcode report "1.0" for everyone, and App Review
    /// has to see the real paywall.
    func checkPaidEra() async {
        guard !grandfathered, let result = try? await AppTransaction.shared,
              case .verified(let app) = result, app.environment == .production else { return }
        let build = Int(app.originalAppVersion.split(separator: ".").first ?? "") ?? Int.max
        if build < Purchases.firstFreeBuild && app.originalPurchaseDate < Purchases.paidCutoff {
            grandfathered = true
            UserDefaults.standard.set(true, forKey: "chain.grandfathered")
            publish()
        }
    }

    func buy() async { _ = await buy(Purchases.productID) }

    /// True when the thing bought is now in hand.
    @discardableResult
    func buy(_ id: String) async -> Bool {
        message = nil
        if demo {
            if id == Purchases.repairID { onRepair?() }
            else if id == Purchases.freezesID { onFreezes?() }
            else if Purchases.plusIDs.contains(id) { plus = true }
            else { owned.insert(id) }
            return true
        }
        await loadProducts()
        guard let product = products[id] else { message = "The App Store did not answer. Check your connection and try again."; return false }
        busy = id; defer { busy = nil }
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let t) = result else {
                    message = "Apple could not confirm that purchase. Nothing was charged twice; try Restore."
                    return false
                }
                credit(t)
                await t.finish()
                await refreshEntitlement()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                return true
            case .pending:
                message = "Waiting for approval. If Ask to Buy is on, a parent can approve it, and Chain picks it up by itself when they do."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = "The purchase did not go through: \(error.localizedDescription)"
        }
        return false
    }

    func restore() async {
        message = nil
        busy = "restore"; defer { busy = nil }
        do { try await AppStore.sync() } catch {
            if case StoreKitError.userCancelled = error { return }
            message = "Could not reach the App Store to restore. Try again when you are online."
            return
        }
        await refreshEntitlement()
        await checkPaidEra()
        message = unlocked || !owned.isEmpty ? "Restored. Everything you bought is back." : "No Chain purchases were found for this Apple ID."
    }
}

enum Locked: String, Identifiable {
    case habits, history, reminders, settings, widgets, amounts, health, pause, sync, export, plus, insights, challenges
    var id: String { rawValue }
    var headline: String {
        switch self {
        case .habits: return "Three chains are free.\nKeep adding."
        case .history: return "See the whole\nquilt."
        case .reminders: return "A nudge per habit,\nat its own time."
        case .settings: return "Go further\nwith Chain."
        case .widgets: return "Your whole day\non the Home Screen."
        case .amounts: return "Count it,\nnot just tick it."
        case .health: return "Let Apple Health\ntick it for you."
        case .pause: return "Holidays don't\nbreak chains."
        case .sync: return "Never lose\na chain."
        case .export: return "Your data,\nyour spreadsheet."
        case .plus: return "Every month,\nsomething new."
        case .insights: return "See what makes\nyour habits stick."
        case .challenges: return "A new challenge,\nwhenever you want one."
        }
    }
    var hot: String {
        switch self {
        case .habits: return "infinity"
        case .history: return "square.grid.3x3.fill"
        case .reminders: return "bell.fill"
        case .widgets: return "rectangle.3.group.fill"
        case .amounts: return "drop.fill"
        case .health: return "heart.fill"
        case .pause: return "airplane"
        case .sync: return "icloud.fill"
        case .export: return "tablecells"
        case .plus: return "bandage.fill"
        case .insights: return "chart.xyaxis.line"
        case .challenges: return "flag.checkered"
        case .settings: return ""
        }
    }
    /// Reasons only Plus answers.
    var plusOnly: Bool { self == .plus || self == .insights || self == .challenges }
}

// MARK: Paywall

struct Paywall: View {
    @Environment(Purchases.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    let reason: Locked
    @State private var lit = 0
    @State private var plan = Purchases.plusYearly
    @State private var redeem = false
    @State private var manage = false
    private let cols = 14, rows = 7

    private let plusPerks: [(String, String, String)] = [
        ("bandage.fill", "3 Streak Repairs every month", "Topped up at the start of each month you're subscribed. Unused ones carry over."),
        ("snowflake", "5 freezes a month", "More room for sick days. Unlimited has three, free has one."),
        ("flag.checkered", "Every challenge, any time", "The whole library of 30-day challenges, not just the month's headline one."),
        ("chart.xyaxis.line", "Insights", "This month against last, the habits that lift each other, and when each chain hits its next milestone."),
        ("paintpalette.fill", "Every theme and celebration", "All five themes with their app icons, plus fireworks and confetti."),
    ]
    private let perks: [(String, String, String)] = [
        ("infinity", "Unlimited habits", "Free keeps three. Keep as many chains as you can carry."),
        ("rectangle.3.group.fill", "Every widget", "Today and Quilt on the Home Screen, the next habit on the Lock Screen. Tick from any of them."),
        ("bell.fill", "Reminders per habit", "Each habit at its own time, with a Done button right on the notification. Quiet once it's done."),
        ("drop.fill", "Amounts and targets", "8 glasses, 20 pages, 10,000 steps. The quilt fills as you go."),
        ("heart.fill", "Apple Health", "Steps, exercise, mindful minutes and workouts tick their habits off by themselves."),
        ("airplane", "Three freezes a month, and pauses", "A sick day or a holiday doesn't snap a chain."),
        ("square.grid.3x3.fill", "The whole quilt", "Every day back to the first one, not just the last 90."),
        ("icloud.fill", "iCloud backup and CSV export", "A new phone keeps every chain. A spreadsheet of every day, any time."),
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CharcoalBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    quilt.padding(.top, 54)
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(purchases.plus ? "Chain Plus" : reason.plusOnly || purchases.ownsUnlimited ? "Chain Plus" : "Go further")
                        Text(reason.headline).font(.big(34)).foregroundStyle(Ink.white).fixedSize(horizontal: false, vertical: true)
                        Text(subline).font(.ui(15, .medium)).foregroundStyle(Ink.grey).fixedSize(horizontal: false, vertical: true)
                    }
                    if purchases.plus {
                        subscribed
                    } else {
                        plans
                        buyButton
                        disclosure
                    }
                    if let m = purchases.message {
                        Text(m).font(.ui(13, .medium)).foregroundStyle(Ink.amber).frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { Eyebrow("Plus adds"); Spacer(); PlusTag() }
                        ForEach(plusPerks, id: \.1) { p in perk(p.0, p.1, p.2, p.0 == reason.hot) }
                    }.tile(padding: 18)
                    VStack(alignment: .leading, spacing: 14) {
                        Eyebrow(purchases.ownsUnlimited ? "Yours already, for good" : "In Unlimited and Plus")
                        ForEach(perks, id: \.1) { p in perk(p.0, p.1, p.2, p.0 == reason.hot && !reason.plusOnly) }
                    }.tile(padding: 18)
                    links
                    Text("Your habits and history stay yours either way. Nothing is ever locked away or deleted.")
                        .font(.ui(12, .medium)).foregroundStyle(Ink.dim).frame(maxWidth: .infinity).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 22).padding(.bottom, 30)
            }
            CloseButton { dismiss() }.padding(.trailing, 18).padding(.top, 16)
        }
        .offerCodeRedemption(isPresented: $redeem) { _ in Task { await purchases.refreshEntitlement() } }
        .manageSubscriptionsSheet(isPresented: $manage)
        .task {
            await purchases.loadProducts()
            // The quilt stitches itself in, one square at a time.
            for i in 1...(cols * rows) { try? await Task.sleep(for: .milliseconds(14)); withAnimation(.snappy(duration: 0.2)) { lit = i } }
        }
        .onChange(of: purchases.unlocked) { _, on in if on { lit = cols * rows } }
    }

    private var subline: String {
        if purchases.plus { return "You're on Chain Plus. Thank you for keeping Chain going." }
        if purchases.ownsUnlimited {
            return purchases.grandfathered ? "You bought Chain before it went free, so Unlimited is yours for good. Plus adds the monthly extras on top." : "Unlimited is yours for good. Plus adds the monthly extras on top."
        }
        return "Plus, by the month or the year. Or Unlimited, once."
    }

    private var subscribed: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(Ink.lime)
                VStack(alignment: .leading, spacing: 2) {
                    Text(purchases.plusProductID == Purchases.plusMonthly ? "Plus, monthly" : "Plus, yearly").font(.ui(15, .heavy)).foregroundStyle(Ink.white)
                    if let d = purchases.plusRenewal { Text("Renews or ends \(d.formatted(date: .abbreviated, time: .omitted))").font(.ui(12, .medium)).foregroundStyle(Ink.grey) }
                }
            }
            GreyButton(title: "Manage subscription", icon: "gearshape") { manage = true }
            LimeButton(title: "Done") { dismiss() }
        }.tile(padding: 16)
    }

    private var plans: some View {
        VStack(spacing: 10) {
            planCard(Purchases.plusYearly, title: "Plus, yearly",
                     detail: purchases.trialText.map { "\($0), then \(purchases.price(Purchases.plusYearly)) a year" } ?? "\(purchases.price(Purchases.plusYearly)) a year",
                     badge: purchases.yearlySaving.map { "SAVE \($0)%" })
            planCard(Purchases.plusMonthly, title: "Plus, monthly", detail: "\(purchases.price(Purchases.plusMonthly)) a month", badge: nil)
            if !purchases.ownsUnlimited {
                planCard(Purchases.productID, title: "Unlimited, one time", detail: "\(purchases.priceText) once. No renewals, yours for good.", badge: nil)
            }
        }
    }

    private func planCard(_ id: String, title: String, detail: String, badge: String?) -> some View {
        let on = plan == id
        return Button { withAnimation(.snappy(duration: 0.2)) { plan = id }; UISelectionFeedbackGenerator().selectionChanged() } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle").font(.system(size: 20, weight: .bold)).foregroundStyle(on ? Ink.lime : Ink.dim)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.ui(16, .heavy)).foregroundStyle(Ink.white)
                    Text(detail).font(.ui(12.5, .medium)).foregroundStyle(Ink.grey).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                if let badge { Text(badge).font(.ui(10, .black)).tracking(0.8).foregroundStyle(Ink.bg).padding(.horizontal, 7).padding(.vertical, 4).background(Capsule().fill(Ink.lime)) }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? Ink.lime.opacity(0.10) : Ink.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(on ? Ink.lime : Ink.line, lineWidth: on ? 2 : 1))
        }
        .buttonStyle(Press())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var ctaTitle: String {
        switch plan {
        case Purchases.plusYearly: return purchases.trialText.map { "Start \($0)" } ?? "Subscribe for \(purchases.price(Purchases.plusYearly)) a year"
        case Purchases.plusMonthly: return "Subscribe for \(purchases.price(Purchases.plusMonthly)) a month"
        default: return "Unlock for \(purchases.priceText) once"
        }
    }

    private var buyButton: some View {
        Button { Task { if await purchases.buy(plan) { dismiss() } } } label: {
            HStack(spacing: 10) {
                if purchases.busy == plan { ProgressView().tint(Ink.bg) }
                Text(ctaTitle).font(.ui(17, .heavy))
            }
            .foregroundStyle(Ink.bg).frame(maxWidth: .infinity).padding(.vertical, 17)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Ink.lime).shadow(color: Ink.lime.opacity(0.4), radius: 18, y: 6))
        }.buttonStyle(Press()).disabled(purchases.busy != nil)
    }

    /// What Apple asks every subscription screen to say, right by the button.
    private var disclosure: some View {
        let text: String
        if plan == Purchases.productID {
            text = "One payment of \(purchases.priceText), charged to your Apple ID. It never renews."
        } else {
            let price = purchases.price(plan), per = purchases.period(plan)
            let trial = plan == Purchases.plusYearly ? purchases.trialText.map { "After the \($0.replacingOccurrences(of: " free", with: "")) free trial, " } ?? "" : ""
            text = "Chain Plus is an auto-renewing subscription. \(trial)\(price) per \(per) is charged to your Apple ID and renews automatically unless you cancel at least 24 hours before the end of the current period. Cancel any time in your App Store account settings."
        }
        return Text(text).font(.ui(11.5, .medium)).foregroundStyle(Ink.dim).fixedSize(horizontal: false, vertical: true)
    }

    private var links: some View {
        VStack(spacing: 10) {
            HStack(spacing: 18) {
                Button { Task { await purchases.restore() } } label: { Text(purchases.busy == "restore" ? "Restoring…" : "Restore purchases") }
                Button { redeem = true } label: { Text("Redeem code") }
            }
            HStack(spacing: 18) {
                Link("Terms of Use", destination: Purchases.terms)
                Link("Privacy Policy", destination: Purchases.privacy)
            }
        }
        .font(.ui(13, .heavy)).foregroundStyle(Ink.grey).buttonStyle(.plain).frame(maxWidth: .infinity)
        .disabled(purchases.busy != nil)
    }

    private var quilt: some View {
        let holes: Set<Int> = [9, 23, 40, 58, 61, 77, 86]
        return Canvas { ctx, size in
            let cell = size.width / CGFloat(cols), s = cell - 4
            for c in 0..<cols { for r in 0..<rows {
                let i = c * rows + r
                let rect = CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: s, height: s)
                let on = i < lit && !holes.contains(i)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(on ? (c >= cols - 3 ? Ink.lime : Ink.lime2) : Ink.hole))
                if on {
                    var p = Path(); p.move(to: CGPoint(x: rect.minX + 3, y: rect.minY + 3)); p.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.maxY - 3))
                    ctx.stroke(p, with: .color(Ink.lime3.opacity(0.7)), lineWidth: 1.2)
                }
            } }
        }
        .aspectRatio(CGFloat(cols) / CGFloat(rows), contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func perk(_ icon: String, _ title: String, _ detail: String, _ hot: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 15, weight: .black)).foregroundStyle(hot ? Ink.bg : Ink.lime)
                .frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hot ? Ink.lime : Ink.lime.opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.ui(15, .heavy)).foregroundStyle(Ink.white)
                Text(detail).font(.ui(12.5, .medium)).foregroundStyle(Ink.grey).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
