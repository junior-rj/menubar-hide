import CoreGraphics
import Testing

@testable import MenubarHide

@Suite("Collapsed geometry on macOS 27")
struct CollapsedGeometryTests {
    typealias Display = CollapsedGeometry.Display

    static let notched1512 = Display(width: 1512, statusWidth: 663.5)

    // macOS 27 discards a status item whose length reaches half the display
    // width. Measured by the Hidden Bar maintainers: 2056pt hides at <= 1000
    // and drops from 1028; 3008 keeps 1480 and drops 1500; 3840 drops from 1920.
    @Test("the unit stays under every measured cliff of a plain display", arguments: [
        (2056.0, 964.0), (3008.0, 1440.0), (3840.0, 1856.0),
    ])
    func unitUnderPlainCliff(width: Double, expected: Double) {
        #expect(CollapsedGeometry.unitLength(displays: [Display(width: CGFloat(width))]) == CGFloat(expected))
    }

    @Test("a notched display is sized from its trailing area, not its width")
    func unitUnderNotchedCliff() {
        // measured drop between 520 and 530 on a 663.5pt trailing area
        let unit = CollapsedGeometry.unitLength(displays: [Self.notched1512])
        #expect(unit == 433)
        #expect(unit < 520)
    }

    @Test("one length applies to every display, so the lowest cliff sizes it")
    func lowestCliffWins() {
        #expect(CollapsedGeometry.unitLength(displays: [Display(width: 3840), Self.notched1512]) == 433)
        #expect(CollapsedGeometry.unitLength(displays: [Display(width: 3840), Display(width: 1512)]) == 692)
    }

    @Test("the unit never drops below the floor", arguments: [[400.0], [100.0], []])
    func floor(widths: [Double]) {
        let displays = widths.map { Display(width: CGFloat($0)) }
        #expect(CollapsedGeometry.unitLength(displays: displays) == CollapsedGeometry.minimumUnit)
    }

    @Test("spacers cover the widest status area together with the separator")
    func spacersCoverWidest() {
        #expect(CollapsedGeometry.activeSpacers(unit: 433, displays: [Self.notched1512]) == 1)
        #expect(CollapsedGeometry.activeSpacers(unit: 1856, displays: [Display(width: 3840)]) == 2)
        #expect(CollapsedGeometry.activeSpacers(unit: 692, displays: [Display(width: 1512), Display(width: 3840)]) == 5)
    }

    @Test("the spacer count is capped at the registered items")
    func spacersCapped() {
        #expect(CollapsedGeometry.activeSpacers(unit: 433, displays: [Self.notched1512, Display(width: 3840)]) == CollapsedGeometry.spacerCount)
    }

    @Test("a unit that already spans the widest area needs no spacer")
    func noSpacerNeeded() {
        #expect(CollapsedGeometry.activeSpacers(unit: 700, displays: [Display(width: 600)]) == 0)
        #expect(CollapsedGeometry.activeSpacers(unit: 700, displays: []) == 0)
        #expect(CollapsedGeometry.activeSpacers(unit: 0, displays: [Display(width: 600)]) == 0)
    }
}
