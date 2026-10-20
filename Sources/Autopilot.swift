import SwiftUI

/// Drives the real screens for the App Review recording (-demoAutoplay) and the App Store
/// preview video (-preview, about 28 seconds).
@Observable
final class Autopilot {
    static let shared = Autopilot()
    static var on: Bool { ProcessInfo.processInfo.arguments.contains("-demoAutoplay") }
    static var preview: Bool { ProcessInfo.processInfo.arguments.contains("-preview") }
    private var running = false
    @MainActor private func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
    @MainActor
    func run(_ store: Store, _ router: Router) {
        guard Autopilot.on || Autopilot.preview, !running else { return }
        running = true
        Task { @MainActor in
            if Autopilot.preview { await preview(store, router) } else { await review(store, router) }
            try? Data("ok".utf8).write(to: URL.documentsDirectory.appending(path: "demo_done"))
        }
    }

    @MainActor private func tickAll(_ store: Store, gap: Double) async {
        for h in store.dueToday where !store.satisfiedToday(h) {
            withAnimation(.snappy(duration: 0.3)) {
                if h.target > 1 { store.markDone(h, Day.today); store.save() } else { store.toggle(h, Day.today) }
            }
            await wait(gap)
        }
    }

    @MainActor private func preview(_ store: Store, _ router: Router) async {
        await wait(2)
        await tickAll(store, gap: 0.8)
        router.celebrating += 1; await wait(2.2)
        router.showcase = true; await wait(3)
        router.showcase = false; await wait(0.6)
        router.challenges = true; await wait(3.2)
        router.challenges = false; router.tab = .stats; await wait(1.3)
        router.insights = true; await wait(3.4)
        router.insights = false; await wait(0.8)
        router.tab = .year; await wait(2.6)
        router.tab = .today; Demo.breakYesterday(store)
        router.rescue = store.rescues().first; await wait(3)
        router.rescue = nil; await wait(0.8)
        router.shop = true; await wait(2.8)
        router.shop = false; await wait(1)
    }

    @MainActor private func review(_ store: Store, _ router: Router) async {
        await wait(3)
        await tickAll(store, gap: 1.2)
        router.celebrating += 1; await wait(2.5)
        router.detail = store.habits.first; await wait(4)
        router.detail = nil; await wait(1)
        router.challenges = true; await wait(4)
        router.challenges = false; await wait(1)
        router.tab = .week; await wait(3)
        router.tab = .year; await wait(3.5)
        router.tab = .stats; await wait(2)
        router.insights = true; await wait(4)
        router.insights = false; await wait(1)
        router.tab = .today; await wait(1)
        Demo.breakYesterday(store)
        router.rescue = store.rescues().first; await wait(4)
        router.rescue = nil; await wait(1)
        router.shop = true; await wait(4)
        router.shop = false; await wait(1)
        router.paywall = .plus; await wait(5)
        router.paywall = nil; await wait(1)
        router.creating = true; await wait(3)
        router.creating = false; await wait(1)
    }
}
