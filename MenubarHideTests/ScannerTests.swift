import CoreGraphics
import Testing

@testable import MenubarHide

@Suite("Hidden item discovery by shape")
struct ScannerTests {
    // CG global space, menu bar strip at y == 0 on a 1710pt display
    static func window(_ id: CGWindowID, x: CGFloat, width: CGFloat) -> MenuBarItemWindow {
        MenuBarItemWindow(id: id, frame: CGRect(x: x, y: 0, width: width, height: 24), ownerName: "Control Center")
    }

    // the collapsed separator: 10000pt asked for, ~5016 delivered by the window server
    static let separator = window(1, x: -4200, width: 5016)

    @Test("an empty status layer yields nothing")
    func empty() {
        #expect(MenuBarItemScanner.hiddenItems(among: []).isEmpty)
    }

    @Test("without a separator-shaped window nothing is hidden")
    func noSeparator() {
        let items = [Self.window(2, x: 700, width: 24), Self.window(3, x: 730, width: 24)]
        #expect(MenuBarItemScanner.hiddenItems(among: items).isEmpty)
    }

    @Test("the contiguous run left of the separator is returned in left-to-right order")
    func contiguousRun() {
        let a = Self.window(2, x: -4260, width: 30) // maxX -4230, touching the separator (+30 gap)
        let b = Self.window(3, x: -4300, width: 30) // maxX -4270, 10pt gap
        let visible = Self.window(4, x: 900, width: 24) // right of the separator
        let found = MenuBarItemScanner.hiddenItems(among: [visible, Self.separator, a, b])
        #expect(found.map(\.id) == [3, 2])
    }

    @Test("a gap wider than the contiguity limit ends the run")
    func gapEndsRun() {
        let a = Self.window(2, x: -4240, width: 30)
        let far = Self.window(3, x: -4400, width: 30) // 130pt gap
        let found = MenuBarItemScanner.hiddenItems(among: [Self.separator, a, far])
        #expect(found.map(\.id) == [2])
    }

    @Test("a full-width overlay narrower than the threshold is not mistaken for the separator")
    func overlayIsNotSeparator() {
        let overlay = Self.window(9, x: 0, width: 1710) // NotchNook-style, spans the whole bar
        let icon = Self.window(2, x: -4240, width: 30)
        let found = MenuBarItemScanner.hiddenItems(among: [overlay, Self.separator, icon])
        #expect(found.map(\.id) == [2])
    }

    @Test("with two displays the rightmost separator copy wins")
    func rightmostSeparator() {
        let secondCopy = Self.window(7, x: -9000, width: 5016) // display to the left has its own copy
        let leftIcon = Self.window(8, x: -9040, width: 30) // belongs to that copy's run
        let icon = Self.window(2, x: -4240, width: 30)
        let found = MenuBarItemScanner.hiddenItems(among: [secondCopy, leftIcon, Self.separator, icon])
        #expect(found.map(\.id) == [2])
    }
}
