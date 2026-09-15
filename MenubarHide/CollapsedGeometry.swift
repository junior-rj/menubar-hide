import CoreGraphics

/// How wide the separator (and its spacers) must get to hide the icons.
///
/// macOS 26 and earlier: the window server clamps a 10 000pt item (~5016
/// delivered) and everything left of it slides off-screen.
///
/// macOS 27 rewrote the menu bar. An item whose length reaches a per-display
/// cliff is DISCARDED, not clamped, and the bar is left as it was; below the
/// cliff the bar no longer reflows around the item but overflows from the
/// left, moving the leftmost items into the system's own « menu until the
/// rest fits. So the separator plus spacers must span the status area of the
/// widest display while every single item stays under the cliff of the
/// narrowest one (one length applies to every display's copy of the bar).
///
/// Cliffs measured on 27.0: half the width on displays without a notch
/// (2056pt hides at 1000 and drops at 1028, 3840 drops at 1920, Hidden Bar
/// maintainers' numbers); on a notched 1512pt display whose trailing area is
/// 663.5pt the drop sits between 520 and 530 regardless of the frontmost app's
/// menu width, so there the cliff tracks the trailing area, not the display.
enum CollapsedGeometry {
    struct Display: Equatable {
        /// Full width of the display.
        let width: CGFloat
        /// Width available to status items: the area right of the notch when
        /// there is one, the full width otherwise.
        let statusWidth: CGFloat

        init(width: CGFloat, statusWidth: CGFloat? = nil) {
            self.width = width
            self.statusWidth = statusWidth ?? width
        }
    }

    static let legacyLength: CGFloat = 10_000
    static let minimumUnit: CGFloat = 200
    /// Safety distance under the cliff; the measured points are not exact.
    static let cliffMargin: CGFloat = 64
    /// 0.75 of the trailing area stays under the ~0.79 measured on the notch.
    static let notchedCliffFactor: CGFloat = 0.75
    /// Fixed so every launch registers the same autosave names: a name first
    /// seen on a later launch would land leftmost, outside the block.
    static let spacerCount = 6

    static func cliff(of display: Display) -> CGFloat {
        display.statusWidth < display.width
            ? display.statusWidth * notchedCliffFactor
            : display.width / 2
    }

    /// Length for the separator and each active spacer: under every cliff.
    static func unitLength(displays: [Display]) -> CGFloat {
        guard let lowest = displays.map(cliff(of:)).min() else { return minimumUnit }
        return max(minimumUnit, (lowest - cliffMargin).rounded(.down))
    }

    /// Spacers to inflate so separator + spacers cover the widest status area.
    /// Surplus spacers would only overflow themselves (harmless but they show
    /// as blank rows in the « menu), so the count is the minimum needed.
    static func activeSpacers(unit: CGFloat, displays: [Display]) -> Int {
        guard unit > 0, let widest = displays.map(\.statusWidth).max() else { return 0 }
        let needed = Int((widest / unit).rounded(.up)) - 1
        return min(max(needed, 0), spacerCount)
    }
}
