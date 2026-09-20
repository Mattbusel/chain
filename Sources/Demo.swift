import Foundation

enum Demo {
    static func fill(_ s: Store) {
        let t = Day.today
        s.habits = [
            Habit(name: "Read 20 pages", emoji: "📖", frequency: .daily, start: Day.add(t, -140)),
            Habit(name: "Run", emoji: "🏃", frequency: .days, days: [0, 2, 4], start: Day.add(t, -140)),
            Habit(name: "No phone after 10pm", emoji: "📵", frequency: .daily, start: Day.add(t, -90)),
            Habit(name: "Strength session", emoji: "💪", frequency: .weekly, perWeek: 3, start: Day.add(t, -140)),
            Habit(name: "Meditate 10 min", emoji: "🧘", frequency: .daily, start: Day.add(t, -60)),
        ]
        var seed: UInt64 = 7
        func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33 % 1000) / 1000 }
        let p: [Double] = [0.86, 0.8, 0.7, 0.45, 0.75]
        for i in stride(from: 140, through: 1, by: -1) {
            let d = Day.add(t, -i)
            for (hi, h) in s.habits.enumerated() where d >= h.start {
                if h.frequency == .days && !h.days.contains(Day.dow(d)) { continue }
                if rnd() < p[hi] + (i < 30 ? 0.08 : 0) { s.log[d, default: []].append(h.id) }
            }
        }
        s.log[t] = [s.habits[0].id, s.habits[4].id]
    }
}
