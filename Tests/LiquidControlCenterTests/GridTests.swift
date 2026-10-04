import Foundation
import CoreGraphics
import SwiftUI
import Testing
@testable import LiquidControlCenter

struct GridTests {
    @Test func nativeArrangementFillsHoles() {
        let items: [ControlGridItem] = [.init(size: .large), .init(size: .large),
                                .init(size: .small), .init(size: .small),
                                .init(size: .tall), .init(size: .tall), .init(size: .wide)]
        let result = ControlCenterGrid.placements(for: items, columns: 4)
        #expect(result.map(\.row) == [0, 0, 2, 2, 2, 2, 3])
        #expect(result.map(\.column) == [0, 2, 0, 1, 2, 3, 0])
    }

    @Test(arguments: [1, 2, 3, 4, 6, 12]) func neverOverlaps(columns: Int) {
        let sizes: [ControlTileSize] = [.small, .wide, .tall, .large, .init(columns: 12, rows: 3)]
        let items = (0..<100).map { ControlGridItem(size: sizes[$0 % sizes.count]) }
        let result = ControlCenterGrid.placements(for: items, columns: columns)
        var cells = Set<String>()
        for tile in result {
            #expect(tile.column + tile.columns <= columns)
            for row in tile.row..<(tile.row + tile.rows) {
                for col in tile.column..<(tile.column + tile.columns) {
                    #expect(cells.insert("\(row):\(col)").inserted)
                }
            }
        }
        #expect(result == ControlCenterGrid.placements(for: items, columns: columns))
    }

    @Test func preferredPositionsAndCollisions() {
        let items = [ControlGridItem(size: .large, position: .init(column: 2, row: 2)),
                     ControlGridItem(size: .large, position: .init(column: 2, row: 2)),
                     ControlGridItem(size: .wide, position: .init(column: 3, row: 0))]
        let result = ControlCenterGrid.placements(for: items, columns: 4)
        #expect(result.map(\.row) == [2, 0, 0])
        #expect(result.map(\.column) == [2, 0, 2])
    }

    @Test func invalidInputsAndEmptyGrid() {
        #expect(ControlCenterGrid.placements(for: [], columns: 0).isEmpty)
        let placement = ControlCenterGrid.placements(for: [.init(size: .init(columns: -2, rows: 0))], columns: -1)
        #expect(placement == [.init(column: 0, row: 0, columns: 1, rows: 1)])
        #expect(ControlCenterGrid.columnCount(requested: 4, width: 180, spacing: 12) == 3)
        #expect(ControlCenterGrid.columnCount(requested: 4, width: .nan, spacing: 12) == 1)
    }

    @Test func framesMatchLayoutAndReportRows() {
        let items: [ControlGridItem] = [.init(size: .large), .init(size: .small), .init(size: .tall)]
        let result = ControlCenterGrid.frames(for: items, requestedColumns: 4, width: 316, spacing: 12)
        #expect(result.placements.map(\.row) == [0, 0, 0])
        #expect(result.frames[0] == CGRect(x: 0, y: 0, width: 152, height: 152))
        #expect(result.frames[2].height == 152)
        #expect(ControlCenterGrid.frames(for: items, requestedColumns: 4, width: .nan, spacing: 12).frames.count == 3)
    }

    @Test func framesRunFromTheLeadingEdge() {
        // SwiftUI mirrors the layout in right-to-left environments (see RightToLeftTests); the grid never does.
        let tile = GridPlacement(column: 0, row: 1, columns: 2, rows: 1)
        #expect(tile.frame(cell: 70, spacing: 12) == CGRect(x: 0, y: 82, width: 152, height: 70))
    }

    @Test func measurementsMirrorBackForPlacement() {
        let measured = CGRect(x: 164, y: 82, width: 152, height: 70)
        #expect(LayoutMirroring.placement(of: measured, inWidth: 316, rightToLeft: false) == measured)
        #expect(LayoutMirroring.placement(of: measured, inWidth: 316, rightToLeft: true) == CGRect(x: 0, y: 82, width: 152, height: 70))
        // Without a recorded frame the morph grows from its panel; mirroring must keep that frame empty.
        #expect(LayoutMirroring.placement(of: .zero, inWidth: 316, rightToLeft: true).isEmpty)
        #expect(LayoutMirroring.offset(40, rightToLeft: false) == 40)
        #expect(LayoutMirroring.offset(40, rightToLeft: true) == -40)
    }
}

