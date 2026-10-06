#if os(iOS)
import SwiftUI
import UIKit
import LiquidGlassKit

extension EnvironmentValues {
    @Entry var controlCenterReduceTransparency = false
    @Entry var controlCenterReduceMotion = false
    @Entry var controlCenterFallback = false
}

/// Glass for tiles and the center's own controls. Every surface is drawn by LiquidGlassKit: native Liquid Glass on
/// iOS 26 and later, its material fallback before that.
///
/// Native glass takes the control's tint itself, lights its own edges, and is otherwise left clear: a default white
/// tint or an outline flattens it into frosted plastic. The kit's fallback is a single material, which can do neither,
/// so the tint is layered behind it and a hairline rim is added.
struct GlassSurface: ViewModifier {
    var radius: CGFloat
    var tint: Color?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.controlCenterReduceTransparency) private var forceOpaque
    @Environment(\.controlCenterFallback) private var forceFallback
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if reduceTransparency || forceOpaque {
                content.background(tint ?? Color(white: 0.22), in: shape)
            } else if forceFallback {
                // On iOS the kit's background effect always draws its fallback (the native one is visionOS-only), so
                // this previews exactly what iOS 16–25 get.
                content.liquidGlassBackgroundEffect(LiquidGlass.regular, in: shape, fallback: Self.fallback)
                    .background { materialTint(shape) }
            } else {
                content.liquidGlassEffect(.regular.tint(tint).interactive(false), in: shape, fallback: Self.fallback)
                    .background { materialTint(shape) }
            }
        }
        .overlay {
            shape.strokeBorder(.white.opacity(rimOpacity), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }

    /// A material cannot carry a tint, so the control's tint sits behind it. Native glass is tinted directly.
    @ViewBuilder
    private func materialTint(_ shape: some Shape) -> some View {
        if drawsMaterial, let tint { shape.fill(tint.opacity(0.35)) }
    }

    /// Native glass lights its own edges; the material and opaque surfaces need a rim. Increase Contrast always gets one.
    private var rimOpacity: Double {
        if contrast == .increased { return 0.65 }
        return drawsMaterial || reduceTransparency || forceOpaque ? 0.18 : 0
    }

    private var drawsMaterial: Bool { forceFallback || !Self.nativeGlass }

    private static let fallback = Material.ultraThinMaterial

    /// Mirrors the kit's own switch: native glass from iOS 26, its fallback below that.
    private static var nativeGlass: Bool {
        if #available(iOS 26.0, *) { return true } else { return false }
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

/// Full-screen live blur, optional Liquid Glass, and dimming, whose strength follows the presentation progress frame
/// by frame.
///
/// Conforming to `Animatable` makes SwiftUI evaluate this view for every animation frame, so the backdrop
/// shares the exact spring of the tiles and can be scrubbed by a finger. The blur radius itself is
/// interpolated by a paused `UIViewPropertyAnimator`; the effect view always stays at full alpha.
struct CenterBackdrop: View, Animatable {
    var progress: Double
    var backdrop: ControlCenterBackdrop
    var opaque: Bool

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let visible = min(1, max(0, progress))
        ZStack {
            if opaque {
                Color.black.opacity(0.88 * visible)
            } else {
                // The blur leads the tiles slightly, like the system, so controls never sit on a sharp app.
                ScrubbableBlur(fraction: backdrop.blur * pow(visible, 0.75))
                if backdrop.glass != .none {
                    // LiquidGlassKit draws the glass on iOS 26 and later; the clear fallback leaves the blur alone.
                    let glass: LiquidGlass = backdrop.glass == .regular ? .regular : .clear
                    Color.clear
                        .liquidGlassEffect(glass.interactive(false), in: Rectangle(), fallback: Color.clear)
                        .opacity(visible)
                }
                Color.black.opacity(backdrop.dimming * visible)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ScrubbableBlur: UIViewRepresentable {
    var fraction: Double

    func makeUIView(context: Context) -> ScrubbableBlurView { ScrubbableBlurView() }
    func updateUIView(_ view: ScrubbableBlurView, context: Context) { view.fraction = fraction }
    static func dismantleUIView(_ view: ScrubbableBlurView, coordinator: ()) { view.tearDown() }
}

/// Scrubs a live blur while the presentation moves, and settles at rest: into a plain `UIBlurEffect` at full
/// strength, or, for a partial blur, by finishing the animator where it stands, which keeps that radius.
///
/// A paused animator leaves a frozen animation on the layer. Keeping one for the whole time the center is open
/// would stop the app from ever reporting idle (UI tests then wait 60 seconds before every action) and keeps an
/// animation in flight, so the animator only exists while the value is changing.
final class ScrubbableBlurView: UIView {
    private let effectView = UIVisualEffectView(effect: nil)
    private var animator: UIViewPropertyAnimator?
    private var observer: NSObjectProtocol?
    private var rebuildScheduled = false
    /// True when the current animator runs from blurred to clear, i.e. it was built while resting blurred.
    private var inverted = false
    private var settleToken = 0
    /// The blur fraction shown while no animator exists; nil when unknown, which forces a rebuild.
    private var resting: CGFloat? = 0

    /// True while an animator is scrubbing the blur; false once it has settled.
    var isScrubbing: Bool { animator != nil }

    var fraction: Double = 0 {
        didSet { apply() }
    }

    private var target: CGFloat { CGFloat(min(1, max(0, fraction.isFinite ? fraction : 0))) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        effectView.frame = bounds
        effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(effectView)
        // Paused animators can be finalized while the app is in the background; rebuild on return.
        observer = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.animator != nil else { return }
                self.stop()
                self.resting = nil
                self.apply()
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        stop()
        effectView.effect = nil
        resting = 0
        apply()
    }

    func tearDown() {
        stop()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private func apply() {
        if let animator {
            animator.fractionComplete = animatorFraction
            scheduleSettle()
            return
        }
        guard window != nil, !isSettled, !rebuildScheduled else { return }
        // SwiftUI updates representables inside `performWithoutAnimation`, which would apply the blur
        // immediately instead of recording it in the animator. Build it on the next turn of the run loop.
        rebuildScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.rebuildScheduled = false
                guard self.window != nil, self.animator == nil, !self.isSettled else { return }
                self.rebuild()
                self.scheduleSettle()
            }
        }
    }

    /// True when the settled blur already matches the requested one.
    private var isSettled: Bool { resting.map { abs(target - $0) <= 0.001 } ?? false }

    private var animatorFraction: CGFloat { inverted ? 1 - target : target }

    /// Animates away from the committed effect. Resetting the effect and animating it back within one run-loop
    /// turn would coalesce into no change, leaving the animator scrubbing nothing. After resting at a partial blur
    /// the committed effect is still none or the full blur, and a new animator starts from that rather than from the
    /// frozen radius, so `animatorFraction` keeps mapping to the same strengths (verified on iOS 27).
    private func rebuild() {
        inverted = effectView.effect != nil
        let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [effectView, inverted] in
            effectView.effect = inverted ? nil : UIBlurEffect(style: .systemUltraThinMaterialDark)
        }
        animator.pausesOnCompletion = true
        animator.fractionComplete = animatorFraction
        self.animator = animator
    }

    private func scheduleSettle() {
        settleToken &+= 1
        let token = settleToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.settleToken == token, let animator = self.animator else { return }
                let value = self.target
                animator.stopAnimation(false)
                if value <= 0.001 || value >= 0.999 {
                    animator.finishAnimation(at: (value >= 0.999) != self.inverted ? .end : .start)
                    self.resting = value >= 0.999 ? 1 : 0
                } else {
                    animator.finishAnimation(at: .current)
                    self.resting = value
                }
                self.animator = nil
            }
        }
    }

    /// Releasing a paused animator is a runtime error; always stop it first.
    private func stop() {
        guard let animator else { return }
        animator.stopAnimation(true)
        self.animator = nil
    }
}
#endif
