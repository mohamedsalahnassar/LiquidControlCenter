#if os(iOS)
import SwiftUI

/// An app-defined control. Keep IDs stable across renders; state belongs to the host app.
@MainActor
public struct ControlTile: Identifiable {
    public let id: String
    public var size: ControlTileSize
    public var position: ControlTilePosition?
    public var tint: Color?
    public var isEnabled: Bool
    public var accessibilityLabel: String
    var content: (ControlTileContext) -> AnyView
    var expandedContent: ((ControlTileContext) -> AnyView)?
    var action: (() -> Void)?
    var expandedHeight: CGFloat

    /// For interactive content (sliders, groups of buttons), omit `action` to avoid nesting buttons.
    public init<Content: View>(
        _ id: String, size: ControlTileSize = .small, position: ControlTilePosition? = nil,
        label: String, tint: Color? = nil, isEnabled: Bool = true,
        action: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (ControlTileContext) -> Content
    ) {
        self.id = id
        self.size = size
        self.position = position
        self.accessibilityLabel = label
        self.tint = tint
        self.isEnabled = isEnabled
        self.action = action
        self.content = { AnyView(content($0)) }
        self.expandedHeight = 360
    }

    /// Hold to expand, or call `context.expand()` from a custom button.
    public func expanded<Content: View>(height: CGFloat = 360,
        @ViewBuilder content: @escaping (ControlTileContext) -> Content
    ) -> Self {
        var copy = self
        copy.expandedHeight = height.isFinite ? min(1200, max(120, height)) : 360
        copy.expandedContent = { AnyView(content($0)) }
        return copy
    }
}

/// Actions available to both the compact and expanded content of a control.
@MainActor
public struct ControlTileContext {
    public let isExpanded: Bool
    public let expand: () -> Void
    public let collapse: () -> Void
    public let dismiss: () -> Void
}

@resultBuilder
public enum ControlCenterBuilder {
    public static func buildExpression(_ tile: ControlTile) -> [ControlTile] { [tile] }
    public static func buildExpression(_ tiles: [ControlTile]) -> [ControlTile] { tiles }
    public static func buildBlock(_ components: [ControlTile]...) -> [ControlTile] { components.flatMap { $0 } }
    public static func buildOptional(_ component: [ControlTile]?) -> [ControlTile] { component ?? [] }
    public static func buildEither(first: [ControlTile]) -> [ControlTile] { first }
    public static func buildEither(second: [ControlTile]) -> [ControlTile] { second }
    public static func buildArray(_ components: [[ControlTile]]) -> [ControlTile] { components.flatMap { $0 } }
    public static func buildLimitedAvailability(_ component: [ControlTile]) -> [ControlTile] { component }
}

/// Optional groups shown in the trailing page rail.
@MainActor
public struct ControlCenterPage: Identifiable {
    public let id: String
    public var title: String
    public var systemImage: String
    public var tiles: [ControlTile]
    public init(_ id: String, title: String, systemImage: String,
                @ControlCenterBuilder tiles: () -> [ControlTile]) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.tiles = tiles()
    }
}

public struct ControlCenterConfiguration {
    public var columns: Int = 4
    public var spacing: CGFloat = 14
    public var horizontalPadding: CGFloat = 28
    public var maximumWidth: CGFloat = 430
    public var title: String = "Control Center"
    public var motion: ControlCenterMotion = .default
    public var dimmingOpacity: Double = 0.22
    public var dismissOnBackgroundTap: Bool = true
    public var hapticsEnabled: Bool = true
    /// Exercise the pre-iOS 26 material path on newer devices as well.
    public var forceFallback: Bool = false
    public var forceReducedMotion: Bool = false
    public var forceReducedTransparency: Bool = false
    public init() {}
}

extension Array where Element == ControlTile {
    /// Duplicate IDs would corrupt SwiftUI identity. Deterministically keep the first.
    var uniqueTiles: [ControlTile] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}
#endif
