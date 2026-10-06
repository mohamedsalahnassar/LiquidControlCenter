#if os(iOS)
import SwiftUI
import UIKit

// MARK: - SwiftUI entry points

public extension View {
    /// Present a live, full-screen Control Center from any mounted SwiftUI view.
    /// Use stable tile IDs and app-owned bindings for state shared between compact and expanded faces.
    func liquidControlCenter(isPresented: Binding<Bool>,
                             configuration: ControlCenterConfiguration = .init(),
                             onDismiss: @escaping () -> Void = {},
                             @ControlCenterBuilder tiles: () -> [ControlTile]) -> some View {
        liquidControlCenter(isPresented: isPresented,
                            pages: [ControlCenterPage("main", title: configuration.title, systemImage: "heart.fill") { tiles() }],
                            configuration: configuration, onDismiss: onDismiss)
    }

    /// Present multiple app-defined groups with a trailing navigation rail.
    func liquidControlCenter(isPresented: Binding<Bool>, pages: [ControlCenterPage],
                             configuration: ControlCenterConfiguration = .init(),
                             onDismiss: @escaping () -> Void = {}) -> some View {
        modifier(ControlCenterPresenter(isPresented: isPresented, pages: pages,
                                        configuration: configuration, onDismiss: onDismiss))
    }

    /// Lets a downward drag on this view pull the Control Center open, tracking the finger like the system.
    ///
    /// Apply it to a descendant of the view that carries `.liquidControlCenter(...)`, typically a header or a
    /// top-edge strip. Releasing past the midpoint, or flicking downward, completes the presentation.
    func liquidControlCenterPullDown(isEnabled: Bool = true) -> some View {
        modifier(PullDownGesture(isEnabled: isEnabled))
    }
}

extension EnvironmentValues {
    @Entry var liquidControlCenter: LiquidControlCenterController? = nil
}

private struct ControlCenterPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let pages: [ControlCenterPage]
    let configuration: ControlCenterConfiguration
    let onDismiss: () -> Void
    @StateObject private var controller = LiquidControlCenterController()
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        content
            .environment(\.liquidControlCenter, controller)
            .background {
                PresentationAnchor(controller: controller, isPresented: $isPresented, pages: pages,
                                   configuration: configuration,
                                   environment: .init(layoutDirection: layoutDirection,
                                                      dynamicTypeSize: dynamicTypeSize, locale: locale),
                                   onDismiss: onDismiss)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
    }
}

/// Bridges the binding to the controller and supplies the view controller to present from.
private struct PresentationAnchor: UIViewControllerRepresentable {
    let controller: LiquidControlCenterController
    @Binding var isPresented: Bool
    let pages: [ControlCenterPage]
    let configuration: ControlCenterConfiguration
    let environment: CenterEnvironment
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> AnchorController {
        let anchor = AnchorController()
        anchor.onReady = { [weak controller] in controller?.anchorBecameReady() }
        anchor.onTearDown = { [weak controller] in controller?.tearDown() }
        return anchor
    }

    func updateUIViewController(_ anchor: AnchorController, context: Context) {
        controller.anchor = anchor
        controller.inheritedEnvironment = environment
        controller.update(pages: pages, configuration: configuration)
        controller.onDismiss = onDismiss
        let binding = $isPresented
        controller.onPresentationChange = { [weak controller] presented in
            controller?.requestedByBinding = presented
            if binding.wrappedValue != presented { binding.wrappedValue = presented }
        }
        controller.requestedByBinding = isPresented
        // Never present or dismiss inside a SwiftUI update pass. Use the latest request when the work runs, so a
        // pull that began in the meantime is not cancelled by a stale value.
        DispatchQueue.main.async { [weak controller] in
            guard let controller else { return }
            if controller.requestedByBinding { controller.present() } else { controller.dismiss() }
        }
    }

    static func dismantleUIViewController(_ anchor: AnchorController, coordinator: ()) {
        anchor.onReady = nil
        anchor.onTearDown?()
    }
}

