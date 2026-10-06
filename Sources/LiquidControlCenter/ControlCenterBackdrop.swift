import Foundation

/// How the app behind the Control Center is obscured while it is open.
///
/// A live blur, an optional Liquid Glass layer, and black dimming, all following the presentation progress so they
/// arrive and leave with the tiles. Reduce Transparency replaces all three with an opaque scrim.
public struct ControlCenterBackdrop: Equatable, Sendable {
    /// Liquid Glass laid over the whole app behind the center.
    public enum Glass: String, CaseIterable, Sendable {
        /// No glass: the blur and dimming alone.
        case none
        /// Keeps the app visible, adding Liquid Glass light and lensing at the screen edges.
        case clear
        /// Frosts the app in Liquid Glass's own tone.
        case regular
    }

    /// Strength of the live blur, from 0 (the app stays sharp) to 1 (the full material blur).
    public var blur: Double
    /// Drawn by LiquidGlassKit on iOS 26 and later. Earlier systems show the blur and dimming alone.
    public var glass: Glass
    /// Black dimming over the blur and glass, from 0 to 0.85.
    public var dimming: Double

    public init(blur: Double = 0.45, glass: Glass = .clear, dimming: Double = 0.12) {
        self.blur = blur
        self.glass = glass
        self.dimming = dimming
    }

    /// A translucent blur under clear Liquid Glass, so the app behind stays recognizable. The default.
    public static let liquidGlass = Self()
    /// The same translucent blur without glass.
    public static let translucent = Self(blur: 0.45, glass: .none, dimming: 0.15)
    /// The full material blur with stronger dimming, the default before Liquid Glass backdrops.
    public static let standard = Self(blur: 1, glass: .none, dimming: 0.22)

    var validated: Self {
        .init(blur: blur.isFinite ? min(1, max(0, blur)) : Self.liquidGlass.blur,
              glass: glass,
              dimming: dimming.isFinite ? min(0.85, max(0, dimming)) : Self.liquidGlass.dimming)
    }
}
