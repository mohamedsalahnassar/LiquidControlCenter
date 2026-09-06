#if os(iOS)
import SwiftUI
import UIKit

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
}

private struct ControlCenterPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let pages: [ControlCenterPage]
    let configuration: ControlCenterConfiguration
    let onDismiss: () -> Void
    @Environment(\.self) private var environment

    func body(content: Content) -> some View {
        content.background {
            PresentationAnchor(isPresented: $isPresented, requested: isPresented, pages: pages, configuration: configuration,
                               environment: environment, onDismiss: onDismiss)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}

private struct PresentationAnchor: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let requested: Bool
    let pages: [ControlCenterPage]
    let configuration: ControlCenterConfiguration
    let environment: EnvironmentValues
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> AnchorController {
        let anchor = AnchorController()
        context.coordinator.anchor = anchor
        anchor.onReady = { [weak coordinator = context.coordinator] in coordinator?.schedule() }
        return anchor
    }
    func updateUIViewController(_ uiViewController: AnchorController, context: Context) {
        context.coordinator.update(self)
    }
    static func dismantleUIViewController(_ uiViewController: AnchorController, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    @MainActor final class Coordinator {
        weak var anchor: AnchorController?
        private var source: PresentationAnchor?
        private var host: CenterHostController?
        private let model = CenterPresentationModel()
        private var state = PresentationState()
        private var pending: Task<Void, Never>?
        private var detached = false

        func update(_ source: PresentationAnchor) {
            self.source = source
            if let host { host.rootView = root(source); host.configuration = source.configuration }
            schedule()
        }

        private func root(_ source: PresentationAnchor) -> AnyView {
            AnyView(ControlCenterView(presentation: model, pages: source.pages,
                                      configuration: source.configuration, dismiss: { [weak self] in self?.close() })
                .environment(\.self, source.environment)
                .environment(\.colorScheme, .dark))
        }

        func schedule() {
            pending?.cancel()
            pending = Task { @MainActor [weak self] in
                await Task.yield()
                guard let self else { return }
                while !Task.isCancelled && !self.detached {
                    if self.reconcile() { return }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }

        /// Returns false only while the anchor or another UIKit transition is not yet ready.
        private func reconcile() -> Bool {
            guard let source else { return true }

            if source.requested {
                if let host {
                    guard !host.isBeingDismissed else { return false }
                    guard state.phase == .dismissing else { return true }
                    animate(show: true, host: host)
                    return true
                }
                guard let anchor, anchor.viewIfLoaded?.window != nil,
                      var presenter = anchor.parent else { return false }
                while let presented = presenter.presentedViewController {
                    guard !presented.isBeingDismissed && !presented.isBeingPresented else { return false }
                    presenter = presented
                }
                guard presenter.viewIfLoaded?.window != nil, !presenter.isBeingDismissed,
                      presenter.transitionCoordinator == nil else { return false }
                let newHost = CenterHostController(rootView: root(source), configuration: source.configuration)
                host = newHost
                _ = state.request(true)
                presenter.present(newHost, animated: false) { [weak self, weak newHost] in
                    guard let self, let newHost, self.host === newHost else { return }
                    self.animate(show: self.source?.requested == true, host: newHost)
                }
            } else if let host, state.phase != .dismissing, state.phase != .hidden {
                guard !host.isBeingPresented else { return false }
                animate(show: false, host: host)
            }
            return true
        }

        private func animate(show: Bool, host: CenterHostController) {
            let token = state.request(show)
            model.isVisible = show
            let reduced = (source?.environment.accessibilityReduceMotion ?? UIAccessibility.isReduceMotionEnabled) || host.configuration.forceReducedMotion
            let opaque = (source?.environment.accessibilityReduceTransparency ?? UIAccessibility.isReduceTransparencyEnabled) || host.configuration.forceReducedTransparency
            host.animateBackdrop(visible: show, reduceMotion: reduced, reduceTransparency: opaque) { [weak self, weak host] in
                guard let self, let host, self.host === host,
                      self.state.complete(generation: token), !show else { return }
                host.dismiss(animated: false) { [weak self] in
                    guard let self else { return }
                    self.host = nil
                    self.source?.onDismiss()
                    self.schedule()
                }
            }
        }

        private func close() {
            guard let source else { return }
            source.isPresented = false
            self.source = source
            schedule()
        }

        func tearDown() {
            detached = true
            pending?.cancel()
            pending = nil
            anchor?.onReady = nil
            model.isVisible = false
            host?.dismiss(animated: false)
            host = nil
            source = nil
        }
    }
}

private final class AnchorController: UIViewController {
    var onReady: (() -> Void)?
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

private final class CenterHostController: UIViewController {
    var configuration: ControlCenterConfiguration
    private let blur = UIVisualEffectView(effect: nil)
    private let dim = UIView()
    private let hosting: UIHostingController<AnyView>
    var rootView: AnyView {
        get { hosting.rootView }
        set { hosting.rootView = newValue }
    }
    override var prefersStatusBarHidden: Bool { true }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    init(rootView: AnyView, configuration: ControlCenterConfiguration) {
        self.configuration = configuration
        self.hosting = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalPresentationCapturesStatusBarAppearance = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityViewIsModal = true
        blur.isUserInteractionEnabled = false
        dim.isUserInteractionEnabled = false
        dim.backgroundColor = .black
        dim.alpha = 0
        addChild(hosting)
        hosting.view.backgroundColor = .clear
        for child in [blur, dim, hosting.view!] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
            NSLayoutConstraint.activate([
                child.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                child.topAnchor.constraint(equalTo: view.topAnchor),
                child.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
        hosting.didMove(toParent: self)
    }

    func animateBackdrop(visible: Bool, reduceMotion: Bool, reduceTransparency: Bool,
                         completion: @escaping () -> Void) {
        let motion = configuration.motion.validated
        let duration = reduceMotion ? 0.18 : (visible ? motion.backdropDuration : motion.dismissalDuration)
        let opacity = configuration.dimmingOpacity.isFinite ? min(0.85, max(0, configuration.dimmingOpacity)) : 0.22
        // Keep UIVisualEffectView alpha at 1; animate the effect itself for live backdrop interpolation.
        UIView.animate(withDuration: duration, delay: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
            self.blur.effect = visible && !reduceTransparency ? UIBlurEffect(style: .systemUltraThinMaterialDark) : nil
            self.dim.alpha = visible ? (reduceTransparency ? 1 : opacity) : 0
        } completion: { _ in completion() }
    }
}
#endif
