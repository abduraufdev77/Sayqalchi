import XCTest
import CoreGraphics
@testable import TransliterationCore

final class TransliteratorTests: XCTestCase {
    func testPDFMappingsAndCase() {
        let cases = [
            "O'zbekiston": "Özbekiston", "g'oya": "ğoya", "Shahar": "Şahar",
            "chiroyli": "çiroyli", "SHOSHILINCH": "ŞOŞILINÇ", "G'ALABA": "ĞALABA",
            "O‘ZBEKCHA": "ÖZBEKÇA", "koʻngil": "köngil", "toʼgʼri": "töğri",
            "o`zgarish": "özgariş", "ma'no": "ma’no", "s'h": "s’h",
            "tong": "tong", "Özbekça, Ğ Ş Ç": "Özbekça, Ğ Ş Ç",
            "O\u{0308}zbek": "Özbek", "'salom'": "'salom'"
        ]
        for (source, expected) in cases { XCTAssertEqual(Transliterator.convert(source), expected, source) }
    }
    func testAddressesStayUnchanged() {
        let text = "https://shahar.uz/ch?o'g=1 shox@chiroy.uz www.shahar.uz shahar.uz"
        XCTAssertEqual(Transliterator.convert(text), text)
    }
    func testUnicodeOffsetsAndBoundary() throws {
        let text = "👋 o'zbekcha "
        let s = try XCTUnwrap(Transliterator.suggestion(in: text, caret: (text as NSString).length))
        XCTAssertEqual(s.original, "o'zbekcha")
        XCTAssertEqual(s.replacement, "özbekça")
        XCTAssertEqual(s.range, NSRange(location: 3, length: 9))
        XCTAssertTrue(s.atBoundary)
    }
    func testNoPartialOrProtectedReplacement() {
        XCTAssertNil(Transliterator.suggestion(in: "shahar", caret: 2))
        XCTAssertNil(Transliterator.suggestion(in: "foo@shahar", caret: 10))
        XCTAssertNil(Transliterator.suggestion(in: "https://shahar", caret: 14))
        XCTAssertNil(Transliterator.suggestion(in: "salom", caret: 5))
        XCTAssertNil(Transliterator.suggestion(in: "", caret: 0))
    }
    func testAlphabet() { XCTAssertEqual(Transliterator.alphabet.count, 28) }
    func testIdempotence() {
        let once = Transliterator.convert("O'zbekistonning go'zal shaharlari, ma'no va chiroq.")
        XCTAssertEqual(Transliterator.convert(once), once)
    }
    func testParagraphIncludesChangedWordsWhenLastWordDoesNotChange() throws {
        let text = "O'zbekiston go'zal. Shahar juda yaxshi, salom! "
        let s = try XCTUnwrap(Transliterator.paragraphSuggestion(in: text, caret: (text as NSString).length))
        XCTAssertEqual(s.original, text)
        XCTAssertEqual(s.replacement, "Özbekiston gözal. Şahar juda yaxşi, salom! ")
        XCTAssertEqual(s.range, NSRange(location: 0, length: (text as NSString).length))
    }
    func testParagraphDoesNotReplacePreviousMessagesOrSuffix() throws {
        let text = "Old shahar\n👋 O'zbekcha, salom! suffix"
        let caret = ("Old shahar\n👋 O'zbekcha, salom! " as NSString).length
        let s = try XCTUnwrap(Transliterator.paragraphSuggestion(in: text, caret: caret))
        XCTAssertEqual(s.original, "👋 O'zbekcha, salom! ")
        XCTAssertEqual(s.replacement, "👋 Özbekça, salom! ")
        XCTAssertEqual((text as NSString).replacingCharacters(in: s.range, with: s.replacement), "Old shahar\n👋 Özbekça, salom! suffix")
    }
    func testParagraphProtectsAddressesAndRejectsPartialContext() throws {
        let text = "https://shahar.uz shox@chiroy.uz O'zbekcha salom"
        XCTAssertEqual(try XCTUnwrap(Transliterator.paragraphSuggestion(in: text, caret: (text as NSString).length)).replacement,
                       "https://shahar.uz shox@chiroy.uz Özbekça salom")
        XCTAssertNil(Transliterator.paragraphSuggestion(in: "shahar", caret: 2))
        XCTAssertNil(Transliterator.paragraphSuggestion(in: "shahar", caret: 6, startsAtDocumentStart: false))
        XCTAssertNil(Transliterator.paragraphSuggestion(in: "salom! ", caret: 7))
    }
    func testTypingPauseInvalidatesOldPreviewAndResetsOnFocusChange() {
        var pause = TypingPause()
        XCTAssertFalse(pause.ready(key: "field1:text", now: 0))
        XCTAssertFalse(pause.ready(key: "field1:text", now: 0.64))
        XCTAssertTrue(pause.ready(key: "field1:text", now: 0.66))
        XCTAssertFalse(pause.ready(key: "field1:new text", now: 0.7))
        XCTAssertTrue(pause.ready(key: "field1:new text", now: 1.36))
        pause.reset()
        XCTAssertFalse(pause.ready(key: "field1:new text", now: 2))
    }
    func testNotchTouchesPhysicalTopOnBothDisplays() {
        for screen in [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: -1920, y: 240, width: 1920, height: 1080)] {
            let frame = NotchGeometry.expandedFrame(screen: screen, safeTop: 32)
            XCTAssertEqual(frame.maxY, screen.maxY + 0.5)
            XCTAssertEqual(frame.midX, screen.midX)
            XCTAssertEqual(frame.height, 272.5)
            XCTAssertEqual(frame.intersection(screen).height, 272)
        }
    }
    func testTopOverscanAndHardwareCenterArePixelAligned() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let compact = NotchGeometry.compactFrame(screen: screen, notchWidth: 185, safeTop: 32, centerX: 755.5, backingScale: 2)
        XCTAssertEqual(compact.midX, 755.5)
        XCTAssertEqual(compact.width, 317)
        XCTAssertEqual(compact.maxY, 982.5)
        XCTAssertEqual(compact.minY, 950)
        let external = NotchGeometry.expandedFrame(screen: screen, safeTop: 0, backingScale: 1)
        XCTAssertEqual(external.maxY, 983)
        XCTAssertEqual(external.minX.rounded(), external.minX)
    }
    func testWholeFieldConvertsEveryParagraphAndPreservesLineBreaks() throws {
        let source = "O'zbekcha yozish oson.\n\nG'oya va shahar.\r\nCHIROQ\t👋 salom!"
        let s = try XCTUnwrap(Transliterator.fieldSuggestion(in: source))
        XCTAssertEqual(s.original, source)
        XCTAssertEqual(s.replacement, "Özbekça yoziş oson.\n\nĞoya va şahar.\r\nÇIROQ\t👋 salom!")
        XCTAssertEqual(s.range, NSRange(location: 0, length: (source as NSString).length))
    }
    func testWholeFieldIsNotLimitedToLast4096Characters() throws {
        let source = "O'zbekcha\n" + String(repeating: "salom ", count: 1000) + "\nShahar, chiroq."
        let s = try XCTUnwrap(Transliterator.fieldSuggestion(in: source))
        XCTAssertTrue(s.replacement.hasPrefix("Özbekça\n"))
        XCTAssertTrue(s.replacement.hasSuffix("\nŞahar, çiroq."))
        XCTAssertEqual(s.range.length, (source as NSString).length)
    }
    func testWholeFieldCaretMappingBeforeAndAfterCursor() throws {
        let source = "👋 O'zbekcha\nshahar"
        XCTAssertEqual(Transliterator.convertedCaret(in: source, utf16Location: 0), 0)
        let originalCaret = ("👋 O'zbekcha" as NSString).length
        XCTAssertEqual(Transliterator.convertedCaret(in: source, utf16Location: originalCaret), ("👋 Özbekça" as NSString).length)
        XCTAssertEqual(Transliterator.convertedCaret(in: source, utf16Location: (source as NSString).length), ("👋 Özbekça\nşahar" as NSString).length)
        XCTAssertNil(Transliterator.convertedCaret(in: source, utf16Location: 1))
        XCTAssertEqual(try XCTUnwrap(Transliterator.fieldSuggestion(in: source)).replacement, "👋 Özbekça\nşahar")
    }
}
