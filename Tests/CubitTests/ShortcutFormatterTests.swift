import XCTest
import AppKit
import Carbon.HIToolbox
@testable import Cubit

final class ShortcutFormatterTests: XCTestCase {
    func testFormatsDefaultBindingAsCanonicalGlyphs() {
        let string = ShortcutFormatter.string(
            keyCode: UInt32(kVK_ANSI_M),
            carbonModifiers: UInt32(controlKey | optionKey | cmdKey)
        )
        XCTAssertEqual(string, "⌃⌥⌘M")
    }

    func testModifierOrderIsControlOptionShiftCommand() {
        let string = ShortcutFormatter.modifierString(
            carbonModifiers: UInt32(cmdKey | shiftKey | controlKey | optionKey)
        )
        XCTAssertEqual(string, "⌃⌥⇧⌘")
    }

    func testDigitAndLetterGlyphs() {
        XCTAssertEqual(ShortcutFormatter.keyGlyph(for: UInt32(kVK_ANSI_0)), "0")
        XCTAssertEqual(ShortcutFormatter.keyGlyph(for: UInt32(kVK_ANSI_9)), "9")
        XCTAssertEqual(ShortcutFormatter.keyGlyph(for: UInt32(kVK_ANSI_A)), "A")
        XCTAssertEqual(ShortcutFormatter.keyGlyph(for: UInt32(kVK_ANSI_Z)), "Z")
    }

    func testFunctionKeyGlyphs() {
        XCTAssertEqual(ShortcutFormatter.keyGlyph(for: UInt32(kVK_F1)), "F1")
        XCTAssertEqual(ShortcutFormatter.keyGlyph(for: UInt32(kVK_F12)), "F12")
    }

    func testArrowAndSpecialKeyGlyphs() {
        XCTAssertEqual(ShortcutFormatter.keyGlyph(for: UInt32(kVK_LeftArrow)), "←")
        XCTAssertEqual(ShortcutFormatter.keyGlyph(for: UInt32(kVK_Space)), "Space")
        XCTAssertEqual(ShortcutFormatter.keyGlyph(for: UInt32(kVK_Escape)), "⎋")
    }

    func testUnknownKeyCodeFallsBackToHexLabel() {
        XCTAssertEqual(ShortcutFormatter.keyGlyph(for: 0xFE), "Key 0xFE")
    }

    func testCarbonModifiersFromNSEventFlagsRoundTrips() {
        let flags: NSEvent.ModifierFlags = [.control, .option, .command]
        let carbon = ShortcutFormatter.carbonModifiers(from: flags)
        XCTAssertEqual(carbon, UInt32(controlKey | optionKey | cmdKey))

        let roundTripped = ShortcutFormatter.modifierFlags(fromCarbon: carbon)
        XCTAssertEqual(roundTripped, flags)
    }

    func testShiftOnlyFlagConversion() {
        let carbon = ShortcutFormatter.carbonModifiers(from: [.shift])
        XCTAssertEqual(carbon, UInt32(shiftKey))
        XCTAssertEqual(ShortcutFormatter.modifierFlags(fromCarbon: carbon), [.shift])
    }

    func testHasRequiredModifierRejectsPlainOrShiftOnlyKeys() {
        XCTAssertFalse(ShortcutFormatter.hasRequiredModifier(carbonModifiers: 0))
        XCTAssertFalse(ShortcutFormatter.hasRequiredModifier(carbonModifiers: UInt32(shiftKey)))
    }

    func testHasRequiredModifierAcceptsCommandOptionOrControl() {
        XCTAssertTrue(ShortcutFormatter.hasRequiredModifier(carbonModifiers: UInt32(cmdKey)))
        XCTAssertTrue(ShortcutFormatter.hasRequiredModifier(carbonModifiers: UInt32(optionKey)))
        XCTAssertTrue(ShortcutFormatter.hasRequiredModifier(carbonModifiers: UInt32(controlKey)))
    }
}
