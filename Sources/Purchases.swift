import StoreKit
import SwiftUI

/// Chain is free for three habits and the last 30 days of the quilt. One non-consumable,
/// Chain Unlimited, lifts both limits and turns on reminders. People who paid for the app
/// before it went free get everything, forever.
@MainActor
@Observable
final class Purchases {
    nonisolated static let productID = "com.mattbusel.chainhabits.unlimited"
    nonisolated static let freeHabits = 3
    nonisolated static let freeHistoryDays = 30
    /// Build 1 was the only paid-era build. Anything a person first downloaded before the
    /// cutoff (the day the price went to free, plus a day for the price change to reach
    /// every storefront) came from the paid app.
    nonisolated static let firstFreeBuild = 2
    nonisolated static let paidCutoff = ISO8601DateFormatter().date(from: "2026-09-26T17:00:00Z")!

    private(set) var purchased: Bool
    private(set) var grandfathered: Bool
    private(set) var product: Product?
    var busy = false
    var message: String?
    private var updates: Task<Void, Never>?
    private let demo: Bool

    var unlocked: Bool { purchased || grandfathered }
    /// Shown before the product loads (no connection yet) and in the screenshot run.
    var priceText: String { product?.displayPrice ?? (demo ? "$4.99" : "…") }

    init(demo: Bool) {
        self.demo = demo
        let d = UserDefaults.standard
        let a = ProcessInfo.processInfo.arguments
        if demo {
            // The store screenshots show the whole app; the paywall shot shows it locked.
            purchased = !a.contains("paywall")
            grandfathered = false
        } else {
            purchased = d.bool(forKey: "chain.unlimited")
            grandfathered = d.bool(forKey: "chain.grandfathered")
        }
    }

    func start() {
        guard !demo, updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let t) = result { await t.finish() }
                await self.refreshEntitlement()
            }
        }
        Task {
            await refreshEntitlement()
            await checkPaidEra()
            await loadProduct()
        }
    }

    func loadProduct() async {
        guard !demo, product == nil else { return }
        product = try? await Product.products(for: [Purchases.productID]).first
    }

    func refreshEntitlement() async {
        var has = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Purchases.productID, t.revocationDate == nil { has = true }
        }
        // currentEntitlements works offline from StoreKit's own cache, so this is the truth,
        // including a refund taking the unlock away.
        purchased = has
        UserDefaults.standard.set(has, forKey: "chain.unlimited")
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
        }
    }

    func buy() async {
        message = nil
        await loadProduct()
        guard let product else { message = "The App Store did not answer. Check your connection and try again."; return }
        busy = true; defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                if case .verified(let t) = result {
                    await t.finish()
                    await refreshEntitlement()
                    if unlocked { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                } else {
                    message = "Apple could not confirm that purchase. Nothing was charged twice; try Restore."
                }
            case .pending:
                message = "Waiting for approval. If Ask to Buy is on, a parent can approve it, and Chain unlocks by itself when they do."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = "The purchase did not go through: \(error.localizedDescription)"
        }
    }

    func restore() async {
        message = nil
        busy = true; defer { busy = false }
        do { try await AppStore.sync() } catch {
            if case StoreKitError.userCancelled = error { return }
            message = "Could not reach the App Store to restore. Try again when you are online."
            return
        }
        await refreshEntitlement()
        await checkPaidEra()
        message = unlocked ? "Restored. Everything is unlocked." : "No Chain Unlimited purchase was found for this Apple ID."
    }
}