/// Renders through SwiftUI, which mirrors placement (`Layout`, `.position`, `.offset`) in right-to-left layouts but
/// measures geometry as it appears on screen. The grid has to cooperate with both.
@MainActor
struct RightToLeftTests {
    /// The arrangement from the report: a large tile on the leading side beside a column of wide tiles, then two
    /// wide tiles sharing a row.
    private let items: [ControlGridItem] = [.init(size: .large), .init(size: .wide), .init(size: .wide),
                                            .init(size: .wide), .init(size: .wide)]
    private let width: CGFloat = 316
    private var frames: [CGRect] {
        ControlCenterGrid.frames(for: items, requestedColumns: 4, width: width, spacing: 12).frames
    }
    private var height: CGFloat { frames.map(\.maxY).max() ?? 0 }

    /// Where a leading-edge frame appears on screen.
    private func onScreen(_ frame: CGRect, _ direction: LayoutDirection) -> CGPoint {
        CGPoint(x: direction == .rightToLeft ? width - frame.midX : frame.midX, y: frame.midY)
    }

    @Test(arguments: [LayoutDirection.leftToRight, .rightToLeft])
    func tilesMirrorExactlyOnce(direction: LayoutDirection) throws {
        let snapshot = try Snapshot(width: width, height: height, direction: direction) {
            TileLayout(items: items, columns: 4, spacing: 12) {
                ForEach(frames.indices, id: \.self) { Snapshot.swatch($0) }
            }
        }
        for index in frames.indices {
            #expect(snapshot.swatch(at: onScreen(frames[index], direction)) == index, "tile \(index)")
        }
    }

    @Test(arguments: [LayoutDirection.leftToRight, .rightToLeft])
    func expansionStartsOnItsTile(direction: LayoutDirection) throws {
        // Like the morph: a tile frame read in a named space, then drawn with `.position` in that space.
        let snapshot = try Snapshot(width: width, height: height, direction: direction) {
            TileLayout(items: items, columns: 4, spacing: 12) {
                ForEach(frames.indices, id: \.self) { index in
                    Snapshot.swatch(index).background(GeometryReader { proxy in
                        Color.clear.preference(key: MeasuredFrames.self, value: [index: proxy.frame(in: .named("grid"))])
                    })
                }
            }
            .overlayPreferenceValue(MeasuredFrames.self) { measured in
                let origin = LayoutMirroring.placement(of: measured[0] ?? .zero, inWidth: width,
                                                       rightToLeft: direction == .rightToLeft)
                ZStack(alignment: .topLeading) {
                    Snapshot.swatch(5).frame(width: origin.width / 2, height: origin.height / 2)
                        .position(x: origin.midX, y: origin.midY)
                }
            }
            .coordinateSpace(name: "grid")
        }
        let tile = onScreen(frames[0], direction)
        #expect(snapshot.swatch(at: tile) == 5)
        #expect(snapshot.swatch(at: CGPoint(x: tile.x, y: frames[0].minY + 8)) == 0)
    }

    @Test(arguments: [LayoutDirection.leftToRight, .rightToLeft])
    func pagesSlideTowardTheTrailingEdgeAndFollowTheFinger(direction: LayoutDirection) throws {
        let rightToLeft = direction == .rightToLeft
        let snapshot = try Snapshot(width: 200, height: 40, direction: direction) {
            VStack(spacing: 0) {
                // A page transition offset, which needs no flipping of its own.
                Snapshot.swatch(0).frame(width: 20, height: 20).offset(x: 50)
                // A drag translation, measured on screen.
                Snapshot.swatch(1).frame(width: 20, height: 20).offset(x: LayoutMirroring.offset(50, rightToLeft: rightToLeft))
            }
        }
        #expect(snapshot.swatch(at: CGPoint(x: rightToLeft ? 50 : 150, y: 10)) == 0)
        #expect(snapshot.swatch(at: CGPoint(x: 150, y: 30)) == 1)
    }
}

private struct MeasuredFrames: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A view rendered at 1× in a layout direction, read back pixel by pixel.
@MainActor
private struct Snapshot {
    /// Pure colors survive rendering exactly, so each tile can be told apart by its pixels.
    private static let palette: [(red: Double, green: Double, blue: Double)] =
        [(1, 0, 0), (0, 1, 0), (0, 0, 1), (1, 1, 0), (1, 0, 1), (0, 1, 1)]
    private let width: Int
    private var pixels: [UInt8]

