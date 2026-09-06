import Foundation

/// Adjustable motion values. Timings are approximations of the system presentation.
public struct ControlCenterMotion: Equatable, Sendable {
    public var response: Double
    public var dampingFraction: Double
    public var stagger: Double
    public var backdropDuration: Double
    public var dismissalDuration: Double

    public init(response: Double = 0.48, dampingFraction: Double = 0.82,
                stagger: Double = 0.018, backdropDuration: Double = 0.32,
                dismissalDuration: Double = 0.24) {
        self.response = response
        self.dampingFraction = dampingFraction
        self.stagger = stagger
        self.backdropDuration = backdropDuration
        self.dismissalDuration = dismissalDuration
    }

    public static let `default` = Self()

    var validated: Self {
        .init(response: Self.clamp(response, 0.15...1, fallback: 0.48),
              dampingFraction: Self.clamp(dampingFraction, 0.65...1, fallback: 0.82),
              stagger: Self.clamp(stagger, 0...0.06, fallback: 0.018),
              backdropDuration: Self.clamp(backdropDuration, 0.1...0.6, fallback: 0.32),
              dismissalDuration: Self.clamp(dismissalDuration, 0.1...0.6, fallback: 0.24))
    }

    func delay(for index: Int, reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : min(0.12, Double(max(0, index)) * validated.stagger)
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}

/// Generation tokens prevent obsolete animation completions from dismissing a reopened center.
struct PresentationState: Equatable {
    enum Phase: Equatable { case hidden, presenting, presented, dismissing }
    private(set) var phase: Phase = .hidden
    private(set) var generation: UInt = 0

    mutating func request(_ presented: Bool) -> UInt {
        if presented && (phase == .hidden || phase == .dismissing) {
            generation &+= 1
            phase = .presenting
        } else if !presented && (phase == .presented || phase == .presenting) {
            generation &+= 1
            phase = .dismissing
        }
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
