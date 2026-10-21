import XCTest
@testable import TransliterationCore

final class InteractionTests: XCTestCase {
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
