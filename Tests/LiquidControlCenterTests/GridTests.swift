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
