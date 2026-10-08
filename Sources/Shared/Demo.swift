import Foundation

/// The data the store screenshots and the App Review recording run on.
enum Demo {
    static func fill(_ s: Store) {
        let t = Day.today
        s.habits = [
            Habit(name: "Read 20 pages", emoji: "📖", frequency: .daily, start: Day.add(t, -160), remind: true, remindHour: 21, part: .evening),
            Habit(name: "Drink water", emoji: "💧", frequency: .daily, start: Day.add(t, -120), target: 8, unit: "glasses", part: .anytime),
            Habit(name: "Run", emoji: "🏃", frequency: .days, days: [0, 2, 4], start: Day.add(t, -160), part: .morning),
            Habit(name: "Meditate 10 min", emoji: "🧘", frequency: .daily, start: Day.add(t, -80), part: .morning),
            Habit(name: "8,000 steps", emoji: "🚶", frequency: .daily, start: Day.add(t, -100), target: 8000, unit: "steps", health: .steps, part: .anytime),
            Habit(name: "Strength session", emoji: "💪", frequency: .weekly, perWeek: 3, start: Day.add(t, -160), part: .afternoon),
            Habit(name: "No phone in bed", emoji: "📵", frequency: .daily, start: Day.add(t, -90), part: .evening),
            Habit(name: "No smoking", emoji: "🚭", start: Day.add(t, -212), kind: .quit),
        ]
        var seed: UInt64 = 7
        func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double((seed >> 33) % 1000) / 1000 }
        let p: [Double] = [0.9, 0.82, 0.8, 0.74, 0.7, 0.5, 0.72, 0]
        for i in stride(from: 160, through: 1, by: -1) {
            let d = Day.add(t, -i)
            for (hi, h) in s.habits.enumerated() where d >= h.start && h.kind == .build {
                if h.frequency == .days && !h.days.contains(Day.dow(d)) { continue }
                // The last few weeks are the streak the screenshots show off.
                if rnd() < p[hi] + (i < 40 ? 0.12 : 0) || (hi == 0 && i < 47) {
                    if h.target > 1 { s.setCount(h, d, h.target + (h.health != nil ? Int(rnd() * 3000) : 0)) } else { s.setDone(h, d, true) }
                } else if h.target > 1 {
                    s.setCount(h, d, Int(Double(h.target) * rnd() * 0.8))
                }
            }
        }
        // One slip, long ago; one frozen day and one patched day in the reading chain.
        s.setDone(s.habits[7], Day.add(t, -47), true)
        s.frozen[Day.add(t, -9)] = [s.habits[0].id]
        s.setDone(s.habits[0], Day.add(t, -9), false)
        s.repaired[Day.add(t, -23)] = [s.habits[0].id]
        s.setDone(s.habits[0], Day.add(t, -23), false)
        // Today: halfway through.
        for h in s.habits { s.setDone(h, t, false); s.counts[t]?[h.id.uuidString] = nil }
        s.setDone(s.habits[3], t, true)
        s.setDone(s.habits[2], t, true)
        s.setCount(s.habits[1], t, 5)
        s.setCount(s.habits[4], t, 6240)
        s.notes[Day.add(t, -1)] = [s.habits[0].id.uuidString: "Finished Project Hail Mary. Starting Dune next."]
        s.notes[Day.add(t, -3)] = [s.habits[0].id.uuidString: "Only 12 pages, but it counts."]
        s.notes[Day.add(t, -2)] = [s.habits[3].id.uuidString: "Calmer before the meeting."]
        s.freezeSpend[Day.month(t)] = 1
        s.repairCredits = 0
    }

    /// A chain that broke yesterday, for the rescue screenshot.
    static func breakYesterday(_ s: Store) {
        let y = Day.add(Day.today, -1)
        s.setDone(s.habits[0], y, false)
        s.frozen[y] = nil
    }
}