    static func swatch(_ index: Int) -> Color {
        Color(red: palette[index].red, green: palette[index].green, blue: palette[index].blue)
    }

    init(width: CGFloat, height: CGFloat, direction: LayoutDirection, @ViewBuilder content: () -> some View) throws {
        let renderer = ImageRenderer(content: content().frame(width: width, height: height)
            .environment(\.layoutDirection, direction))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        self.width = image.width
        pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                                 bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
    }

    /// The palette index of the opaque color at a point, in points from the top-left corner.
    func swatch(at point: CGPoint) -> Int? {
        let start = (Int(point.y) * width + Int(point.x)) * 4
        let rgba = pixels[start..<start + 4].map { Double($0) / 255 }
        guard rgba[3] > 0.9 else { return nil }
        return Self.palette.firstIndex {
            abs($0.red - rgba[0]) < 0.1 && abs($0.green - rgba[1]) < 0.1 && abs($0.blue - rgba[2]) < 0.1
        }
    }
}

struct MotionTests {
    @Test func staleDismissalCannotCloseReopenedCenter() {
        var state = PresentationState()
        let opening = state.request(true)
        let result1 = state.complete(generation: opening)
        #expect(result1)
        let closing = state.request(false)
        let reopening = state.request(true)
        let result2 = state.complete(generation: closing)
        #expect(!result2)
        #expect(state.phase == .presenting)
        let result3 = state.complete(generation: reopening)
        #expect(result3)
        #expect(state.phase == .presented)
    }

    @Test func dismissDuringPresentationAndIdempotentRequests() {
        var state = PresentationState()
        let first = state.request(true)
        let repeated = state.request(true)
        #expect(repeated == first)
        let closing = state.request(false)
        let result4 = state.complete(generation: first)
        #expect(!result4)
        let result5 = state.complete(generation: closing)
        #expect(result5)
        #expect(state.phase == .hidden)
        let result6 = state.complete(generation: closing)
        #expect(!result6)
    }

    @Test func reducedMotionAndBoundedStagger() {
        #expect(ControlCenterMotion.default.rowDelay(1000, reduceMotion: false) == 0.35)
        #expect(ControlCenterMotion.default.rowDelay(3, reduceMotion: true) == 0)
        #expect(ControlCenterMotion.default.rowDelay(0, reduceMotion: false) == 0)
        let invalid = ControlCenterMotion(response: .nan, dampingFraction: -1, stagger: .infinity)
        #expect(invalid.validated.response == 0.5)
        #expect(invalid.validated.dampingFraction == 0.65)
        #expect(invalid.validated.stagger == 0.026)
    }

    @Test func interactionInvalidatesInFlightCompletions() {
        var state = PresentationState()
        let opening = state.request(true)
        let grabbed = state.beginInteraction()
        #expect(state.phase == .interacting)
        let staleOpening = state.complete(generation: opening)
        let completedInteraction = state.complete(generation: grabbed)
        #expect(!staleOpening)
        #expect(!completedInteraction)
        let released = state.request(false)
        #expect(state.phase == .dismissing)
        let dismissed = state.complete(generation: released)
        #expect(dismissed)
        #expect(state.phase == .hidden)
        _ = state.beginInteraction()
        let reopened = state.request(true)
        let presented = state.complete(generation: reopened)
        #expect(presented)
        #expect(state.phase == .presented)
    }

    @Test func revealIsHiddenAtZeroSettledAtOneAndStaggered() {
        let hidden = TileReveal.at(progress: 0, row: 3, delay: 0.1, reduceMotion: false)
        #expect(hidden.opacity == 0)
        #expect(hidden.offset < 0)
        let shown = TileReveal.at(progress: 1, row: 3, delay: 0.1, reduceMotion: false)
        #expect(shown == TileReveal(opacity: 1, scale: 1, offset: 0))
        // A later row lags behind an earlier one at the same progress.
        let first = TileReveal.at(progress: 0.4, row: 0, delay: 0, reduceMotion: false)
        let later = TileReveal.at(progress: 0.4, row: 4, delay: 0.3, reduceMotion: false)
        #expect(first.opacity > later.opacity)
        #expect(first.scale > later.scale)
        // Spring overshoot passes through instead of clamping.
        #expect(TileReveal.at(progress: 1.05, row: 0, delay: 0, reduceMotion: false).scale > 1)
        // Reduce Motion fades only.
        let reduced = TileReveal.at(progress: 0.5, row: 5, delay: 0.3, reduceMotion: true)
        #expect(reduced == TileReveal(opacity: 0.5, scale: 1, offset: 0))
        #expect(TileReveal.at(progress: .nan, row: 0, delay: 0, reduceMotion: false).opacity == 0)
    }

