#if os(iOS)
import SwiftUI
import UIKit

struct ControlCenterView: View {
    @ObservedObject var model: CenterModel
    let pages: [ControlCenterPage]
    let configuration: ControlCenterConfiguration
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var selectedPage: String?
    /// The tile the user asked to expand; nil while collapsing.
    @State private var expandedID: String?
    /// The tile whose morph is on screen; stays set until the collapse finishes.
    @State private var morphID: String?
    @State private var morph: Double = 0
    @State private var morphOrigin: CGRect = .zero
    @State private var tileFrames = TileFrameStore()
    @State private var pageDrag: CGFloat = 0
    @State private var pageShift: CGFloat = 120
    @State private var dragAxis: Axis?
    @State private var pageTracker = VelocityTracker()
    @AccessibilityFocusState private var closeFocused: Bool
    @AccessibilityFocusState private var expandedCloseFocused: Bool

    private var reduceMotion: Bool { systemReduceMotion || configuration.forceReducedMotion }
    private var rightToLeft: Bool { layoutDirection == .rightToLeft }
    private var uniquePages: [ControlCenterPage] {
        var ids = Set<String>()
        return pages.filter { ids.insert($0.id).inserted }
    }
    private var currentPage: ControlCenterPage? {
        uniquePages.first { $0.id == selectedPage } ?? uniquePages.first
    }
    private var currentIndex: Int { uniquePages.firstIndex { $0.id == currentPage?.id } ?? 0 }
    private var tiles: [ControlTile] { currentPage?.tiles.uniqueTiles ?? [] }
    private var morphTile: ControlTile? { tiles.first { $0.id == morphID && $0.isEnabled && $0.expandedContent != nil } }
    private var isExpanded: Bool { expandedID != nil }
    /// 0 when no tile is expanded, 1 when fully expanded. Drives the background dimming in step with the morph.
    private var morphAmount: Double { morphID == nil ? 0 : min(1, max(0, morph)) }
    private var motion: ControlCenterMotion { configuration.motion.validated }
    private var expansionSpring: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.86)
    }
    private var pageSpring: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.9)
    }
    private var gap: CGFloat { configuration.spacing.isFinite ? min(32, max(4, configuration.spacing)) : 14 }
    private var padding: CGFloat { configuration.horizontalPadding.isFinite ? min(80, max(12, configuration.horizontalPadding)) : 28 }
    private var maxWidth: CGFloat { configuration.maximumWidth.isFinite ? min(1200, max(240, configuration.maximumWidth)) : 430 }
    /// Header and rail trail the tiles slightly so the grid leads the reveal.
    private var chromeOpacity: Double { min(1, max(0, model.progress * 1.5 - 0.3)) }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.clear.contentShape(Rectangle())
                    .gesture(SpatialTapGesture(coordinateSpace: .named(centerSpace)).onEnded { value in
                        backgroundTap(at: value.location)
                    })
                    .accessibilityHidden(true)

                VStack(spacing: 20) {
                    header.opacity(chromeOpacity)
                    gridArea
                }
                .frame(maxWidth: maxWidth)
                .padding(.horizontal, padding)
                .padding(.top, 16)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: model.dragOffset)
                // No blur here: blurring live glass forces an offscreen pass every frame.
                .opacity(1 - 0.92 * morphAmount)
                .scaleEffect(reduceMotion ? 1 : 1 - 0.06 * morphAmount)
                .allowsHitTesting(!isExpanded)
                .accessibilityHidden(isExpanded)

                if uniquePages.count > 1 {
                    pageRail
                        .frame(width: 28)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .opacity(chromeOpacity * (1 - morphAmount))
                        .offset(y: model.dragOffset)
                        .allowsHitTesting(!isExpanded)
                        .accessibilityHidden(isExpanded)
                }

                if let tile = morphTile {
                    TileMorph(progress: morph,
                              origin: LayoutMirroring.placement(of: morphOrigin, inWidth: geometry.size.width,
                                                                rightToLeft: rightToLeft),
                              target: expandedFrame(for: tile, in: geometry.size),
                              compactRadius: tileRadius(tile.size), reduceMotion: reduceMotion,
                              tint: tile.tint,
                              compact: tile.content(context(for: tile)),
                              expanded: tile.expandedContent?(context(for: tile, expanded: true)) ?? AnyView(EmptyView()),
                              closeLabel: "Collapse \(tile.accessibilityLabel)",
                              identifier: "control-expanded.\(tile.id)",
                              closeFocus: $expandedCloseFocused,
                              collapse: collapse)
                        .allowsHitTesting(isExpanded)
                        .zIndex(2)
                }
            }
            .coordinateSpace(name: centerSpace)
            .onPreferenceChange(TileFrameKey.self) { [tileFrames] frames in tileFrames.frames = frames }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(centerDrag(height: geometry.size.height),
                     including: isExpanded ? .subviews : .all)
        }
        .environment(\.controlCenterReduceTransparency, configuration.forceReducedTransparency)
        .environment(\.controlCenterReduceMotion, reduceMotion)
        .environment(\.controlCenterFallback, configuration.forceFallback)
        // Modality comes from the host view's `accessibilityViewIsModal`. A SwiftUI `.isModal` trait here would
        // propagate to every tile, which XCTest then reports as alerts.
        .accessibilityAction(.escape) { expandedID != nil ? collapse() : dismiss() }
        .onChange(of: model.focusRequest) { _ in closeFocused = true }
        .onChange(of: model.isInteractive) { interactive in if !interactive { collapse() } }
        .onChange(of: expandedID) { expandedCloseFocused = $0 != nil }
        .onChange(of: tiles.map(\.id)) { _ in reconcileExpansion() }
        .onChange(of: tiles.map(\.isEnabled)) { _ in reconcileExpansion() }
        .onChange(of: tiles.map { $0.expandedContent != nil }) { _ in reconcileExpansion() }
    }

    // MARK: Chrome

    private var header: some View {
        HStack {
            Text(currentPage?.title ?? configuration.title)
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .id(currentPage?.id)
                .transition(.opacity)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .modifier(GlassSurface(radius: 22))
            }
            .accessibilityLabel("Close Control Center")
            .accessibilityIdentifier("control-center.close")
            .accessibilityFocused($closeFocused)
            .buttonStyle(ControlPressStyle())
        }
    }

    private var pageRail: some View {
        VStack(spacing: 8) {
            ForEach(uniquePages) { page in
                Button { select(page) } label: {
                    Image(systemName: page.systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 28, height: 44)
                        .foregroundStyle(.white.opacity(currentPage?.id == page.id ? 1 : 0.4))
                        .scaleEffect(currentPage?.id == page.id && !reduceMotion ? 1.12 : 1)
                }
                .accessibilityLabel(page.title)
                .accessibilityAddTraits(currentPage?.id == page.id ? .isSelected : [])
            }
        }
        .buttonStyle(.plain)
        .gesture(DragGesture(minimumDistance: 24).onEnded { value in
            let next = currentIndex + (value.translation.height < 0 ? 1 : -1)
            if uniquePages.indices.contains(next) { select(uniquePages[next]) }
        })
    }

    // MARK: Grid

    private var gridArea: some View {
        GeometryReader { area in
            let items = tiles.map { ControlGridItem(size: $0.size, position: $0.position) }
            let layout = ControlCenterGrid.frames(for: items, requestedColumns: configuration.columns,
                                                  width: area.size.width - 8, spacing: gap)
            let contentHeight = (layout.frames.map(\.maxY).max() ?? 0) + 8
            let rows = layout.placements.map(\.row)
            // Scroll only when the grid overflows, so a vertical swipe anywhere else can dismiss.
            Group {
                if contentHeight <= area.size.height + 0.5 {
                    pageGrid(rows: rows)
                } else {
                    ScrollView { pageGrid(rows: rows) }
                        .scrollIndicators(.hidden)
                        .scrollDisabled(isExpanded)
                }
            }
            .frame(width: area.size.width, height: area.size.height, alignment: .top)
        }
    }

    private func pageGrid(rows: [Int]) -> some View {
        TileLayout(items: tiles.map { ControlGridItem(size: $0.size, position: $0.position) },
                   columns: configuration.columns, spacing: gap) {
            ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                tileCell(tile, row: rows.indices.contains(index) ? rows[index] : 0)
            }
        }
        .padding(4)
        .id(currentPage?.id)
        .transition(reduceMotion ? .opacity : .asymmetric(
            insertion: .offset(x: pageShift).combined(with: .opacity),
            removal: .offset(x: -pageShift).combined(with: .opacity)))
        .offset(x: pageDrag)
    }

    private func tileCell(_ tile: ControlTile, row: Int) -> some View {
        compact(tile)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: TileFrameKey.self, value: [tile.id: proxy.frame(in: .named(centerSpace))])
                }
            }
            // The morph draws this tile while it is expanded; keeping it mounted preserves its state and layout.
            .opacity(morphID == tile.id ? 0 : 1)
            .modifier(RevealModifier(progress: model.progress, row: row,
                                     delay: motion.rowDelay(row, reduceMotion: reduceMotion),
                                     reduceMotion: reduceMotion))
    }

    private func compact(_ tile: ControlTile) -> some View {
        TileInteraction(tile: tile, context: context(for: tile))
            .disabled(!tile.isEnabled)
            .opacity(tile.isEnabled ? 1 : 0.4)
            .accessibilityIdentifier("control-tile.\(tile.id)")
    }

    // MARK: Expansion

    private func expandedFrame(for tile: ControlTile, in size: CGSize) -> CGRect {
        let width = max(120, min(maxWidth - 16, size.width - 48))
        let height = min(tile.expandedHeight, max(120, size.height - 160))
        // Leave room below for the collapse button (16 spacing + 48).
        return CGRect(x: (size.width - width) / 2, y: (size.height - height - 64) / 2, width: width, height: height)
    }

    private func tileRadius(_ size: ControlTileSize) -> CGFloat {
        size == .small || size == .wide || size == .tall ? 100 : 34
    }

    private func context(for tile: ControlTile, expanded: Bool = false) -> ControlTileContext {
        .init(isExpanded: expanded, expand: {
            guard tile.isEnabled, tile.expandedContent != nil else { return }
            expand(tile)
        }, collapse: collapse, dismiss: dismiss)
    }

    // MARK: Actions

    private func dismiss() { model.controller?.dismiss() }

    private func backgroundTap(at location: CGPoint) {
        if expandedID != nil { collapse(); return }
        // A tap that reaches the background over a tile (one still fading in, or mid page transition)
        // must never close the center.
        if tileFrames.frames.values.contains(where: { $0.insetBy(dx: -4, dy: -4).contains(location) }) { return }
        if configuration.dismissOnBackgroundTap { dismiss() }
    }

    private func expand(_ tile: ControlTile) {
        guard expandedID != tile.id else { return }
        if configuration.hapticsEnabled { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        if morphID != tile.id {
            // Mount the morph at the tile's frame first; an inserted view cannot interpolate from its first value.
            morphOrigin = tileFrames.frames[tile.id] ?? .zero
            morphID = tile.id
            morph = 0
        }
        DispatchQueue.main.async {
            withAnimation(expansionSpring) {
                expandedID = tile.id
                morph = 1
            }
        }
    }

    private func collapse() {
        guard expandedID != nil else { return }
        let id = expandedID
        let finish: @MainActor () -> Void = {
            // Only unmount if nothing re-expanded in the meantime.
            if expandedID == nil && morphID == id { morphID = nil }
        }
        if #available(iOS 17.0, *) {
            withAnimation(expansionSpring, completionCriteria: .logicallyComplete) {
                expandedID = nil
                morph = 0
            } completion: { finish() }
        } else {
            withAnimation(expansionSpring) {
                expandedID = nil
                morph = 0
            }
        }
        // Completions are not guaranteed for animations merged with an interrupted one; never leave the grid
        // non-interactive because one was dropped. `finish` is idempotent.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { finish() }
    }

    private func select(_ page: ControlCenterPage) {
        guard let target = uniquePages.firstIndex(where: { $0.id == page.id }), target != currentIndex else { return }
        go(to: page, forward: target > currentIndex)
    }

    private func go(to page: ControlCenterPage, forward: Bool) {
        // Set the direction in its own update so the outgoing page picks up the matching removal edge.
        // `.offset` mirrors in right-to-left layouts, so the next page enters from the trailing edge in both.
        pageShift = (forward ? 1 : -1) * 120
        if configuration.hapticsEnabled { UISelectionFeedbackGenerator().selectionChanged() }
        DispatchQueue.main.async {
            morphID = nil
            withAnimation(pageSpring) {
                expandedID = nil
                morph = 0
                selectedPage = page.id
                pageDrag = 0
            }
        }
    }

    private func reconcileExpansion() {
        // A removed or disabled tile cannot stay expanded; drop it without animating from a stale frame.
        if morphID != nil && morphTile == nil {
            expandedID = nil
            morphID = nil
            morph = 0
        }
    }

    // MARK: Gestures

    /// Vertical drags dismiss interactively; horizontal drags page between groups. Controls inside tiles
    /// (buttons, sliders) keep priority because this gesture sits on their ancestor.
    private func centerDrag(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                let translation = value.translation
                if dragAxis == nil {
                    dragAxis = abs(translation.height) > abs(translation.width) ? .vertical : .horizontal
                    if dragAxis == .vertical {
                        if configuration.allowsInteractiveDismissal { model.controller?.beginDismissalDrag() }
                    } else {
                        pageTracker.reset()
                    }
                }
                if dragAxis == .vertical {
                    guard configuration.allowsInteractiveDismissal else { return }
                    model.controller?.updateDismissalDrag(translation: translation.height,
                                                          distance: pullDistance(for: height),
                                                          time: CACurrentMediaTime())
                } else if uniquePages.count > 1 {
                    let dx = pageDistance(translation.width)
                    pageTracker.add(dx, at: CACurrentMediaTime())
                    let target = currentIndex + (isForward(dx) ? 1 : -1)
                    let offset = uniquePages.indices.contains(target)
                        ? dx * 0.6
                        : GestureMath.rubberBand(dx, dimension: 300)
                    withAnimation(.interactiveSpring(response: 0.16, dampingFraction: 0.86)) { pageDrag = offset }
                }
            }
            .onEnded { value in
                defer { dragAxis = nil }
                if dragAxis == .vertical {
                    if configuration.allowsInteractiveDismissal { model.controller?.endDismissalDrag() }
                    return
                }
                guard dragAxis == .horizontal, uniquePages.count > 1 else { return }
                let width = pageDistance(value.translation.width)
                let velocity = pageTracker.velocity
                let forward = isForward(width)
                let flick = abs(velocity) > 450 && isForward(velocity) == forward
                let target = currentIndex + (forward ? 1 : -1)
                if (abs(width) > 70 || flick), uniquePages.indices.contains(target) {
                    go(to: uniquePages[target], forward: forward)
                } else {
                    withAnimation(pageSpring) { pageDrag = 0 }
                }
            }
    }

    /// A horizontal drag in the leading-relative coordinates `.offset` uses, so the grid follows the finger.
    private func pageDistance(_ translation: CGFloat) -> CGFloat {
        LayoutMirroring.offset(translation, rightToLeft: rightToLeft)
    }

    /// Swiping toward the leading edge advances. Page distances run from the leading edge in both directions.
    private func isForward(_ dx: Double) -> Bool { dx < 0 }
}

