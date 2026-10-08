import StoreKit
import SwiftUI
import WidgetKit

/// Chain is free for three habits and the last 90 days of the quilt. Chain Unlimited, one
/// non-consumable, lifts the limits and adds the power features. On top of that, small
/// 99-cent buys: Streak Repair (consumable), five colour themes and the celebration pack.
/// People who paid for the app before it went free get Unlimited, forever.
@MainActor
@Observable
final class Purchases {
    nonisolated static let productID = "com.mattbusel.chainhabits.unlimited"
    nonisolated static let repairID = "com.mattbusel.chainhabits.repair"
    nonisolated static let celebrateID = "com.mattbusel.chainhabits.celebrate"
    nonisolated static func themeID(_ id: String) -> String { "com.mattbusel.chainhabits.theme." + id }
    nonisolated static var allIDs: [String] {
        [productID, repairID, celebrateID] + Palette.all.filter { $0.id != "lime" }.map { themeID($0.id) }
    }
    nonisolated static let freeHabits = 3
    nonisolated static let freeHistoryDays = 90
    /// Build 1 was the only paid-era build. Anything a person first downloaded before the
    /// cutoff (the day the price went to free, plus a day for the price change to reach
    /// every storefront) came from the paid app.
    nonisolated static let firstFreeBuild = 2
    nonisolated static let paidCutoff = ISO8601DateFormatter().date(from: "2026-09-26T17:00:00Z")!

    private(set) var owned: Set<String>
    private(set) var grandfathered: Bool
    private(set) var products: [String: Product] = [:]
    var busy: String? = nil
    var message: String?
    /// Called with each Streak Repair that clears, so the store can bank it.
    var onRepair: (() -> Void)?
    private var updates: Task<Void, Never>?
    private let demo: Bool

    var unlocked: Bool { owned.contains(Purchases.productID) || grandfathered }
    var product: Product? { products[Purchases.productID] }
    var priceText: String { price(Purchases.productID, fallback: "$9.99") }
    func price(_ id: String, fallback: String = "$0.99") -> String { products[id]?.displayPrice ?? (demo ? fallback : "…") }
    func ownsTheme(_ id: String) -> Bool { id == "lime" || owned.contains(Purchases.themeID(id)) }
    var ownsCelebrations: Bool { owned.contains(Purchases.celebrateID) }

    init(demo: Bool) {
        self.demo = demo
        let d = UserDefaults.standard
        let a = ProcessInfo.processInfo.arguments
        if demo {
            // The store screenshots show the whole app; the paywall and shop shots show it locked.
            owned = a.contains("paywall") ? [] : a.contains("themes") ? [Purchases.productID, Purchases.themeID("ember")] : Set(Purchases.allIDs)
            grandfathered = false
        } else {
            owned = Set((d.array(forKey: "chain.owned") as? [String]) ?? (d.bool(forKey: "chain.unlimited") ? [Purchases.productID] : []))
            grandfathered = d.bool(forKey: "chain.grandfathered")
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
        guard !demo, products.count < Purchases.allIDs.count else { return }
        if let ps = try? await Product.products(for: Purchases.allIDs) {
            for p in ps { products[p.id] = p }
        }
    }
    /// Kept for the old call sites.
    func loadProduct() async { await loadProducts() }

    func refreshEntitlement() async {
        var has: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.revocationDate == nil, t.productType == .nonConsumable { has.insert(t.productID) }
        }
        // currentEntitlements works offline from StoreKit's own cache, so this is the truth,
        // including a refund taking an unlock away.
        owned = has
        let d = UserDefaults.standard
        d.set(Array(has), forKey: "chain.owned")
        d.set(has.contains(Purchases.productID), forKey: "chain.unlimited")
        publish()
    }

