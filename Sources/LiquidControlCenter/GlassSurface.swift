#if os(iOS)
import SwiftUI
import LiquidGlassKit

extension EnvironmentValues {
    @Entry var controlCenterReduceTransparency = false
    @Entry var controlCenterReduceMotion = false
}

struct GlassSurface: ViewModifier {
    var radius: CGFloat
    var tint: Color?
    var fallback: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.controlCenterReduceTransparency) private var forceOpaque
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if reduceTransparency || forceOpaque {
                content.background(tint ?? Color(white: 0.22), in: shape)
            } else if fallback {
                content.background(.ultraThinMaterial, in: shape)
                    .background((tint ?? .clear).opacity(0.35), in: shape)
            } else {
                content.liquidGlassEffect(.regular.tint(tint).interactive(false), in: shape)
            }
        }
        .overlay {
            shape.strokeBorder(.white.opacity(contrast == .increased ? 0.65 : 0.18), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }
}

struct CenterGlassContainer<Content: View>: View {
    var fallback: Bool
    @ViewBuilder var content: Content
    var body: some View {
        if #available(iOS 26, *), !fallback {
            GlassEffectContainer(spacing: 8) { content }
        } else {
            content
        }
    }
}

struct ControlPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlCenterReduceMotion) private var forceReducedMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion && !forceReducedMotion ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.78), value: configuration.isPressed)
    }
}
#endif
