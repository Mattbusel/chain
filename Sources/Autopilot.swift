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
            for h in store.habits where store.due(h, Day.today) && !store.done(h, Day.today) { store.toggle(h, Day.today); await wait(1.4) }
            await wait(1)
            router.tab = .week; await wait(3)
            router.tab = .year; await wait(3.5)
            router.tab = .stats; await wait(3)
            router.tab = .today; await wait(1)
            router.creating = true; await wait(3)
            router.creating = false; await wait(1)
            try? Data("ok".utf8).write(to: URL.documentsDirectory.appending(path: "demo_done"))
        }
    }
}
