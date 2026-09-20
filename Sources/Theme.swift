import SwiftUI

/// Charcoal and lime. The year is a quilt of squares; a missed day is a hole in it.
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
    static let lime = Color(red: 0.64, green: 0.90, blue: 0.21)           // #A3E635
    static let lime2 = Color(red: 0.40, green: 0.64, blue: 0.05)
    static let lime3 = Color(red: 0.21, green: 0.33, blue: 0.08)
    static let hole = Color(red: 0.17, green: 0.17, blue: 0.20)
    static let amber = Color(red: 0.98, green: 0.75, blue: 0.14)
    static let red = Color(red: 0.97, green: 0.44, blue: 0.44)
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

/// The lime button.
struct LimeButton: View {
    let title: String
    var icon: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 15, weight: .black)) }
                Text(title).font(.ui(15, .heavy))
            }
            .foregroundStyle(Ink.bg).frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Ink.lime).shadow(color: Ink.lime.opacity(0.35), radius: 16, y: 6))
        }.buttonStyle(.plain)
    }
}

struct GreyButton: View {
    let title: String
    var icon: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 13, weight: .bold)) }
                Text(title).font(.ui(13, .heavy))
            }
            .foregroundStyle(Ink.grey).padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Ink.card2)).overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Ink.line2))
        }.buttonStyle(.plain)
    }
}

struct QuiltTabBar: View {
    @Binding var selection: Tab
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button { withAnimation(.snappy(duration: 0.25)) { selection = t } } label: {
                    VStack(spacing: 5) {
                        Image(systemName: t.icon).font(.system(size: 17, weight: selection == t ? .black : .medium))
                        Text(t.rawValue).font(.ui(10, .heavy))
                    }
                    .foregroundStyle(selection == t ? Ink.bg : Ink.dim)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(Group { if selection == t { RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Ink.lime) } })
                }.buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 19, style: .continuous).fill(Ink.card).shadow(color: .black.opacity(0.6), radius: 20, y: 10))
        .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).strokeBorder(Ink.line2))
        .padding(.horizontal, 16)
    }
}

/// The completion ring on Today.
struct Ring: View {
    let fraction: Double
    var body: some View {
        ZStack {
            Circle().stroke(Ink.line2, lineWidth: 9)
            Circle().trim(from: 0, to: fraction).stroke(Ink.lime, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.6), value: fraction)
            Text("\(Int((fraction * 100).rounded()))%").font(.num(17)).foregroundStyle(Ink.white)
        }
        .frame(width: 84, height: 84)
    }
}
