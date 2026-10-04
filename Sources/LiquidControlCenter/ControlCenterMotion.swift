import Foundation

/// Adjustable motion values. Timings are approximations of the system presentation.
///
/// The backdrop, dimming, chrome, and every tile are driven by one shared presentation progress,
/// so they can never drift apart, and the same value can follow a finger during interactive gestures.
public struct ControlCenterMotion: Equatable, Sendable {
    /// Response of the opening spring, in seconds.
    public var response: Double
    /// Damping of the opening spring. Values below 1 settle with a small overshoot.
    public var dampingFraction: Double
    /// Delay added per grid row while revealing, in seconds at the default response.
    public var stagger: Double
    /// Response of the closing spring, in seconds. Closing never overshoots.
    public var dismissalDuration: Double
    private var legacyBackdropDuration: Double

    public init(response: Double = 0.5, dampingFraction: Double = 0.84,
                stagger: Double = 0.026, backdropDuration: Double = 0.32,
                dismissalDuration: Double = 0.34) {
        self.response = response
        self.dampingFraction = dampingFraction
        self.stagger = stagger
        self.legacyBackdropDuration = backdropDuration
        self.dismissalDuration = dismissalDuration
    }

    /// Unused: the backdrop now shares the presentation spring.
    @available(*, deprecated, message: "The backdrop now shares the presentation spring; this value is ignored.")
    public var backdropDuration: Double {
        get { legacyBackdropDuration }
        set { legacyBackdropDuration = newValue }
    }

    public static let `default` = Self()

    var validated: Self {
        .init(response: Self.clamp(response, 0.15...1, fallback: 0.5),
              dampingFraction: Self.clamp(dampingFraction, 0.65...1, fallback: 0.84),
              stagger: Self.clamp(stagger, 0...0.06, fallback: 0.026),
              backdropDuration: legacyBackdropDuration,
              dismissalDuration: Self.clamp(dismissalDuration, 0.15...0.8, fallback: 0.34))
    }

    /// Delay of a grid row, as a fraction of the shared progress.
    func rowDelay(_ row: Int, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 0 }
        let motion = validated
        return min(0.35, Double(max(0, row)) * motion.stagger / motion.response)
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}

/// How a single tile looks at a given presentation progress.
struct TileReveal: Equatable {
    var opacity: Double
    var scale: Double
    var offset: Double

    /// `progress` is the shared presentation value. It may exceed 1 while the opening spring overshoots,
    /// which is passed through so tiles settle with the same small overshoot.
    static func at(progress: Double, row: Int, delay: Double, reduceMotion: Bool) -> TileReveal {
        let progress = progress.isFinite ? progress : 0
        if reduceMotion {
            return .init(opacity: min(1, max(0, progress)), scale: 1, offset: 0)
        }
        let delay = min(0.9, max(0, delay))
        let local = max(0, (progress - delay) / (1 - delay))
        let fade = min(1, max(0, (local - 0.08) / 0.55))
        // Lower rows travel further, so the grid unfolds downward from the top edge.
        let travel = 26 + Double(max(0, row)) * 12
        return .init(opacity: fade * fade * (3 - 2 * fade),
                     scale: 0.84 + 0.16 * local,
                     offset: -travel * (1 - local))
    }
}

/// Pure gesture helpers shared by the interactive presentation and dismissal.
enum GestureMath {
    /// iOS-style resistance: grows without bound but ever more slowly.
    static func rubberBand(_ offset: Double, dimension: Double = 600, coefficient: Double = 0.55) -> Double {
        guard offset.isFinite, dimension > 0 else { return 0 }
        let magnitude = abs(offset)
        let banded = (1 - 1 / (magnitude * coefficient / dimension + 1)) * dimension
        return offset < 0 ? -banded : banded
    }

    /// Decide where a released gesture should settle, projecting momentum like a UIScrollView does.
    /// - Parameters:
    ///   - progress: Current presentation progress (0 hidden, 1 shown).
    ///   - velocity: Progress per second.
    static func shouldPresent(progress: Double, velocity: Double) -> Bool {
        guard progress.isFinite else { return false }
        let velocity = velocity.isFinite ? velocity : 0
        if abs(velocity) > 1.6 { return velocity > 0 }
        // Project with a deceleration rate of 0.998/ms.
        let projected = progress + velocity * 0.998 / (1 - 0.998) / 1000
        return projected > 0.5
    }

    /// Normalized spring velocity SwiftUI expects: units of "remaining distance per second".
    static func relativeVelocity(_ velocity: Double, from: Double, to: Double) -> Double {
        let distance = to - from
        guard abs(distance) > 0.001, velocity.isFinite else { return 0 }
        return min(30, max(-30, velocity / distance))
    }
}

/// Estimates velocity from recent samples. Works on iOS 16, where `DragGesture.Value.velocity` is unavailable.
struct VelocityTracker {
    private var samples: [(time: TimeInterval, value: Double)] = []

    mutating func reset() { samples.removeAll(keepingCapacity: true) }

    mutating func add(_ value: Double, at time: TimeInterval) {
        samples.append((time, value))
        samples.removeAll { time - $0.time > 0.1 }
    }

    /// Units per second over the last ~100 ms.
    var velocity: Double {
        guard let first = samples.first, let last = samples.last, last.time - first.time > 0.008 else { return 0 }
        return (last.value - first.value) / (last.time - first.time)
    }
}

/// Generation tokens prevent obsolete animation completions from dismissing a reopened center.
struct PresentationState: Equatable {
    enum Phase: Equatable { case hidden, presenting, presented, interacting, dismissing }
    private(set) var phase: Phase = .hidden
    private(set) var generation: UInt = 0

    var isVisible: Bool { phase != .hidden }

    mutating func request(_ presented: Bool) -> UInt {
        switch (presented, phase) {
        case (true, .hidden), (true, .dismissing), (true, .interacting):
            generation &+= 1
            phase = .presenting
        case (false, .presented), (false, .presenting), (false, .interacting):
            generation &+= 1
            phase = .dismissing
        default: break
        }
        return generation
    }

    /// A finger took over. Any in-flight completion becomes obsolete.
    mutating func beginInteraction() -> UInt {
        generation &+= 1
        phase = .interacting
        return generation
    }

    @discardableResult
    mutating func complete(generation token: UInt) -> Bool {
        guard generation == token else { return false }
        switch phase {
        case .presenting: phase = .presented
        case .dismissing: phase = .hidden
        default: return false
        }
        return true
    }
}

/// Normalizes arbitrary model values for the vertical control, including invalid external writes.
enum ControlValue {
    static func normalized(_ value: Double, in range: ClosedRange<Double>) -> Double {
        guard value.isFinite, range.lowerBound.isFinite, range.upperBound.isFinite,
              range.upperBound > range.lowerBound else { return 0 }
        let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return fraction.isFinite ? min(1, max(0, fraction)) : 0
    }

    static func value(at fraction: Double, in range: ClosedRange<Double>) -> Double {
        guard range.lowerBound.isFinite, range.upperBound.isFinite else { return 0 }
        let fraction = fraction.isFinite ? min(1, max(0, fraction)) : 0
        return range.lowerBound * (1 - fraction) + range.upperBound * fraction
    }
}
