import SwiftUI

/// Drives the real screens for the App Review recording (-demoAutoplay).
@Observable
final class Autopilot {
    static let shared = Autopilot()
    static var on: Bool { ProcessInfo.processInfo.arguments.contains("-demoAutoplay") }
    private var running = false
    @MainActor private func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
    @MainActor
    func run(_ store: Store, _ router: Router) {
        guard Autopilot.on, !running else { return }
        running = true
        Task { @MainActor in
            await wait(3)
            for h in store.dueToday where !store.satisfiedToday(h) {
                if h.target > 1 { store.markDone(h, Day.today); store.save() } else { store.toggle(h, Day.today) }
                await wait(1.2)
            }
            router.celebrating += 1; await wait(2.5)
            router.detail = store.habits.first; await wait(4)
            router.detail = nil; await wait(1)
            router.tab = .week; await wait(3)
            router.tab = .year; await wait(3.5)
            router.tab = .stats; await wait(3)
            router.tab = .today; await wait(1)
            Demo.breakYesterday(store)
            router.rescue = store.rescues().first; await wait(4)
            router.rescue = nil; await wait(1)
            router.shop = true; await wait(4)
            router.shop = false; await wait(1)
            router.paywall = .widgets; await wait(4)
            router.paywall = nil; await wait(1)
            router.creating = true; await wait(3)
            router.creating = false; await wait(1)
            try? Data("ok".utf8).write(to: URL.documentsDirectory.appending(path: "demo_done"))
        }
    }
}