enum Locked: String, Identifiable {
    case habits, history, reminders, settings
    var id: String { rawValue }
    var headline: String {
        switch self {
        case .habits: return "Three chains are free.\nKeep adding."
        case .history: return "See the whole\nquilt."
        case .reminders: return "A nudge at\nyour hour."
        case .settings: return "Chain\nUnlimited."
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
                        perk("infinity", "Unlimited habits", "Free keeps three. Unlimited keeps as many chains as you can carry.", reason == .habits)
                        perk("square.grid.3x3.fill", "The whole year in the quilt", "Every day back to the first one, not just the last 30.", reason == .history)
                        perk("bell.fill", "Reminders", "A nudge at the hour you pick, per habit.", reason == .reminders)
                        perk("heart.fill", "Pays for the app", "No ads, no account, no data leaving your phone. Ever.", false)
                    }.tile(padding: 18)
                    if purchases.unlocked {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(Ink.lime)
                            Text(purchases.grandfathered ? "You bought Chain before it went free, so everything is yours. Thank you." : "Unlocked. Thank you for keeping Chain going.")
                                .font(.ui(14, .heavy)).foregroundStyle(Ink.white)
                        }.tile(padding: 16)
                        LimeButton(title: "Done") { dismiss() }
                    } else {
                        Button { Task { await purchases.buy() } } label: {
                            HStack(spacing: 10) {
                                if purchases.busy { ProgressView().tint(Ink.bg) }
                                Text("Unlock for \(purchases.priceText)").font(.ui(17, .heavy))
                                Text("once").font(.ui(12, .heavy)).padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(Ink.bg.opacity(0.15)))
                            }
                            .foregroundStyle(Ink.bg).frame(maxWidth: .infinity).padding(.vertical, 17)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Ink.lime).shadow(color: Ink.lime.opacity(0.4), radius: 18, y: 6))
                        }.buttonStyle(.plain).disabled(purchases.busy)
                        Button { Task { await purchases.restore() } } label: {
                            Text("Restore purchase").font(.ui(14, .heavy)).foregroundStyle(Ink.grey).frame(maxWidth: .infinity).padding(.vertical, 6)
                        }.buttonStyle(.plain).disabled(purchases.busy)
                    }
                    if let m = purchases.message {
                        Text(m).font(.ui(13, .medium)).foregroundStyle(Ink.amber).frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
                    }
                    Text("Your habits and history stay yours either way. Nothing is ever locked away or deleted.")
                        .font(.ui(12, .medium)).foregroundStyle(Ink.dim).frame(maxWidth: .infinity).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 22).padding(.bottom, 30)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .black)).foregroundStyle(Ink.grey)
                    .frame(width: 36, height: 36).background(Circle().fill(Ink.card2)).overlay(Circle().strokeBorder(Ink.line2))
            }.buttonStyle(.plain).padding(.trailing, 18).padding(.top, 16).accessibilityLabel("Close")
        }
        .task {
            await purchases.loadProduct()
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

// MARK: Settings

struct SettingsSheet: View {
    @Environment(Purchases.self) private var purchases
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings.").font(.big(26)).foregroundStyle(Ink.white).padding(.top, 22)
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow("Chain Unlimited")
                    HStack {
                        Image(systemName: purchases.unlocked ? "checkmark.seal.fill" : "lock.fill").foregroundStyle(purchases.unlocked ? Ink.lime : Ink.grey)
                        Text(purchases.unlocked ? (purchases.grandfathered ? "Unlocked: you bought Chain before it went free" : "Unlocked. Thank you.") : "Free: three habits, the last 30 days of the quilt")
                            .font(.ui(14, .heavy)).foregroundStyle(Ink.white)
                    }
                    if !purchases.unlocked {
                        LimeButton(title: "Unlock for \(purchases.priceText), once", icon: "infinity") { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { router.paywall = .settings } }
                    }
                    GreyButton(title: purchases.busy ? "Restoring…" : "Restore purchase", icon: "arrow.clockwise") { Task { await purchases.restore() } }
                    if let m = purchases.message { Text(m).font(.ui(12, .medium)).foregroundStyle(Ink.amber) }
                }.tile()
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow("About")
                    Text("Chain keeps everything on this iPhone. No account, no ads, no tracking.").font(.ui(13, .medium)).foregroundStyle(Ink.grey)
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")").font(.num(12, .bold)).foregroundStyle(Ink.dim)
                }.tile()
            }.padding(18)
        }
        .task { await purchases.loadProduct() }
    }
}