    @Test func releaseProjectsMomentum() {
        #expect(GestureMath.shouldPresent(progress: 0.7, velocity: 0))
        #expect(!GestureMath.shouldPresent(progress: 0.3, velocity: 0))
        // A flick wins over position.
        #expect(!GestureMath.shouldPresent(progress: 0.9, velocity: -2))
        #expect(GestureMath.shouldPresent(progress: 0.15, velocity: 2))
        // Moderate velocity is projected.
        #expect(!GestureMath.shouldPresent(progress: 0.6, velocity: -0.5))
        #expect(!GestureMath.shouldPresent(progress: .nan, velocity: 1))
    }

    @Test func rubberBandResistsAndPreservesSign() {
        #expect(GestureMath.rubberBand(0) == 0)
        let small = GestureMath.rubberBand(50), large = GestureMath.rubberBand(500)
        #expect(small > 0 && small < 50)
        #expect(large > small && large < 600)
        #expect(GestureMath.rubberBand(-50) == -small)
        #expect(GestureMath.rubberBand(.infinity) == 0)
    }

    @Test func velocityTrackerUsesRecentSamples() {
        var tracker = VelocityTracker()
        #expect(tracker.velocity == 0)
        tracker.add(0, at: 0)
        tracker.add(100, at: 0.45)  // older than the 100 ms window once newer samples arrive
        tracker.add(110, at: 0.55)
        tracker.add(130, at: 0.6)
        #expect(abs(tracker.velocity - 400) < 0.001)
        tracker.reset()
        #expect(tracker.velocity == 0)
    }

    @Test func sliderClampsAndHandlesDegenerateRange() {
        #expect(ControlValue.normalized(20, in: 0...10) == 1)
        #expect(ControlValue.normalized(-3, in: 0...10) == 0)
        #expect(ControlValue.normalized(.nan, in: 0...1) == 0)
        #expect(ControlValue.normalized(5, in: 5...5) == 0)
        #expect(ControlValue.value(at: 0.5, in: 20...100) == 60)
        #expect(ControlValue.value(at: .infinity, in: 20...100) == 20)
    }
}

struct RobustnessTests {
    @Test func persistedLayoutValidatesDecodedValues() throws {
        let decoder = JSONDecoder()
        let size = try decoder.decode(ControlTileSize.self, from: Data(#"{"columns":-10,"rows":999999}"#.utf8))
        let position = try decoder.decode(ControlTilePosition.self, from: Data(#"{"column":999,"row":9223372036854775807}"#.utf8))
        #expect(size == .init(columns: 1, rows: 12))
        #expect(position == .init(column: 11, row: 512))
        #expect(try decoder.decode(ControlTileSize.self, from: JSONEncoder().encode(size)) == size)
    }

    @Test func extremeWidthDoesNotOverflow() {
        #expect(ControlCenterGrid.columnCount(requested: 4, width: .greatestFiniteMagnitude, spacing: 12) == 4)
    }
}

#if os(iOS)
struct TileAPITests {
    @Test @MainActor func builderSupportsConditionsLoopsAndArrays() {
        @ControlCenterBuilder func controls(show: Bool) -> [ControlTile] {
            ControlTile("first", label: "First") { _ in Text("First") }
            if show { ControlTile("optional", label: "Optional") { _ in Text("Optional") } }
            for i in 0..<3 { ControlTile("loop-\(i)", label: "Loop") { _ in Text("Loop") } }
        }
        #expect(controls(show: true).map(\.id) == ["first", "optional", "loop-0", "loop-1", "loop-2"])
        #expect(controls(show: false).count == 4)
    }

    @Test @MainActor func duplicateIDsKeepFirstAndExpansionIsOptIn() {
        let a = ControlTile("same", label: "First") { _ in Text("First") }
        let b = ControlTile("same", label: "Second") { _ in Text("Second") }.expanded { _ in Text("Expanded") }
        #expect([a, b].uniqueTiles.count == 1)
        #expect([a, b].uniqueTiles.first?.accessibilityLabel == "First")
        #expect(a.expandedContent == nil)
        #expect(b.expandedContent != nil)
    }
}
#endif
