import Foundation
import CoreGraphics

/// The footprint of a control in grid cells. Values are bounded to keep layout finite.
public struct ControlTileSize: Hashable, Sendable, Codable {
    public let columns: Int
    public let rows: Int

    public init(columns: Int, rows: Int) {
        self.columns = min(12, max(1, columns))
        self.rows = min(12, max(1, rows))
    }

    private enum CodingKeys: String, CodingKey { case columns, rows }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(columns: try values.decode(Int.self, forKey: .columns),
                  rows: try values.decode(Int.self, forKey: .rows))
    }

    public static let small = Self(columns: 1, rows: 1)
    public static let wide = Self(columns: 2, rows: 1)
    public static let large = Self(columns: 2, rows: 2)
    public static let tall = Self(columns: 1, rows: 2)
}

/// A zero-based preferred position. Colliding or out-of-bounds positions use first-fit packing.
public struct ControlTilePosition: Hashable, Sendable, Codable {
    public let column: Int
    public let row: Int
    public init(column: Int, row: Int) {
        self.column = min(11, max(0, column))
        self.row = min(512, max(0, row))
    }
    private enum CodingKeys: String, CodingKey { case column, row }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(column: try values.decode(Int.self, forKey: .column),
                  row: try values.decode(Int.self, forKey: .row))
    }
}

struct ControlGridItem: Equatable {
    let size: ControlTileSize
    var position: ControlTilePosition? = nil
}

struct GridPlacement: Equatable {
    let column: Int
    let row: Int
    let columns: Int
    let rows: Int

    func frame(cell: CGFloat, spacing: CGFloat, width: CGFloat, rightToLeft: Bool) -> CGRect {
        let widthOfTile = CGFloat(columns) * cell + CGFloat(columns - 1) * spacing
        let x = CGFloat(column) * (cell + spacing)
        let originX: CGFloat = rightToLeft ? width - x - widthOfTile : x
        let originY: CGFloat = CGFloat(row) * (cell + spacing)
        let height: CGFloat = CGFloat(rows) * cell + CGFloat(rows - 1) * spacing
        return CGRect(x: originX, y: originY, width: widthOfTile, height: height)
    }
}

enum ControlCenterGrid {
    static func placements(for items: [ControlGridItem], columns proposedColumns: Int) -> [GridPlacement] {
        let columns = min(12, max(1, proposedColumns))
        // Internal cells cannot use the public position initializer's row clamp.
        var cells = Set<Int>()
        var result: [GridPlacement] = []
        var bottom = 0
        for item in items {
            let span = min(columns, max(1, item.size.columns))
            let height = min(12, max(1, item.size.rows))
            func fits(_ column: Int, _ row: Int) -> Bool {
                guard column >= 0, row >= 0, column + span <= columns else { return false }
                return (row..<(row + height)).allSatisfy { r in
                    (column..<(column + span)).allSatisfy { c in !cells.contains(r * columns + c) }
                }
            }
            var location: (Int, Int)?
            if let p = item.position {
                let row = min(512, max(0, p.row))
                let column = min(11, max(0, p.column))
                if fits(column, row) { location = (column, row) }
            }
            if location == nil {
                search: for row in 0...bottom {
                    for column in 0...(columns - span) where fits(column, row) {
                        location = (column, row)
                        break search
                    }
                }
            }
            let (column, row) = location ?? (0, bottom)
            for r in row..<(row + height) {
                for c in column..<(column + span) { cells.insert(r * columns + c) }
            }
            bottom = max(bottom, row + height)
            result.append(.init(column: column, row: row, columns: span, rows: height))
        }
        return result
    }

    static func columnCount(requested: Int, width: CGFloat, spacing: CGFloat) -> Int {
        guard width.isFinite, width > 0 else { return 1 }
        let gap = spacing.isFinite ? max(0, spacing) : 12
        let bounded = min(12, max(1, requested))
        let fitting = min(CGFloat(bounded), max(1, ((width + gap) / (44 + gap)).rounded(.down)))
        return Int(fitting)
    }
}