final class AnchorController: UIViewController {
    var onReady: (() -> Void)?
    var onTearDown: (() -> Void)?
    override func loadView() {
        let view = AnchorView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.onWindow = { [weak self] in self?.onReady?() }
        self.view = view
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); onReady?() }
}

private final class AnchorView: UIView {
    var onWindow: (() -> Void)?
    override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { onWindow?() } }
}

// MARK: - Controller

struct CenterEnvironment: Equatable {
    var layoutDirection: LayoutDirection?
    var dynamicTypeSize: DynamicTypeSize?
    var locale: Locale?
}

/// Animated state shared with the hosted SwiftUI tree. Everything visual derives from `progress`.
@MainActor
final class CenterModel: ObservableObject {
    /// 0 is hidden, 1 is fully presented. Springs may briefly overshoot 1.
    @Published var progress: Double = 0
    /// Extra vertical displacement while a finger drags the whole center.
    @Published var dragOffset: CGFloat = 0
    /// False while dismissing; an expanded tile collapses as the center closes.
    @Published var isInteractive = false
    /// Incremented to move VoiceOver focus to the close button.
    @Published var focusRequest = 0
    weak var controller: LiquidControlCenterController?
}

/// Presents and dismisses a Control Center. Use it directly from UIKit, React Native, or Flutter hosts;
/// the SwiftUI `liquidControlCenter` modifiers use it internally.
///
/// ```swift
/// let center = LiquidControlCenterController(pages: [...])
/// center.present()                              // from the key window's top-most view controller
/// center.addPullDownGesture(to: headerView)     // optional finger-tracking presentation
/// ```
@MainActor
public final class LiquidControlCenterController: ObservableObject {
    public var pages: [ControlCenterPage] { didSet { refreshRoot() } }
    public var configuration: ControlCenterConfiguration { didSet { refreshRoot() } }
    /// Called after the center has fully disappeared.
    public var onDismiss: (() -> Void)?
    /// True from the moment presentation is requested until dismissal is requested.
    public var isPresented: Bool { wantsPresentation }

    let model = CenterModel()
    weak var anchor: UIViewController?
    var inheritedEnvironment = CenterEnvironment() { didSet { if inheritedEnvironment != oldValue { refreshRoot() } } }
    var onPresentationChange: ((Bool) -> Void)?
    /// The most recent value of the SwiftUI binding, including writes made by the controller itself.
    var requestedByBinding = false

    private var state = PresentationState()
    private var host: CenterHostController?
    private weak var explicitPresenter: UIViewController?
    private var wantsPresentation = false
    private var retry: Task<Void, Never>?
    private var tracker = VelocityTracker()
    private var gestureTargets: [PullDownGestureTarget] = []

    public init(pages: [ControlCenterPage] = [], configuration: ControlCenterConfiguration = .init()) {
        self.pages = pages
        self.configuration = configuration
        model.controller = self
    }

    public convenience init(configuration: ControlCenterConfiguration = .init(),
                            @ControlCenterBuilder tiles: () -> [ControlTile]) {
        self.init(pages: [ControlCenterPage("main", title: configuration.title, systemImage: "heart.fill") { tiles() }],
                  configuration: configuration)
    }

    func update(pages: [ControlCenterPage], configuration: ControlCenterConfiguration) {
        self.pages = pages
        self.configuration = configuration
    }

    // MARK: Programmatic presentation

    /// Present over the given view controller, or over the top-most view controller of the key window.
    public func present(from viewController: UIViewController? = nil, animated: Bool = true) {
        if let viewController { explicitPresenter = viewController }
        if host != nil {
            // Already showing, or a finger is driving it; only reverse an in-flight dismissal.
            guard !wantsPresentation || state.phase == .dismissing else { return }
            wantsPresentation = true
            onPresentationChange?(true)
            animate(to: true, animated: animated)
            return
        }
        wantsPresentation = true
        onPresentationChange?(true)
        schedulePresentation(animated: animated)
    }

