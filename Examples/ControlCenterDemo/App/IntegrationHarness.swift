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
