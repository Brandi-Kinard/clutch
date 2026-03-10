import SwiftUI

// MARK: - Brand Colors

extension Color {
    /// Deep indigo #1a0533
    static let clutchDeepIndigo = Color(red: 0.102, green: 0.020, blue: 0.200)
    /// Electric violet #7c3aed
    static let clutchViolet = Color(red: 0.486, green: 0.227, blue: 0.929)
    /// Near-white #e0d4ff
    static let clutchNearWhite = Color(red: 0.878, green: 0.831, blue: 1.000)
    /// Primary #a78bfa
    static let clutchPrimary = Color(red: 0.655, green: 0.545, blue: 0.980)
}

// MARK: - Animated Cosmic Gradient Background

struct CosmicGradientBackground: View {
    var dimmed: Bool = false
    /// When true, a soft violet overlay breathes in/out (use during speaking)
    var pulsing: Bool = false
    @State private var animate = false

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .clutchDeepIndigo, location: animate ? 0.00 : 0.10),
                    .init(color: .clutchViolet, location: animate ? 0.48 : 0.58),
                    .init(color: .clutchNearWhite.opacity(dimmed ? 0.12 : 0.22), location: 1.00),
                ],
                startPoint: animate ? .topLeading : .topTrailing,
                endPoint: animate ? .bottomTrailing : .bottomLeading
            )
            .ignoresSafeArea()

            if pulsing {
                PulsingOverlay()
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

// MARK: - Pulsing Overlay (shown during speaking)

struct PulsingOverlay: View {
    @State private var breathing = false

    var body: some View {
        Color.clutchViolet
            .opacity(breathing ? 0.14 : 0.0)
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
    }
}

// MARK: - Glass Card Modifier

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.clutchViolet.opacity(0.08))
                    )
                    .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Glass Button Modifier (capsule)

struct GlassButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.clutchViolet.opacity(0.12)))
                    .shadow(color: .black.opacity(0.20), radius: 8, x: 0, y: 3)
            )
            .clipShape(Capsule())
    }
}

// MARK: - Glass Circle Modifier (icon buttons)

struct GlassCircleModifier: ViewModifier {
    var size: CGFloat = 48
    var highlighted: Bool = false

    func body(content: Content) -> some View {
        content
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle().fill(
                            highlighted
                                ? Color.clutchPrimary.opacity(0.30)
                                : Color.clutchViolet.opacity(0.10)
                        )
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                highlighted ? Color.clutchPrimary : Color.white.opacity(0.18),
                                lineWidth: highlighted ? 2 : 1
                            )
                    )
                    .shadow(color: .black.opacity(0.20), radius: 6, x: 0, y: 2)
            )
            .clipShape(Circle())
    }
}

// MARK: - View Extensions

extension View {
    func glassCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    func glassButton() -> some View {
        modifier(GlassButtonModifier())
    }

    func glassCircle(size: CGFloat = 48, highlighted: Bool = false) -> some View {
        modifier(GlassCircleModifier(size: size, highlighted: highlighted))
    }
}

// MARK: - Thinking Dot

struct ThinkingDot: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Color.clutchPrimary)
            .frame(width: 10, height: 10)
            .scaleEffect(pulsing ? 1.5 : 1.0)
            .opacity(pulsing ? 0.6 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}