    /// Dismiss with the closing spring. Safe to call repeatedly.
    public func dismiss(animated: Bool = true) {
        retry?.cancel()
        retry = nil
        guard wantsPresentation || state.phase == .interacting else { return }
        wantsPresentation = false
        onPresentationChange?(false)
        guard host != nil else { return }
        animate(to: false, animated: animated)
    }

    // MARK: Interactive presentation (pull down)

    /// Adds a pan gesture that pulls the center open while tracking the finger. Returns the recognizer so you
    /// can coordinate it with other gestures. The controller does not retain the view.
    @discardableResult
    public func addPullDownGesture(to view: UIView) -> UIPanGestureRecognizer {
        let target = PullDownGestureTarget(controller: self)
        let recognizer = UIPanGestureRecognizer(target: target, action: #selector(PullDownGestureTarget.handle(_:)))
        recognizer.delegate = target
        view.addGestureRecognizer(recognizer)
        gestureTargets.removeAll { $0.recognizer == nil }
        target.recognizer = recognizer
        gestureTargets.append(target)
        return recognizer
    }

    /// Starts tracking a pull. Returns false when the center cannot be shown right now.
    func beginPull(from presenter: UIViewController? = nil) -> Bool {
        if host == nil {
            guard let presenter = presenter ?? resolvePresenter(), presentHost(from: presenter, animatedIn: false) else { return false }
        }
        _ = state.beginInteraction()
        wantsPresentation = true
        onPresentationChange?(true)
        tracker.reset()
        return true
    }

    func updatePull(translation: CGFloat, distance: CGFloat, time: TimeInterval) {
        guard state.phase == .interacting, distance > 0 else { return }
        let progress = Double(translation / distance)
        tracker.add(progress, at: time)
        let overflow = max(0, translation - distance)
        track(progress: min(1, max(0, progress)),
              offset: CGFloat(GestureMath.rubberBand(Double(overflow), dimension: 500)))
    }

    func endPull() {
        guard state.phase == .interacting else { return }
        finishInteraction(present: GestureMath.shouldPresent(progress: model.progress, velocity: tracker.velocity))
    }

    // MARK: Interactive dismissal (swipe up), driven by the hosted view

    func beginDismissalDrag() {
        guard state.phase != .hidden, state.phase != .dismissing else { return }
        _ = state.beginInteraction()
        tracker.reset()
    }

    func updateDismissalDrag(translation: CGFloat, distance: CGFloat, time: TimeInterval) {
        guard state.phase == .interacting, distance > 0 else { return }
        if translation < 0 {
            let progress = 1 + Double(translation / distance)
            tracker.add(progress, at: time)
            track(progress: max(0, progress), offset: translation * 0.22)
        } else {
            tracker.add(1, at: time)
            track(progress: 1, offset: CGFloat(GestureMath.rubberBand(Double(translation), dimension: 400)))
        }
    }

    func endDismissalDrag() {
        guard state.phase == .interacting else { return }
        finishInteraction(present: GestureMath.shouldPresent(progress: model.progress, velocity: tracker.velocity))
    }

    // MARK: Internals

    func anchorBecameReady() {
        if wantsPresentation && host == nil { schedulePresentation(animated: true) }
    }

    private func track(progress: Double, offset: CGFloat) {
        // An interactive spring keeps up with the finger and hands its velocity to the release spring.
        withAnimation(.interactiveSpring(response: 0.16, dampingFraction: 0.86, blendDuration: 0.2)) {
            model.progress = progress
            model.dragOffset = offset
        }
    }

    private func finishInteraction(present: Bool) {
        if present {
            wantsPresentation = true
            onPresentationChange?(true)
            animate(to: true, animated: true)
        } else {
            wantsPresentation = false
            onPresentationChange?(false)
            animate(to: false, animated: true, carryOffset: true)
        }
    }

    private var reduceMotion: Bool {
        configuration.forceReducedMotion || UIAccessibility.isReduceMotionEnabled
    }

    private func animation(presenting: Bool) -> Animation {
        if reduceMotion { return .easeInOut(duration: 0.22) }
        let motion = configuration.motion.validated
        return presenting
            ? .spring(response: motion.response, dampingFraction: motion.dampingFraction)
            : .spring(response: motion.dismissalDuration, dampingFraction: 1)
    }

    private func settleTime(presenting: Bool) -> Double {
        if reduceMotion { return 0.22 }
        let motion = configuration.motion.validated
        return presenting ? motion.response * 1.5 : motion.dismissalDuration * 1.1
    }

    private func animate(to presented: Bool, animated: Bool, carryOffset: Bool = false) {
        let token = state.request(presented)
        model.isInteractive = presented
        // Block late taps while closing at the UIKit level. Toggling SwiftUI hit testing under an in-flight
        // touch leaves its gesture state stale and swallows the next tap after a reopen.
        host?.view.isUserInteractionEnabled = presented
        let finish: () -> Void = { [weak self] in self?.complete(token: token, presented: presented) }
        let changes = { [model] in
            model.progress = presented ? 1 : 0
            // A released swipe keeps travelling the way it was going instead of snapping back.
            model.dragOffset = presented ? 0 : (carryOffset ? min(0, model.dragOffset) - 40 : 0)
        }
        guard animated else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, changes)
            finish()
            return
        }
        let animation = animation(presenting: presented)
        if #available(iOS 17.0, *) {
            withAnimation(animation, completionCriteria: .logicallyComplete, changes) {
                MainActor.assumeIsolated { finish() }
            }
        } else {
            withAnimation(animation, changes)
        }
        // SwiftUI does not always deliver completions for animations that merged with an interrupted one. A timed
        // fallback guarantees the transparent host can never linger over the app; the generation token makes
        // whichever arrives second a no-op.
        let delay = settleTime(presenting: presented) + 0.1
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            finish()
        }
        if presented { model.focusRequest &+= 1 }
    }

    private func complete(token: UInt, presented: Bool) {
        guard state.complete(generation: token), !presented, let host else { return }
        self.host = nil
        host.dismiss(animated: false) { [weak self] in
            guard let self else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { self.model.dragOffset = 0 }
            self.onDismiss?()
            // A presentation requested during the final frames starts fresh.
            if self.wantsPresentation { self.schedulePresentation(animated: true) }
        }
    }

    private func schedulePresentation(animated: Bool) {
        retry?.cancel()
        retry = Task { @MainActor [weak self] in
            await Task.yield()
            // UIKit refuses to present during another transition; poll briefly until it settles.
            for _ in 0..<100 {
                guard let self, !Task.isCancelled, self.wantsPresentation else { return }
                if self.host != nil { return }
                if let presenter = self.resolvePresenter(), self.presentHost(from: presenter, animatedIn: animated) { return }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Presents the transparent host at progress 0. When `animatedIn` is true, springs it open afterwards.
    private func presentHost(from presenter: UIViewController, animatedIn: Bool) -> Bool {
        guard presenter.viewIfLoaded?.window != nil, !presenter.isBeingDismissed, !presenter.isBeingPresented,
              presenter.transitionCoordinator == nil else { return false }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            model.progress = 0
            model.dragOffset = 0
        }
        let newHost = CenterHostController(model: model)
        host = newHost
        refreshRoot()
        presenter.present(newHost, animated: false) { [weak self, weak newHost] in
            guard animatedIn, let self, let newHost, self.host === newHost, self.wantsPresentation,
                  self.state.phase != .interacting else { return }
            self.animate(to: true, animated: true)
        }
        return true
    }

    private func resolvePresenter() -> UIViewController? {
        var presenter: UIViewController?
        if let explicitPresenter, explicitPresenter.viewIfLoaded?.window != nil {
            presenter = explicitPresenter
        } else if let anchor, anchor.viewIfLoaded?.window != nil {
            presenter = anchor.parent ?? anchor
        } else {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
            presenter = window?.rootViewController
        }
        while let presented = presenter?.presentedViewController, !presented.isBeingDismissed {
            presenter = presented
        }
        return presenter
    }

    private func refreshRoot() {
        guard let host else { return }
        host.rootView = CenterRoot(model: model, pages: pages, configuration: configuration,
                                   environment: inheritedEnvironment)
    }

    func tearDown() {
        retry?.cancel()
        wantsPresentation = false
        state = PresentationState()
        host?.dismiss(animated: false)
        host = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            model.progress = 0
            model.dragOffset = 0
        }
    }
}

