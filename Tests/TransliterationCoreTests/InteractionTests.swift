import XCTest
@testable import TransliterationCore

final class InteractionTests: XCTestCase {
    func testRightShiftDeviceFlagsIgnoreLeftShiftChordsAndRecoverAfterInterruption() {
        var shortcut = RightShiftDoublePress()
        let shift: UInt64 = 1 << 17
        XCTAssertFalse(shortcut.flagsChanged(keyCode: 56, flags: shift | 0x2, now: 0))
        XCTAssertFalse(shortcut.flagsChanged(keyCode: 56, flags: 0, now: 0.05))
        XCTAssertFalse(shortcut.flagsChanged(keyCode: 60, flags: shift | 0x4, now: 0.1))
        XCTAssertFalse(shortcut.flagsChanged(keyCode: 60, flags: 0, now: 0.15))
        XCTAssertTrue(shortcut.flagsChanged(keyCode: 60, flags: shift | 0x4, now: 0.2))
        XCTAssertFalse(shortcut.flagsChanged(keyCode: 60, flags: 0, now: 0.25))
        XCTAssertFalse(shortcut.flagsChanged(keyCode: 60, flags: shift | 0x4 | (1 << 20), now: 0.3))
        XCTAssertFalse(shortcut.flagsChanged(keyCode: 60, flags: 1 << 20, now: 0.35))
        XCTAssertFalse(shortcut.flagsChanged(keyCode: 60, flags: shift | 0x4, now: 0.4))
        shortcut.cancel() // Another key was typed while Shift was held.
        XCTAssertFalse(shortcut.flagsChanged(keyCode: 60, flags: shift | 0x2, now: 0.45))
        XCTAssertFalse(shortcut.flagsChanged(keyCode: 60, flags: shift | 0x4, now: 0.5))
        XCTAssertFalse(shortcut.flagsChanged(keyCode: 60, flags: 0, now: 0.55))
        XCTAssertTrue(shortcut.flagsChanged(keyCode: 60, flags: shift | 0x4, now: 0.6))
    }
    func testDoubleRightShiftRequiresTwoSeparatePressesAndDoesNotRepeatWhileHeld() {
        var presses = DoublePress()
        XCTAssertFalse(presses.update(pressed: true, now: 0))
        XCTAssertFalse(presses.update(pressed: true, now: 0.1))
        XCTAssertFalse(presses.update(pressed: false, now: 0.15))
        XCTAssertTrue(presses.update(pressed: true, now: 0.3))
        XCTAssertFalse(presses.update(pressed: true, now: 0.31))
        XCTAssertFalse(presses.update(pressed: false, now: 0.4))
        XCTAssertFalse(presses.update(pressed: true, now: 0.5))
    }
    func testSlowPressAndInterruptedShiftShortcutDoNotToggle() {
        var presses = DoublePress()
        XCTAssertFalse(presses.update(pressed: true, now: 0))
        XCTAssertFalse(presses.update(pressed: false, now: 0.1))
        XCTAssertFalse(presses.update(pressed: true, now: 1))
        presses.cancel()
        XCTAssertFalse(presses.update(pressed: false, now: 1.1))
        XCTAssertFalse(presses.update(pressed: true, now: 1.2))
        XCTAssertFalse(presses.update(pressed: false, now: 1.3))
        XCTAssertTrue(presses.update(pressed: true, now: 1.4))
    }
    func testOnlyConvertedLettersAreHighlightedInline() {
        let runs = Transliterator.runs(in: "O'zbekcha shahar\nğoya https://shahar.uz")
        XCTAssertEqual(runs.map(\.text).joined(), "Özbekça şahar\nğoya https://shahar.uz")
        XCTAssertEqual(runs.filter(\.changed).map(\.text), ["Ö", "ç", "ş"])
        XCTAssertTrue(runs.last?.text.hasSuffix("https://shahar.uz") == true)
        XCTAssertEqual(runs.last?.changed, false)
    }
    func testExistingNewAlphabetAndProtectedAddressesDoNotLookChanged() {
        XCTAssertTrue(Transliterator.runs(in: "Ö Ğ Ş Ç ma’no shox@chiroy.uz").allSatisfy { !$0.changed })
        let text = "👋 g'oya\n\nCHIROQ ma'no"
        let runs = Transliterator.runs(in: text)
        XCTAssertEqual(runs.map(\.text).joined(), "👋 ğoya\n\nÇIROQ ma’no")
        XCTAssertEqual(runs.filter(\.changed).map(\.text), ["ğ", "Ç", "’"])
    }
}
