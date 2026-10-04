import Foundation
import CoreGraphics
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
        let result = ControlCenterGrid.frames(for: items, requestedColumns: 4, width: 316, spacing: 12, rightToLeft: false)
        #expect(result.placements.map(\.row) == [0, 0, 0])
        #expect(result.frames[0] == CGRect(x: 0, y: 0, width: 152, height: 152))
        #expect(result.frames[2].height == 152)
        #expect(ControlCenterGrid.frames(for: items, requestedColumns: 4, width: .nan, spacing: 12, rightToLeft: false).frames.count == 3)
    }

    @Test func mirrorsCoordinatesWithoutChangingReadingOrder() {
        let tile = GridPlacement(column: 0, row: 1, columns: 2, rows: 1)
        let ltr = tile.frame(cell: 70, spacing: 12, width: 316, rightToLeft: false)
        let rtl = tile.frame(cell: 70, spacing: 12, width: 316, rightToLeft: true)
        #expect(ltr == CGRect(x: 0, y: 82, width: 152, height: 70))
        #expect(rtl.minX == 164)
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
import SwiftUI
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