/// Applies the shared progress to one tile. Being `Animatable`, it is evaluated every frame,
/// so each tile follows the presentation spring with its own row delay.
private struct RevealModifier: ViewModifier, Animatable {
    var progress: Double
    let row: Int
    let delay: Double
    let reduceMotion: Bool

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let reveal = TileReveal.at(progress: progress, row: row, delay: delay, reduceMotion: reduceMotion)
        content
            // Never fully transparent: SwiftUI skips opacity-0 views when hit testing, and a tap on a tile that is
            // still fading in should reach the tile.
            .opacity(max(0.001, reveal.opacity))
            .scaleEffect(reveal.scale, anchor: .top)
            .offset(y: reveal.offset)
    }
}

private let centerSpace = "liquid-control-center"

/// Tile frames in `centerSpace` as they appear on screen, like the background tap location. Anything placed at one
/// goes through `LayoutMirroring` first.
private struct TileFrameKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Tile frames change every frame while the center animates. Keeping them in a reference box
/// (rather than `@State` values) records them without re-rendering the whole center.
private final class TileFrameStore {
    var frames: [String: CGRect] = [:]
}

/// One continuous shape that grows out of a tile into its expanded panel and back.
///
/// Frame, corner radius, the compact-to-expanded content crossfade, and the collapse button are
/// all functions of a single animatable `progress`, so the morph is interruptible at any point.
private struct TileMorph: View, Animatable {
    var progress: Double
    let origin: CGRect
    let target: CGRect
    let compactRadius: CGFloat
    let reduceMotion: Bool
    let tint: Color?
    let compact: AnyView
    let expanded: AnyView
    let closeLabel: String
    let identifier: String
    var closeFocus: AccessibilityFocusState<Bool>.Binding
    let collapse: () -> Void

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let clamped = min(1, max(0, progress))
        // Without a recorded origin (e.g. expanded through accessibility), grow from the panel centre.
        let start = origin.isEmpty || reduceMotion
            ? target.insetBy(dx: target.width * 0.1, dy: target.height * 0.1) : origin
        let frame = Self.mix(start, target, progress)
        let radius = min(compactRadius, start.height / 2, start.width / 2) * (1 - clamped) + 44 * clamped
        let compactOpacity = 1 - Self.smooth(progress / 0.25)
        let expandedOpacity = Self.smooth((progress - 0.18) / 0.5)
        let scale = frame.width / max(1, target.width)

        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: frame.width, height: frame.height)
                .modifier(GlassSurface(radius: radius, tint: tint))
                .opacity(reduceMotion ? clamped : 1)
                .overlay {
                    ZStack {
                        compact
                            .frame(width: start.width, height: start.height)
                            .opacity(compactOpacity)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        // Laid out once at its final size and scaled, so text never reflows mid-morph.
                        ScrollView { expanded }
                            .scrollIndicators(.hidden)
                            .padding(24)
                            .frame(width: target.width, height: target.height)
                            .scaleEffect(reduceMotion ? 1 : scale)
                            .opacity(expandedOpacity)
                    }
                    .frame(width: frame.width, height: frame.height)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(identifier)
                .position(x: frame.midX, y: frame.midY)

            Button(action: collapse) {
                Image(systemName: "xmark").font(.system(size: 18, weight: .semibold))
                    .frame(width: 48, height: 48)
                    .modifier(GlassSurface(radius: 24))
            }
            .buttonStyle(ControlPressStyle())
            .accessibilityLabel(closeLabel)
            .accessibilityFocused(closeFocus)
            .opacity(Self.smooth((progress - 0.5) / 0.5))
            .scaleEffect(reduceMotion ? 1 : 0.6 + 0.4 * clamped)
            .position(x: target.midX, y: target.maxY + 16 + 24)
        }
    }

    private static func mix(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
        let t = CGFloat(t)
        return CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
                      width: max(1, a.width + (b.width - a.width) * t),
                      height: max(1, a.height + (b.height - a.height) * t))
    }

    private static func smooth(_ x: Double) -> Double {
        let x = min(1, max(0, x))
        return x * x * (3 - 2 * x)
    }
}

private struct TileInteraction: View {
    let tile: ControlTile
    let context: ControlTileContext

    private var face: some View {
        GeometryReader { geometry in
            tile.content(context)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .modifier(GlassSurface(radius: radius, tint: tile.tint))
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
