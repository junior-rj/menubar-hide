import Foundation
import Testing

@testable import MenubarHide

@Suite("Arrangement position validity")
struct PositionValidityTests {
    @Test("0 is a legitimate position (rightmost)")
    func zeroIsValid() {
        #expect(MenuBarArrangement.isValid(0))
    }

    @Test("the off-screen parking value is rejected")
    func parkedIsInvalid() {
        // the real value macOS autosaves for an item pushed off the bar
        #expect(!MenuBarArrangement.isValid(-4220))
    }

    @Test("the range is closed at both ends", arguments: [
        (10_000.0, true), (10_001.0, false), (250.0, true), (-0.5, false),
    ])
    func bounds(position: Double, expected: Bool) {
        #expect(MenuBarArrangement.isValid(position) == expected)
    }
}

@Suite("Arrangement snapshot merge")
struct MergeTests {
    @Test("a fresh reading wins over the remembered one")
    func freshWins() {
        let merged = MenuBarArrangement.merge(
            saved: ["app.a": ["Item-0": 1]],
            fresh: ["app.a": ["Item-0": 2]],
            liveDomains: ["app.a"])
        #expect(merged == ["app.a": ["Item-0": 2]])
    }

    @Test("a domain whose plist is gone is dropped")
    func uninstalledDomainDropped() {
        let merged = MenuBarArrangement.merge(
            saved: ["app.a": ["Item-0": 1], "app.gone": ["Item-0": 3]],
            fresh: [:],
            liveDomains: ["app.a"])
        #expect(merged == ["app.a": ["Item-0": 1]])
    }

    @Test("a key missing from the fresh reading keeps its remembered value")
    func corruptedKeySurvives() {
        // capture() drops damaged values, so the key simply isn't in `fresh`.
        // This is the whole point of merging instead of replacing: the last
        // good value must survive exactly when the live one is garbage.
        let merged = MenuBarArrangement.merge(
            saved: ["app.a": ["Item-0": 5, "Item-1": 7]],
            fresh: ["app.a": ["Item-1": 8]],
            liveDomains: ["app.a"])
        #expect(merged == ["app.a": ["Item-0": 5, "Item-1": 8]])
    }

    @Test("a newly seen domain is added")
    func newDomainAdded() {
        let merged = MenuBarArrangement.merge(
            saved: [:], fresh: ["app.new": ["Item-0": 1]], liveDomains: ["app.new"])
        #expect(merged == ["app.new": ["Item-0": 1]])
    }
}

@Suite("Menu bar spacing")
struct SpacingTests {
    @Test("every preset sits inside the range the custom prompt enforces")
    func presetsWithinRange() {
        for preset in MenuBarSpacing.presets {
            #expect(MenuBarSpacing.allowedRange.contains(preset), "preset \(preset) out of range")
        }
    }

    @Test("presets are sorted and free of duplicates")
    func presetsOrdered() {
        #expect(MenuBarSpacing.presets == MenuBarSpacing.presets.sorted())
        #expect(Set(MenuBarSpacing.presets).count == MenuBarSpacing.presets.count)
    }
}
