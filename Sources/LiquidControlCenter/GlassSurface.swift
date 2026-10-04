#if os(iOS)
import SwiftUI
import UIKit

extension EnvironmentValues {
    @Entry var controlCenterReduceTransparency = false
    @Entry var controlCenterReduceMotion = false
    @Entry var controlCenterFallback = false
}

/// Native Liquid Glass on iOS 26+, a material fallback before that (or when forced).
/// The availability check is compiled only by toolchains that ship the iOS 26 SDK, so older Xcode versions still build.
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
            } else if !forceFallback, let glass = nativeGlass(content, shape: shape) {
                glass
            } else {
                content.background(.ultraThinMaterial, in: shape)
                    .background((tint ?? .clear).opacity(0.35), in: shape)
            }
        }
        .overlay {
            shape.strokeBorder(.white.opacity(contrast == .increased ? 0.65 : 0.18), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }

    private func nativeGlass(_ content: Content, shape: some Shape) -> AnyView? {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            return AnyView(content.glassEffect(.regular.tint(tint ?? .white.opacity(0.12)).interactive(false), in: shape))
        }
        #endif
        return nil
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

/// Full-screen live blur and dimming whose strength follows the presentation progress frame by frame.
///
/// Conforming to `Animatable` makes SwiftUI evaluate this view for every animation frame, so the blur
/// shares the exact spring of the tiles and can be scrubbed by a finger. The blur radius itself is
/// interpolated by a paused `UIViewPropertyAnimator`; the effect view always stays at full alpha.
struct CenterBackdrop: View, Animatable {
    var progress: Double
    var dimming: Double
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
                ScrubbableBlur(fraction: pow(visible, 0.75))
                Color.black.opacity(dimming * visible)
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

/// Scrubs a live blur while the presentation moves, and settles into a plain `UIBlurEffect` at rest.
///
/// A paused animator leaves a frozen animation on the layer. Keeping one for the whole time the center is open
/// would stop the app from ever reporting idle (UI tests wait forever) and keeps an animation in flight, so the
/// animator only exists while the value is changing.
final class ScrubbableBlurView: UIView {
    private let effectView = UIVisualEffectView(effect: nil)
    private var animator: UIViewPropertyAnimator?
    private var observer: NSObjectProtocol?
    private var rebuildScheduled = false
    /// True when the current animator runs from blurred to clear, i.e. it was built while resting blurred.
    private var inverted = false
    private var settleToken = 0

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
                self.apply()
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        stop()
        effectView.effect = nil
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

    /// True when the static effect already matches the requested end state.
    private var isSettled: Bool {
        (target <= 0.001 && effectView.effect == nil) || (target >= 0.999 && effectView.effect != nil)
    }

    private var animatorFraction: CGFloat { inverted ? 1 - target : target }

    /// Animates away from the committed effect. Resetting the effect and animating it back within one run-loop
    /// turn would coalesce into no change, leaving the animator scrubbing nothing.
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
                guard value <= 0.001 || value >= 0.999 else { return }
                let blurred = value >= 0.999
                animator.stopAnimation(false)
                animator.finishAnimation(at: blurred != self.inverted ? .end : .start)
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
