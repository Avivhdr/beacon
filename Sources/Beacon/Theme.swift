import SwiftUI

/// Cockpit palette: blue-black ink, cool white type, amber as the one signal color.
/// Red and green only ever mean status (failing/changes requested, passing/approved).
enum Palette {
    static let ink = Color(hex: 0x0C0F14)
    static let surface = Color(hex: 0x12161D)
    static let raised = Color(hex: 0x1A2029)
    static let hairline = Color.white.opacity(0.07)
    static let hairlineStrong = Color.white.opacity(0.14)

    static let text = Color(hex: 0xE6EAF0)
    static let dim = Color(hex: 0x8A93A3)
    static let faint = Color(hex: 0x525B6A)

    static let amber = Color(hex: 0xF4A93B)
    static let red = Color(hex: 0xF0575D)
    static let green = Color(hex: 0x41D18A)
    static let steel = Color(hex: 0x9FB2CC)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Small uppercase monospaced labels, the "readout" voice of the panel.
struct Readout: ViewModifier {
    var size: CGFloat = 9.5
    var tracking: CGFloat = 1.4

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: .semibold, design: .monospaced))
            .textCase(.uppercase)
            .tracking(tracking)
    }
}

extension View {
    func readout(size: CGFloat = 9.5, tracking: CGFloat = 1.4) -> some View {
        modifier(Readout(size: size, tracking: tracking))
    }
}

/// A square indicator lamp: dark housing, colored symbol, lit background when active.
struct Lamp: View {
    let symbol: String
    let color: Color
    var lit = true
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .bold))
            .foregroundStyle(lit ? color : Palette.faint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(lit ? color.opacity(0.14) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(lit ? color.opacity(0.35) : Palette.hairline, lineWidth: 1)
            )
    }
}

/// Instrument-style tick marks along an edge: short ticks every 6pt, long ones every 30pt.
struct TickRuler: View {
    var body: some View {
        Canvas { context, size in
            var x: CGFloat = 0.5
            var index = 0
            while x < size.width {
                let long = index % 5 == 0
                let height: CGFloat = long ? size.height : size.height * 0.45
                context.fill(
                    Path(CGRect(x: x, y: size.height - height, width: 1, height: height)),
                    with: .color(.white.opacity(long ? 0.13 : 0.06))
                )
                x += 6
                index += 1
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Ease-out-quint, for anything that arrives.
extension Animation {
    static func arrive(_ duration: Double = 0.42) -> Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: duration)
    }

    static func leave(_ duration: Double = 0.22) -> Animation {
        .timingCurve(0.5, 0, 0.75, 0, duration: duration)
    }
}

/// Fades and lifts a row in when the panel opens, one after another.
struct StaggeredReveal: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .onAppear {
                guard !reduceMotion, !shown else { return }
                // Only the first screenful gets choreography; rows further down just appear.
                let delay = index < 9 ? 0.06 + Double(index) * 0.035 : 0
                withAnimation(.arrive(0.5).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func staggeredReveal(_ index: Int) -> some View {
        modifier(StaggeredReveal(index: index))
    }
}

/// Press feedback for rows: a quick dip in scale.
struct PressableRow: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.arrive(0.18), value: configuration.isPressed)
    }
}

/// Small icon button for the panel chrome: dim at rest, white on hover.
struct ChromeButton: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(hovering ? Palette.text : Palette.dim)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.12 : hovering ? 0.07 : 0))
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.arrive(0.2), value: hovering)
    }
}
