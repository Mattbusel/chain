import SwiftUI

/// One accent in three depths. Lime is free; the others are 99-cent themes, each with a matching app icon.
struct Palette: Identifiable, Hashable {
    let id: String
    let name: String
    let blurb: String
    let accent: Color
    let mid: Color
    let deep: Color
    /// The alternate icon in the asset catalog, nil for the default.
    var icon: String? { id == "lime" ? nil : "AppIcon-" + name }

    static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
    static let all: [Palette] = [
        Palette(id: "lime", name: "Lime", blurb: "The original. Free.", accent: rgb(0xA3E635), mid: rgb(0x65A30D), deep: rgb(0x365314)),
        Palette(id: "ember", name: "Ember", blurb: "A chain that glows like coals.", accent: rgb(0xFB923C), mid: rgb(0xC2410C), deep: rgb(0x7C2D12)),
        Palette(id: "tide", name: "Tide", blurb: "Cold water, clear head.", accent: rgb(0x22D3EE), mid: rgb(0x0891B2), deep: rgb(0x164E63)),
        Palette(id: "bloom", name: "Bloom", blurb: "Pink, loud and proud of it.", accent: rgb(0xF472B6), mid: rgb(0xDB2777), deep: rgb(0x831843)),
        Palette(id: "gold", name: "Gold", blurb: "For chains worth bragging about.", accent: rgb(0xFACC15), mid: rgb(0xCA8A04), deep: rgb(0x713F12)),
        Palette(id: "violet", name: "Violet", blurb: "Late nights, long streaks.", accent: rgb(0xA78BFA), mid: rgb(0x7C3AED), deep: rgb(0x4C1D95)),
    ]
    /// Read once and kept, because the quilt asks for it hundreds of times a frame.
    static var current: Palette = byID(Shared.theme)
    static func byID(_ id: String) -> Palette { all.first { $0.id == id } ?? all[0] }
    static func reload() { current = byID(Shared.theme) }
    static func apply(_ id: String) { Shared.theme = id; current = byID(id) }
}

/// Charcoal and an accent. The year is a quilt of squares; a missed day is a hole in it.
enum Ink {
    static let bg = Color(red: 0.059, green: 0.059, blue: 0.067)          // #0F0F11
    static let bg2 = Color(red: 0.082, green: 0.082, blue: 0.094)
    static let card = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let card2 = Color(red: 0.14, green: 0.14, blue: 0.16)
    static let line = Color.white.opacity(0.08)
    static let line2 = Color.white.opacity(0.18)
    static let white = Color(red: 0.96, green: 0.96, blue: 0.96)
    static let grey = Color(red: 0.96, green: 0.96, blue: 0.96).opacity(0.6)
    static let dim = Color(red: 0.96, green: 0.96, blue: 0.96).opacity(0.32)
    static var lime: Color { Palette.current.accent }
    static var lime2: Color { Palette.current.mid }
    static var lime3: Color { Palette.current.deep }
    static let hole = Color(red: 0.17, green: 0.17, blue: 0.20)
    static let amber = Color(red: 0.98, green: 0.75, blue: 0.14)
    static let red = Color(red: 0.97, green: 0.44, blue: 0.44)
    /// A day a freeze held.
    static let ice = Color(red: 0.56, green: 0.78, blue: 0.98)
    /// A day a Streak Repair patched.
    static let patch = Color(red: 0.98, green: 0.75, blue: 0.14)
}

extension Font {
    static func big(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static func ui(_ size: CGFloat, _ w: Font.Weight = .semibold) -> Font { .system(size: size, weight: w, design: .rounded) }
    static func num(_ size: CGFloat, _ w: Font.Weight = .heavy) -> Font { .system(size: size, weight: w, design: .rounded).monospacedDigit() }
}

struct CharcoalBackground: View {
    var body: some View {
        ZStack {
            Ink.bg
            RadialGradient(colors: [Ink.lime.opacity(0.10), .clear], center: .init(x: 0.9, y: -0.1), startRadius: 10, endRadius: 500)
        }.ignoresSafeArea()
    }
}

struct Eyebrow: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View { Text(text.uppercased()).font(.ui(11, .heavy)).tracking(2).foregroundStyle(Ink.dim) }
}

extension View {
    func tile(padding: CGFloat = 16, radius: CGFloat = 20) -> some View {
        self.padding(padding)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Ink.card))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Ink.line))
    }
}

/// One square of a quilt: what colour a habit's day is.
enum Square {
    case future, notDue, hole, done, partial(Double), frozen, repaired, slip, clean
    var color: Color {
        switch self {
        case .future: return Ink.line.opacity(0.4)
        case .notDue: return Ink.line
        case .hole: return Ink.hole
        case .done, .clean: return Ink.lime
        case .partial(let p): return Ink.lime.opacity(0.25 + 0.5 * p)
        case .frozen: return Ink.ice.opacity(0.8)
        case .repaired: return Ink.patch
        case .slip: return Ink.red.opacity(0.85)
        }
    }
    var stitched: Bool { if case .done = self { return true }; if case .repaired = self { return true }; return false }
}

extension Store {
    func square(_ h: Habit, _ d: String) -> Square {
        if d > Day.today { return .future }
        if d < h.start { return .future }
        if h.kind == .quit { return done(h, d) ? .slip : .clean }
        if done(h, d) { return .done }
        if isRepaired(h, d) { return .repaired }
        if isFrozen(h, d) { return .frozen }
        if !due(h, d) { return .notDue }
        if h.target > 1, count(h, d) > 0 { return .partial(progress(h, d)) }
        return d == Day.today ? .notDue : .hole
    }
}

/// The completion ring on Today and on the widgets.
struct Ring: View {
    let fraction: Double
    var size: CGFloat = 84
    var width: CGFloat = 9
    var label = true
    var body: some View {
        ZStack {
            Circle().stroke(Ink.line2, lineWidth: width)
            Circle().trim(from: 0, to: fraction).stroke(Ink.lime, style: StrokeStyle(lineWidth: width, lineCap: .round)).rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.6), value: fraction)
            if label { Text("\(Int((fraction * 100).rounded()))%").font(.num(size * 0.2)).foregroundStyle(Ink.white) }
        }
        .frame(width: size, height: size)
    }
}
