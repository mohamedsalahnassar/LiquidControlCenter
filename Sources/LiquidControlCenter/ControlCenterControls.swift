#if os(iOS)
import SwiftUI

/// A compact icon or a wide icon-and-label face. Tile sizing and glass are handled by the center.
public struct ControlCenterLabel: View {
    let title: String
    let systemImage: String
    let subtitle: String?
    let showsTitle: Bool
    public init(_ title: String, systemImage: String, subtitle: String? = nil, showsTitle: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.showsTitle = showsTitle
    }
    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).font(.system(size: 25, weight: .medium))
            if showsTitle {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    if let subtitle { Text(subtitle).font(.caption).opacity(0.7) }
                }
                .lineLimit(2).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
        }
        .padding(showsTitle ? 16 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle ?? "")
    }
}

/// A directly draggable, VoiceOver-adjustable vertical fill control. Its binding belongs to your app.
public struct ControlCenterSlider: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let title: String
    private let systemImage: String
    private let tint: Color
    private let onEditingChanged: (Bool) -> Void
    @GestureState private var dragging = false
    @Environment(\.isEnabled) private var isEnabled

    public init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double> = 0...1,
                systemImage: String, tint: Color = .white,
                onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.title = title
        self._value = value
        self.range = range
        self.systemImage = systemImage
        self.tint = tint
        self.onEditingChanged = onEditingChanged
    }

    public var body: some View {
        GeometryReader { geometry in
            let fraction = ControlValue.normalized(value, in: range)
            ZStack(alignment: .bottom) {
                Rectangle().fill(tint).frame(height: geometry.size.height * fraction)
                Image(systemName: systemImage)
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(fraction > 0.22 ? Color.black.opacity(0.65) : .white)
                    .padding(.bottom, 22)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .updating($dragging) { _, state, _ in state = true }
                .onChanged { gesture in
                    guard isEnabled, geometry.size.height > 0 else { return }
                    value = ControlValue.value(at: 1 - gesture.location.y / geometry.size.height, in: range)
                })
        }
        .onChange(of: dragging) { onEditingChanged($0) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(Int(ControlValue.normalized(value, in: range) * 100)) percent")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            let delta = direction == .increment ? 0.05 : -0.05
            value = ControlValue.value(at: ControlValue.normalized(value, in: range) + delta, in: range)
        }
    }
}
#endif
