import SwiftUI
import LiquidControlCenter

/// Deliberately small presentation anchor and mutable content for regression tests.
struct IntegrationHarness: View {
    @State private var presented = false
    @State private var showRemovable = true
    @State private var value = 0.5
    @State private var dismissals = 0
    @State private var cycleFinished = false
    @State private var sheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Button("Open harness") { presented = true }
                Button("Open sheet") { sheet = true }
                Text("Dismissals: \(dismissals)")
                Text(cycleFinished ? "Cycle finished" : "Ready")
                Text("Slider: \(Int(value * 100))")
                Text("Small anchor")
                    .frame(width: 80, height: 30)
                    .liquidControlCenter(isPresented: $presented, onDismiss: { dismissals += 1 }) {
                        ControlTile("cycle", size: .wide, label: "Interrupt dismissal", action: interruptDismissal) { _ in
                            ControlCenterLabel("Interrupt dismissal", systemImage: "arrow.clockwise", showsTitle: true)
                        }
                        if showRemovable {
                            ControlTile("removable", size: .wide, label: "Removable") { context in
                                Button("Expand removable", action: context.expand)
                            }.expanded(height: 240) { _ in
                                Button("Remove this tile") { showRemovable = false }
                            }
                        }
                        ControlTile("slider", size: .tall, label: "Test slider") { _ in
                            ControlCenterSlider("Test slider", value: $value, systemImage: "sun.max.fill")
                        }.expanded { _ in
                            Slider(value: $value).accessibilityLabel("Expanded slider")
                        }
                        ControlTile("disabled", label: "Disabled action", isEnabled: false, action: { value = 0 }) { _ in
                            ControlCenterLabel("Disabled action", systemImage: "lock.fill")
                        }
                    }
            }
            .navigationTitle("Integration harness")
            .sheet(isPresented: $sheet) { SheetHarness() }
        }
    }

    private func interruptDismissal() {
        presented = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            presented = true
            try? await Task.sleep(for: .milliseconds(600))
            cycleFinished = true
        }
    }
}

private struct SheetHarness: View {
    @State private var presented = false
    var body: some View {
        Button("Open center over sheet") { presented = true }
            .liquidControlCenter(isPresented: $presented) {
                ControlTile("sheet", size: .wide, label: "Sheet control") { _ in Text("Above the sheet") }
            }
    }
}

// MARK: - UIKit host

/// A plain UIKit screen, as a React Native or Flutter plugin would provide. No SwiftUI view tree is required:
/// the controller presents itself, and app state is pushed in by rebuilding `pages`.
final class UIKitHostController: UIViewController {
    private var flashlight = false
    private var dismissals = 0
    private let status = UILabel()
    private lazy var center = LiquidControlCenterController(pages: makePages())

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemIndigo

        let pullArea = UILabel()
        pullArea.text = "Pull down here"
        pullArea.textAlignment = .center
        pullArea.textColor = .white
        pullArea.isUserInteractionEnabled = true
        pullArea.accessibilityIdentifier = "uikit.pull"
        center.addPullDownGesture(to: pullArea)

        let open = UIButton(configuration: .filled(), primaryAction: UIAction(title: "Open from UIKit") { [weak self] _ in
            guard let self else { return }
            self.center.present(from: self)
        })
        open.accessibilityIdentifier = "uikit.open"

        status.textColor = .white
        status.accessibilityIdentifier = "uikit.status"
        center.onDismiss = { [weak self] in
            guard let self else { return }
            self.dismissals += 1
            self.updateStatus()
        }
        updateStatus()

        let stack = UIStackView(arrangedSubviews: [pullArea, open, status])
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            pullArea.heightAnchor.constraint(equalToConstant: 120)
        ])
    }

    private func updateStatus() {
        status.text = "Flashlight \(flashlight ? "on" : "off") · Dismissals: \(dismissals)"
    }

    private func makePages() -> [ControlCenterPage] {
        [ControlCenterPage("uikit", title: "From UIKit", systemImage: "square.stack.3d.up.fill") {
            ControlTile("uikit-flashlight", label: "Flashlight", tint: flashlight ? .orange : nil,
                        action: { [weak self] in
                            guard let self else { return }
                            self.flashlight.toggle()
                            self.center.pages = self.makePages()
                            self.updateStatus()
                        }) { [flashlight] _ in
                ControlCenterLabel("Flashlight", systemImage: flashlight ? "flashlight.on.fill" : "flashlight.off.fill")
                    .accessibilityValue(flashlight ? "On" : "Off")
            }
            ControlTile("uikit-info", size: .wide, label: "Host") { _ in
                ControlCenterLabel("UIKit host", systemImage: "uiwindow.split.2x1", subtitle: "No SwiftUI tree", showsTitle: true)
            }
        }]
    }
}

struct UIKitHostScreen: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIKitHostController { UIKitHostController() }
    func updateUIViewController(_ controller: UIKitHostController, context: Context) {}
}
