import CoreGraphics
import Testing

@testable import MenubarHide

@Suite("Own item position pinning")
@MainActor
struct SanePairTests {
    @Test("the shipping defaults are a sane pair")
    func defaultsAreSane() {
        #expect(StatusBarController.isSanePair(toggle: 250, separator: 265))
    }

    @Test("a swapped pair is scramble damage")
    func swappedRejected() {
        // separator must stay LEFT of (= greater than) the chevron; re-pinning
        // a swapped pair would swallow the chevron on every launch
        #expect(!StatusBarController.isSanePair(toggle: 265, separator: 250))
    }

    @Test("equal positions are rejected")
    func equalRejected() {
        #expect(!StatusBarController.isSanePair(toggle: 250, separator: 250))
    }

    @Test("a toggle at 0 is rejected even though 0 is a valid position")
    func zeroToggleRejected() {
        #expect(MenuBarArrangement.isValid(0))
        #expect(!StatusBarController.isSanePair(toggle: 0, separator: 265))
    }

    @Test("an off-screen parked value is rejected on either side", arguments: [
        (-4220.0, 265.0), (250.0, -4220.0), (250.0, 20_000.0),
    ])
    func parkedRejected(toggle: Double, separator: Double) {
        #expect(!StatusBarController.isSanePair(toggle: toggle, separator: separator))
    }
}

@Suite("Click target must sit in a menu bar strip")
@MainActor
struct MenuBarStripTests {
    // CG global space: origin top-left of the main display, menu bar at y == 0
    static let main = CGRect(x: 0, y: 0, width: 1710, height: 1107)
    /// A display to the LEFT of the main one legitimately has negative x.
    static let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)

    @Test("an ordinary status item on the main display passes")
    func ordinaryItem() {
        let item = CGRect(x: 1500, y: 0, width: 24, height: 24)
        #expect(StatusBarController.isInStrip(item, displays: [Self.main]))
    }

    @Test("an item on a display left of the main one passes")
    func negativeXDisplay() {
        let item = CGRect(x: -500, y: 0, width: 24, height: 24)
        #expect(StatusBarController.isInStrip(item, displays: [Self.main, Self.left]))
    }

    @Test("a window below the menu bar is rejected")
    func belowTheStrip() {
        let item = CGRect(x: 800, y: 500, width: 24, height: 24)
        #expect(!StatusBarController.isInStrip(item, displays: [Self.main]))
    }

    @Test("a window taller than the menu bar is rejected")
    func tooTall() {
        let item = CGRect(x: 800, y: 0, width: 24, height: 200)
        #expect(!StatusBarController.isInStrip(item, displays: [Self.main]))
    }

    @Test("a very wide window merely CENTRED on the strip is rejected")
    func wideWindowCentredOnStrip() {
        // the spoofing shape the centre-point-only check used to let through:
        // centre lands in the strip, but the frame spills off the display
        let item = CGRect(x: -500, y: 0, width: 3000, height: 24)
        #expect(item.midX > Self.main.minX && item.midX < Self.main.maxX)
        #expect(!StatusBarController.isInStrip(item, displays: [Self.main]))
    }

    @Test("a wide but fully contained status item still passes")
    func wideButContained() {
        // clocks and meters are legitimately hundreds of points wide, which is
        // why the check has no width ceiling
        let item = CGRect(x: 1100, y: 0, width: 400, height: 24)
        #expect(StatusBarController.isInStrip(item, displays: [Self.main]))
    }

    @Test("no active display means no click")
    func noDisplays() {
        let item = CGRect(x: 1500, y: 0, width: 24, height: 24)
        #expect(!StatusBarController.isInStrip(item, displays: []))
    }
}
