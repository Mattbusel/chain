import Foundation

/// A month-long push on one habit. Each calendar month headlines one (free to join); Chain Plus
/// opens the whole library, any time, as 30-day runs.
struct Challenge: Identifiable, Hashable {
    let id: String
    let title: String
    let emoji: String
    /// The habit the challenge adds (or links, if one with this name already exists).
    let habit: String
    let part: Part
    let blurb: String
    /// 1...12 for the month it headlines, 0 for library-only.
    let month: Int
}

/// One go at a challenge: a habit, a window of days and a goal of days inside it.
struct ChallengeRun: Codable, Hashable, Identifiable {
    var challenge: String
    var habit: UUID
    var from: String
    var to: String
    var goal: Int
    var won: Bool = false
    var id: String { challenge + "@" + from }
}

enum Challenges {
    static let all: [Challenge] = [
        Challenge(id: "walk", title: "Walk January", emoji: "🚶", habit: "Walk 20 minutes", part: .anytime, blurb: "Twenty minutes on foot. The easiest way to start a year moving.", month: 1),
        Challenge(id: "read", title: "Read February", emoji: "📖", habit: "Read 10 pages", part: .evening, blurb: "Ten pages a night is a book every few weeks.", month: 2),
        Challenge(id: "mindful", title: "Mindful March", emoji: "🧘", habit: "Meditate 5 minutes", part: .morning, blurb: "Five quiet minutes before the day starts talking.", month: 3),
        Challenge(id: "early", title: "Early April", emoji: "🌅", habit: "Up by 7", part: .morning, blurb: "Win the first hour and the rest follows.", month: 4),
        Challenge(id: "move", title: "Move May", emoji: "🏃", habit: "Move 30 minutes", part: .afternoon, blurb: "Run, ride, lift, dance. Half an hour, any way you like.", month: 5),
        Challenge(id: "hydrate", title: "Hydrate June", emoji: "💧", habit: "Drink 8 glasses of water", part: .anytime, blurb: "Summer is thirsty work. Eight glasses, every day.", month: 6),
        Challenge(id: "journal", title: "Journal July", emoji: "✍️", habit: "Write one line", part: .evening, blurb: "One line a day. Future you will read every one.", month: 7),
        Challenge(id: "stretch", title: "Stretch August", emoji: "🤸", habit: "Stretch 10 minutes", part: .morning, blurb: "Ten minutes of stretching, and your back says thank you.", month: 8),
        Challenge(id: "sleep", title: "Sleep September", emoji: "😴", habit: "In bed by 11", part: .evening, blurb: "Back to routine, starting with bedtime.", month: 9),
        Challenge(id: "outdoor", title: "Outdoor October", emoji: "🍂", habit: "15 minutes outside", part: .anytime, blurb: "Daylight while it lasts. Fifteen minutes outdoors.", month: 10),
        Challenge(id: "noscroll", title: "No-Scroll November", emoji: "📵", habit: "No phone for the first hour", part: .morning, blurb: "Start the day before the feed does. No phone for the first hour after you wake.", month: 11),
        Challenge(id: "gratitude", title: "Grateful December", emoji: "🙏", habit: "Write 3 good things", part: .evening, blurb: "End every day of the year on three good things.", month: 12),
        Challenge(id: "pushups", title: "Push-up Ladder", emoji: "💪", habit: "Push-ups", part: .morning, blurb: "A set of push-ups every day. Watch the number climb.", month: 0),
        Challenge(id: "cold", title: "Cold Finish", emoji: "🚿", habit: "30 seconds cold shower", part: .morning, blurb: "End the shower cold for thirty seconds. Wide awake.", month: 0),
        Challenge(id: "words", title: "Word a Day", emoji: "🗣️", habit: "Learn one new word", part: .anytime, blurb: "A new word in any language, every day for a month.", month: 0),
        Challenge(id: "tidy", title: "Tidy Ten", emoji: "🧹", habit: "Tidy for 10 minutes", part: .evening, blurb: "Ten minutes of tidying a night, and the weekend stays free.", month: 0),
        Challenge(id: "nosugar", title: "Sugar Reset", emoji: "🍬", habit: "No added sugar", part: .anytime, blurb: "A month without added sugar. Count the days you pull it off.", month: 0),
        Challenge(id: "veg", title: "Five a Day", emoji: "🥗", habit: "Five fruit and veg", part: .anytime, blurb: "Five portions of fruit and veg, every day.", month: 0),
    ]

    static func byID(_ id: String) -> Challenge? { all.first { $0.id == id } }
    static func month(_ day: String) -> Int { Int(day.dropFirst(5).prefix(2)) ?? 1 }
    /// This month's headline challenge.
    static func featured(_ day: String = Day.today) -> Challenge { all.first { $0.month == month(day) } ?? all[0] }
    static var library: [Challenge] { all }
    /// The last day of the month `day` is in.
    static func monthEnd(_ day: String) -> String {
        let first = String(day.prefix(7)) + "-01"
        let next = Day.cal.date(byAdding: .month, value: 1, to: Day.date(first)) ?? .now
        return Day.add(Day.key(next), -1)
    }
    /// Four days in five: room for a bad day or two without losing the badge.
    static func goal(from: String, to: String) -> Int { max(1, Int((Double(Day.diff(from, to) + 1) * 0.8).rounded(.up))) }
}

extension Store {
    /// The run of a challenge that is still open (or finished today).
    func openRun(_ c: Challenge) -> ChallengeRun? { runs.last { $0.challenge == c.id && $0.to >= Day.today } }
    var liveRuns: [ChallengeRun] { runs.filter { $0.to >= Day.today } }
    func progress(_ r: ChallengeRun) -> Int {
        guard let h = habits.first(where: { $0.id == r.habit }) else { return 0 }
        var n = 0; var d = r.from
        while d <= min(r.to, Day.today) { if done(h, d) || isRepaired(h, d) { n += 1 }; d = Day.add(d, 1) }
        return n
    }
    func daysLeft(_ r: ChallengeRun) -> Int { max(0, Day.diff(Day.today, r.to) + 1) }

    /// Join a challenge: the featured one runs to the end of the month, a library one for 30 days.
    @discardableResult func join(_ c: Challenge, featured: Bool) -> ChallengeRun {
        if let r = openRun(c) { return r }
        let from = Day.today
        let to = featured ? Challenges.monthEnd(from) : Day.add(from, 29)
        let habit: Habit
        if let i = habits.firstIndex(where: { $0.name.caseInsensitiveCompare(c.habit) == .orderedSame && $0.kind == .build }) {
            habits[i].archived = false
            habit = habits[i]
        } else {
            habit = Habit(name: c.habit, emoji: c.emoji, frequency: .daily, start: from, part: c.part, challenge: c.id)
            habits.append(habit)
        }
        let r = ChallengeRun(challenge: c.id, habit: habit.id, from: from, to: to, goal: Challenges.goal(from: from, to: to))
        runs.append(r)
        save()
        return r
    }

    /// Marks any run that just reached its goal as won, and returns those.
    func checkWins() -> [ChallengeRun] {
        var out: [ChallengeRun] = []
        for i in runs.indices where !runs[i].won && progress(runs[i]) >= runs[i].goal {
            runs[i].won = true
            out.append(runs[i])
        }
        if !out.isEmpty { save() }
        return out
    }
    var wonRuns: [ChallengeRun] { runs.filter(\.won) }
}