    private func publish() {
        Shared.unlocked = unlocked
        // A theme the person no longer owns (refund) falls back to lime.
        if !ownsTheme(Shared.theme) { Palette.apply("lime") }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Bank a Streak Repair once per transaction, however many times StoreKit reports it.
    private func credit(_ t: StoreKit.Transaction) {
        guard t.productID == Purchases.repairID, t.revocationDate == nil else { return }
        let d = UserDefaults.standard
        var seen = Set((d.array(forKey: "chain.credited") as? [String]) ?? [])
        guard !seen.contains(String(t.id)) else { return }
        seen.insert(String(t.id))
        d.set(Array(seen), forKey: "chain.credited")
        onRepair?()
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
            if id == Purchases.repairID { onRepair?() } else { owned.insert(id) }
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
    case habits, history, reminders, settings, widgets, amounts, health, pause, sync, export
    var id: String { rawValue }
    var headline: String {
        switch self {
        case .habits: return "Three chains are free.\nKeep adding."
        case .history: return "See the whole\nquilt."
        case .reminders: return "A nudge per habit,\nat its own time."
        case .settings: return "Chain\nUnlimited."
        case .widgets: return "Your whole day\non the Home Screen."
        case .amounts: return "Count it,\nnot just tick it."
        case .health: return "Let Apple Health\ntick it for you."
        case .pause: return "Holidays don't\nbreak chains."
        case .sync: return "Never lose\na chain."
        case .export: return "Your data,\nyour spreadsheet."
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
        case .settings: return ""
        }
    }
}

// MARK: Paywall

struct Paywall: View {
    @Environment(Purchases.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    let reason: Locked
    @State private var lit = 0
    private let cols = 14, rows = 7

    private let perks: [(String, String, String)] = [
        ("infinity", "Unlimited habits", "Free keeps three. Unlimited keeps as many chains as you can carry."),
        ("rectangle.3.group.fill", "Every widget", "Today and Quilt on the Home Screen, the next habit on the Lock Screen. Tick from any of them."),
        ("bell.fill", "Reminders per habit", "Each habit at its own time, with a Done button right on the notification. Quiet once it's done."),
        ("drop.fill", "Amounts and targets", "8 glasses, 20 pages, 10,000 steps. The quilt fills as you go."),
        ("heart.fill", "Apple Health", "Steps, exercise, mindful minutes and workouts tick their habits off by themselves."),
        ("snowflake", "Three freezes a month, and pauses", "A sick day or a holiday doesn't snap a chain."),
        ("square.grid.3x3.fill", "The whole quilt", "Every day back to the first one, not just the last 90."),
        ("icloud.fill", "iCloud backup and CSV export", "A new phone keeps every chain. A spreadsheet of every day, any time."),
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CharcoalBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    quilt.padding(.top, 54)
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow("Chain Unlimited")
                        Text(reason.headline).font(.big(34)).foregroundStyle(Ink.white).fixedSize(horizontal: false, vertical: true)
                        Text("One payment. No subscription, ever.").font(.ui(15, .medium)).foregroundStyle(Ink.grey)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(perks, id: \.0) { p in perk(p.0, p.1, p.2, p.0 == reason.hot) }
                    }.tile(padding: 18)
                    if purchases.unlocked {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(Ink.lime)
                            Text(purchases.grandfathered ? "You bought Chain before it went free, so everything is yours. Thank you." : "Unlocked. Thank you for keeping Chain going.")
                                .font(.ui(14, .heavy)).foregroundStyle(Ink.white)
                        }.tile(padding: 16)
                        LimeButton(title: "Done") { dismiss() }
                    } else {
                        Button { Task { if await purchases.buy(Purchases.productID) { dismiss() } } } label: {
                            HStack(spacing: 10) {
                                if purchases.busy == Purchases.productID { ProgressView().tint(Ink.bg) }
                                Text("Unlock for \(purchases.priceText)").font(.ui(17, .heavy))
                                Text("once").font(.ui(12, .heavy)).padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(Ink.bg.opacity(0.15)))
                            }
                            .foregroundStyle(Ink.bg).frame(maxWidth: .infinity).padding(.vertical, 17)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Ink.lime).shadow(color: Ink.lime.opacity(0.4), radius: 18, y: 6))
                        }.buttonStyle(Press()).disabled(purchases.busy != nil)
                        Button { Task { await purchases.restore() } } label: {
                            Text("Restore purchase").font(.ui(14, .heavy)).foregroundStyle(Ink.grey).frame(maxWidth: .infinity).padding(.vertical, 6)
                        }.buttonStyle(.plain).disabled(purchases.busy != nil)
                    }
                    if let m = purchases.message {
                        Text(m).font(.ui(13, .medium)).foregroundStyle(Ink.amber).frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
                    }
                    Text("Your habits and history stay yours either way. Nothing is ever locked away or deleted.")
                        .font(.ui(12, .medium)).foregroundStyle(Ink.dim).frame(maxWidth: .infinity).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 22).padding(.bottom, 30)
            }
            CloseButton { dismiss() }.padding(.trailing, 18).padding(.top, 16)
        }
        .task {
            await purchases.loadProducts()
            // The quilt stitches itself in, one square at a time.
            for i in 1...(cols * rows) { try? await Task.sleep(for: .milliseconds(14)); withAnimation(.snappy(duration: 0.2)) { lit = i } }
        }
        .onChange(of: purchases.unlocked) { _, on in if on { lit = cols * rows } }
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
    }
}
