import SwiftUI

/// The accent button.
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
        }.buttonStyle(Press())
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
        }.buttonStyle(Press())
    }
}

/// A small squash on press, so every button answers the finger.
struct Press: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.96 : 1).animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct CloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 14, weight: .black)).foregroundStyle(Ink.grey)
                .frame(width: 36, height: 36).background(Circle().fill(Ink.card2)).overlay(Circle().strokeBorder(Ink.line2))
        }.buttonStyle(.plain).accessibilityLabel("Close")
    }
}

/// A pill naming what Chain Unlimited adds, on a locked control.
struct ProTag: View {
    var body: some View {
        Text("UNLIMITED").font(.ui(9, .black)).tracking(1).foregroundStyle(Ink.bg)
            .padding(.horizontal, 6).padding(.vertical, 3).background(Capsule().fill(Ink.lime))
    }
}

struct QuiltTabBar: View {
    @Binding var selection: Tab
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = t }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
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

/// Header line for a group of rows.
struct SectionHead: View {
    let title: String
    var icon: String? = nil
    var trailing: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 11, weight: .black)).foregroundStyle(Ink.dim) }
            Eyebrow(title)
            Spacer()
            if let trailing { Text(trailing).font(.num(11, .bold)).foregroundStyle(Ink.dim) }
        }.padding(.top, 6).padding(.horizontal, 4)
    }
}