/// Target-action and delegate glue for `addPullDownGesture(to:)`.
@MainActor
private final class PullDownGestureTarget: NSObject, UIGestureRecognizerDelegate {
    weak var controller: LiquidControlCenterController?
    weak var recognizer: UIPanGestureRecognizer?
    private var active = false

    init(controller: LiquidControlCenterController) { self.controller = controller }

    @objc func handle(_ recognizer: UIPanGestureRecognizer) {
        guard let controller, let window = recognizer.view?.window else { return }
        let distance = pullDistance(for: window.bounds.height)
        switch recognizer.state {
        case .began:
            active = controller.beginPull()
        case .changed where active:
            controller.updatePull(translation: recognizer.translation(in: window).y, distance: distance,
                                  time: CACurrentMediaTime())
        case .ended where active, .cancelled where active, .failed where active:
            active = false
            controller.endPull()
        default: break
        }
    }

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let pan = recognizer as? UIPanGestureRecognizer, controller?.isPresented == false else { return false }
        let velocity = pan.velocity(in: pan.view)
        return velocity.y > abs(velocity.x)
    }
}

func pullDistance(for height: CGFloat) -> CGFloat { min(420, max(240, height * 0.42)) }

private struct PullDownGesture: ViewModifier {
    let isEnabled: Bool
    @Environment(\.liquidControlCenter) private var controller
    @State private var active: Bool?

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .global)
                .onChanged { value in
                    guard let controller else { return }
                    if active == nil {
                        let t = value.translation
                        active = t.height > abs(t.width) && !controller.isPresented && controller.beginPull()
                    }
                    guard active == true else { return }
                    controller.updatePull(translation: value.translation.height,
                                          distance: pullDistance(for: screenHeight), time: CACurrentMediaTime())
                }
                .onEnded { _ in
                    if active == true { controller?.endPull() }
                    active = nil
                },
            including: isEnabled && controller != nil ? .all : .subviews)
    }

    private var screenHeight: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?
            .windows.first?.bounds.height ?? 800
    }
}

