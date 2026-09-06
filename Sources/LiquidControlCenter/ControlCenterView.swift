#if os(iOS)
import SwiftUI
import UIKit

@MainActor
final class CenterPresentationModel: ObservableObject {
    @Published var isVisible = false
}

struct TileLayout: Layout {
    let items: [ControlGridItem]
    let columns: Int
    let spacing: CGFloat
    let rightToLeft: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(1, proposal.width ?? 320)
        let frames = frames(width: width)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(width: CGFloat) -> [CGRect] {
        let count = ControlCenterGrid.columnCount(requested: columns, width: width, spacing: spacing)
        let cell = max(1, (width - CGFloat(count - 1) * spacing) / CGFloat(count))
        return ControlCenterGrid.placements(for: items, columns: count).map {
            $0.frame(cell: cell, spacing: spacing, width: width, rightToLeft: rightToLeft)
        }
    }
}

struct ControlCenterView: View {
    @ObservedObject var presentation: CenterPresentationModel
    let pages: [ControlCenterPage]
    let configuration: ControlCenterConfiguration
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || configuration.forceReducedMotion }
    @Environment(\.layoutDirection) private var layoutDirection
    @Namespace private var tileNamespace
    @State private var selectedPage: String?
    @State private var expandedID: String?
    @AccessibilityFocusState private var closeFocused: Bool
    @AccessibilityFocusState private var expandedCloseFocused: Bool

    private var uniquePages: [ControlCenterPage] {
        var ids = Set<String>()
        return pages.filter { ids.insert($0.id).inserted }
    }
    private var currentPage: ControlCenterPage? {
        uniquePages.first { $0.id == selectedPage } ?? uniquePages.first
    }
    private var tiles: [ControlTile] { currentPage?.tiles.uniqueTiles ?? [] }
    private var expandedTile: ControlTile? { tiles.first { $0.id == expandedID && $0.isEnabled && $0.expandedContent != nil } }
    private var motion: ControlCenterMotion { configuration.motion.validated }
    private var spring: Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .spring(response: motion.response, dampingFraction: motion.dampingFraction)
    }
    private var gap: CGFloat { configuration.spacing.isFinite ? min(32, max(4, configuration.spacing)) : 14 }
    private var padding: CGFloat { configuration.horizontalPadding.isFinite ? min(80, max(12, configuration.horizontalPadding)) : 28 }
    private var maxWidth: CGFloat { configuration.maximumWidth.isFinite ? min(1200, max(240, configuration.maximumWidth)) : 430 }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture {
                        if expandedID != nil { collapse() }
                        else if configuration.dismissOnBackgroundTap { dismiss() }
                    }
                    .accessibilityHidden(true)
                CenterGlassContainer(fallback: configuration.forceFallback) {
                    VStack(spacing: 20) {
                        header
                        ZStack(alignment: .trailing) {
                            ScrollView {
                                TileLayout(items: tiles.map { ControlGridItem(size: $0.size, position: $0.position) },
                                           columns: configuration.columns, spacing: gap,
                                           rightToLeft: layoutDirection == .rightToLeft) {
                                    ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                                        tileCell(tile, index: index)
                                    }
                                }
                                .padding(4)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if expandedID != nil { collapse() }
                                    else if configuration.dismissOnBackgroundTap { dismiss() }
                                }
                            }
                            .scrollIndicators(.hidden)
                            .scrollDisabled(expandedTile != nil)
                            .simultaneousGesture(DragGesture(minimumDistance: 40).onEnded { value in
                                guard let index = uniquePages.firstIndex(where: { $0.id == currentPage?.id }) else { return }
                                if abs(value.translation.height) < abs(value.translation.width) {
                                    let next = index + (value.translation.width < 0 ? 1 : -1)
                                    if uniquePages.indices.contains(next) { select(uniquePages[next]) }
                                }
                            })
                        }
                        .allowsHitTesting(expandedTile == nil)
                        .accessibilityHidden(expandedTile != nil)
                    }
                    .frame(maxWidth: maxWidth)
                    .padding(.horizontal, padding)
                    .padding(.top, 16)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                }
                .opacity(expandedTile == nil ? 1 : 0.08)
                .blur(radius: expandedTile == nil ? 0 : 5)
                .scaleEffect(expandedTile != nil && !reduceMotion ? 0.96 : 1)
                .allowsHitTesting(expandedTile == nil)
                .accessibilityHidden(expandedTile != nil)

                if uniquePages.count > 1 && expandedTile == nil {
                    pageRail
                        .frame(width: 28)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                // A separate container prevents the enlarged surface from uniting with the grid.
                if let tile = expandedTile {
                    CenterGlassContainer(fallback: configuration.forceFallback) {
                        expanded(tile, available: geometry.size)
                    }
                    .zIndex(2)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.controlCenterReduceTransparency, configuration.forceReducedTransparency)
        .environment(\.controlCenterReduceMotion, reduceMotion)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { expandedID != nil ? collapse() : dismiss() }
        .onChange(of: presentation.isVisible) { visible in
            if !visible { collapse() }
            else { closeFocused = true }
        }
        .onChange(of: expandedID) { expandedCloseFocused = $0 != nil }
        .onChange(of: tiles.map(\.id)) { _ in reconcileExpansion() }
        .onChange(of: tiles.map(\.isEnabled)) { _ in reconcileExpansion() }
        .onChange(of: tiles.map { $0.expandedContent != nil }) { _ in reconcileExpansion() }
        .onChange(of: currentPage?.id) { _ in collapse() }
    }

    private var header: some View {
        HStack {
            Text(currentPage?.title ?? configuration.title)
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .modifier(GlassSurface(radius: 22, fallback: configuration.forceFallback))
            }
            .accessibilityLabel("Close Control Center")
            .accessibilityIdentifier("control-center.close")
            .accessibilityFocused($closeFocused)
            .buttonStyle(ControlPressStyle())
        }
        .opacity(presentation.isVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: presentation.isVisible)
        .accessibilityHidden(expandedTile != nil)
    }


    private var pageRail: some View {
        VStack(spacing: 8) {
            ForEach(uniquePages) { page in
                Button { select(page) } label: {
                    Image(systemName: page.systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 28, height: 44)
                        .foregroundStyle(.white.opacity(currentPage?.id == page.id ? 1 : 0.4))
                }
                .accessibilityLabel(page.title)
                .accessibilityAddTraits(currentPage?.id == page.id ? .isSelected : [])
            }
        }
        .buttonStyle(.plain)
        .gesture(DragGesture(minimumDistance: 24).onEnded { value in
            guard let index = uniquePages.firstIndex(where: { $0.id == currentPage?.id }) else { return }
            let next = index + (value.translation.height < 0 ? 1 : -1)
            if uniquePages.indices.contains(next) { select(uniquePages[next]) }
        })
        .opacity(presentation.isVisible ? 1 : 0)
    }

    @ViewBuilder
    private func tileCell(_ tile: ControlTile, index: Int) -> some View {
        if expandedTile?.id == tile.id {
            Color.clear
        } else {
            compact(tile)
                .matchedGeometryEffect(id: tile.id, in: tileNamespace, properties: reduceMotion ? [] : .frame)
                .opacity(presentation.isVisible ? 1 : 0)
                .scaleEffect(presentation.isVisible || reduceMotion ? 1 : 0.86, anchor: .topTrailing)
                .offset(y: presentation.isVisible || reduceMotion ? 0 : -22)
                .animation(presentation.isVisible
                           ? spring.delay(motion.delay(for: index, reduceMotion: reduceMotion))
                           : .easeOut(duration: motion.dismissalDuration), value: presentation.isVisible)
        }
    }

    private func compact(_ tile: ControlTile) -> some View {
        TileInteraction(tile: tile, context: context(for: tile), fallback: configuration.forceFallback)
            .disabled(!tile.isEnabled)
            .opacity(tile.isEnabled ? 1 : 0.4)
            .accessibilityIdentifier("control-tile.\(tile.id)")
    }

    private func expanded(_ tile: ControlTile, available: CGSize) -> some View {
        VStack(spacing: 16) {
            ScrollView {
                if let content = tile.expandedContent { content(context(for: tile, expanded: true)) }
            }
            .scrollIndicators(.hidden)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(GlassSurface(radius: 44, tint: tile.tint, fallback: configuration.forceFallback))
            .matchedGeometryEffect(id: tile.id, in: tileNamespace, properties: reduceMotion ? [] : .frame)
            .frame(height: min(tile.expandedHeight, max(120, available.height - 160)))
            .accessibilityIdentifier("control-expanded.\(tile.id)")
            Button(action: collapse) {
                Image(systemName: "xmark").font(.system(size: 18, weight: .semibold))
                    .frame(width: 48, height: 48)
                    .modifier(GlassSurface(radius: 24, fallback: configuration.forceFallback))
            }
            .buttonStyle(ControlPressStyle())
            .accessibilityLabel("Collapse \(tile.accessibilityLabel)")
            .accessibilityFocused($expandedCloseFocused)
        }
        .frame(width: max(120, min(maxWidth - 16, available.width - 48)))
        .transition(.opacity)
    }

    private func context(for tile: ControlTile, expanded: Bool = false) -> ControlTileContext {
        .init(isExpanded: expanded, expand: {
            guard tile.isEnabled, tile.expandedContent != nil else { return }
            if configuration.hapticsEnabled { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
            withAnimation(spring) { expandedID = tile.id }
        }, collapse: collapse, dismiss: dismiss)
    }

    private func collapse() { withAnimation(spring) { expandedID = nil } }
    private func select(_ page: ControlCenterPage) {
        withAnimation(spring) { expandedID = nil; selectedPage = page.id }
    }
    private func reconcileExpansion() {
        if expandedID != nil && expandedTile == nil { collapse() }
    }
}

private struct TileInteraction: View {
    let tile: ControlTile
    let context: ControlTileContext
    let fallback: Bool

    private var face: some View {
        GeometryReader { geometry in
            tile.content(context)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .modifier(GlassSurface(radius: radius, tint: tile.tint, fallback: fallback))
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
    private var radius: CGFloat { tile.size == .small || tile.size == .wide || tile.size == .tall ? 100 : 34 }

    var body: some View {
        Group {
            if tile.isCustomView {
                tile.content(context)
            } else if let action = tile.action {
                Button(action: action) { face }
                    .buttonStyle(ControlPressStyle())
                    .accessibilityLabel(tile.accessibilityLabel)
            } else {
                face
                    .onTapGesture {
                        if tile.expandedContent != nil { context.expand() }
                    }
            }
        }
        .highPriorityGesture(LongPressGesture(minimumDuration: 0.38).onEnded { _ in
            if tile.expandedContent != nil { context.expand() }
        }, including: tile.expandedContent != nil ? .all : .none)
        .accessibilityAction(named: Text("Expand \(tile.accessibilityLabel)")) { context.expand() }
    }
}
#endif
