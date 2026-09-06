import Foundation
import Testing
@testable import LiquidControlCenter

struct GridTests {
    @Test func nativeArrangementFillsHoles() {
        let items: [GridItem] = [.init(size: .large), .init(size: .large),
                                .init(size: .small), .init(size: .small),
                                .init(size: .tall), .init(size: .tall), .init(size: .wide)]
        let result = ControlCenterGrid.placements(for: items, columns: 4)
        #expect(result.map(\.row) == [0, 0, 2, 2, 2, 2, 3])
        #expect(result.map(\.column) == [0, 2, 0, 1, 2, 3, 0])
    }

    @Test(arguments: [1, 2, 3, 4, 6, 12]) func neverOverlaps(columns: Int) {
        let sizes: [ControlTileSize] = [.small, .wide, .tall, .large, .init(columns: 12, rows: 3)]
        let items = (0..<100).map { GridItem(size: sizes[$0 % sizes.count]) }
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
        let items = [GridItem(size: .large, position: .init(column: 2, row: 2)),
                     GridItem(size: .large, position: .init(column: 2, row: 2)),
                     GridItem(size: .wide, position: .init(column: 3, row: 0))]
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
        #expect(state.complete(generation: opening))
        let closing = state.request(false)
        let reopening = state.request(true)
        #expect(!state.complete(generation: closing))
        #expect(state.phase == .presenting)
        #expect(state.complete(generation: reopening))
        #expect(state.phase == .presented)
    }

    @Test func dismissDuringPresentationAndIdempotentRequests() {
        var state = PresentationState()
        let first = state.request(true)
        #expect(state.request(true) == first)
        let closing = state.request(false)
        #expect(!state.complete(generation: first))
        #expect(state.complete(generation: closing))
        #expect(state.phase == .hidden)
        #expect(!state.complete(generation: closing))
    }

    @Test func reducedMotionAndBoundedStagger() {
        #expect(ControlCenterMotion.default.delay(for: 1000, reduceMotion: false) == 0.12)
        #expect(ControlCenterMotion.default.delay(for: 3, reduceMotion: true) == 0)
        let invalid = ControlCenterMotion(response: .nan, dampingFraction: -1, stagger: .infinity)
        #expect(invalid.validated.response == 0.48)
        #expect(invalid.validated.dampingFraction == 0.65)
        #expect(invalid.validated.stagger == 0.018)
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