// MARK: - Host

/// The hosted tree: backdrop plus controls, both reading the same progress.
struct CenterRoot: View {
    @ObservedObject var model: CenterModel
    var pages: [ControlCenterPage] = []
    var configuration = ControlCenterConfiguration()
    var environment = CenterEnvironment()
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            CenterBackdrop(progress: model.progress, backdrop: configuration.backdrop.validated,
                           opaque: reduceTransparency || configuration.forceReducedTransparency)
            ControlCenterView(model: model, pages: pages, configuration: configuration)
        }
        .modifier(InheritedEnvironment(environment: environment))
        .environment(\.colorScheme, .dark)
    }
}

private struct InheritedEnvironment: ViewModifier {
    let environment: CenterEnvironment
    func body(content: Content) -> some View {
        content.transformEnvironment(\.self) { values in
            if let direction = environment.layoutDirection { values.layoutDirection = direction }
            if let size = environment.dynamicTypeSize { values.dynamicTypeSize = size }
            if let locale = environment.locale { values.locale = locale }
        }
    }
}

final class CenterHostController: UIHostingController<CenterRoot> {
    init(model: CenterModel) {
        super.init(rootView: CenterRoot(model: model))
        modalPresentationStyle = .overFullScreen
        modalPresentationCapturesStatusBarAppearance = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityViewIsModal = true
    }
}
#endif
