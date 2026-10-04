import Foundation
import CoreGraphics
import SwiftUI

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

    /// Measured from the leading edge in both layout directions; `TileLayout` explains why.
    func frame(cell: CGFloat, spacing: CGFloat) -> CGRect {
        let widthOfTile = CGFloat(columns) * cell + CGFloat(columns - 1) * spacing
        let originX: CGFloat = CGFloat(column) * (cell + spacing)
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

    /// Placements and frames for a given width, shared by the layout and by the motion stagger.
    static func frames(for items: [ControlGridItem], requestedColumns: Int, width: CGFloat,
                       spacing: CGFloat) -> (placements: [GridPlacement], frames: [CGRect]) {
        let width = width.isFinite ? max(1, width) : 320
        let count = columnCount(requested: requestedColumns, width: width, spacing: spacing)
        let cell = max(1, (width - CGFloat(count - 1) * spacing) / CGFloat(count))
        let placements = placements(for: items, columns: count)
        return (placements, placements.map { $0.frame(cell: cell, spacing: spacing) })
    }

    static func columnCount(requested: Int, width: CGFloat, spacing: CGFloat) -> Int {
        guard width.isFinite, width > 0 else { return 1 }
        let gap = spacing.isFinite ? max(0, spacing) : 12
        let bounded = min(12, max(1, requested))
        let fitting = min(CGFloat(bounded), max(1, ((width + gap) / (44 + gap)).rounded(.down)))
        return Int(fitting)
    }
}

/// Places tiles at their grid frames, from the leading edge. SwiftUI mirrors a custom layout's placements in
/// right-to-left environments, so mirroring the frames here as well would cancel that out.
struct TileLayout: Layout {
    let items: [ControlGridItem]
    let columns: Int
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(1, proposal.width ?? 320)
        return CGSize(width: width, height: frames(width: width).map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(width: CGFloat) -> [CGRect] {
        ControlCenterGrid.frames(for: items, requestedColumns: columns, width: width, spacing: spacing).frames
    }
}

/// SwiftUI places views from the leading edge (`Layout`, `.position`, `.offset`) and mirrors that placement in
/// right-to-left layouts, but reports geometry as it appears on screen (geometry readers, gesture locations and
/// translations). These turn a measurement into a placement, so it is mirrored exactly once.
enum LayoutMirroring {
    /// A frame measured in a container of the given width, as `.position` in that container expects it.
    static func placement(of frame: CGRect, inWidth width: CGFloat, rightToLeft: Bool) -> CGRect {
        guard rightToLeft else { return frame }
        return CGRect(x: width - frame.maxX, y: frame.minY, width: frame.width, height: frame.height)
    }

    /// A horizontal distance measured on screen, such as a drag translation, as `.offset(x:)` expects it.
    static func offset(_ distance: CGFloat, rightToLeft: Bool) -> CGFloat {
        rightToLeft ? -distance : distance
    }
}
