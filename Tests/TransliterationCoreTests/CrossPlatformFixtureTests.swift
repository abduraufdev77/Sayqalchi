import XCTest
@testable import TransliterationCore

final class CrossPlatformFixtureTests: XCTestCase {
    func testWindowsAndMacUseTheSameAlphabetExamples() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        struct Fixture: Decodable { let input: String; let expected: String }
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: root.appendingPathComponent("shared/format-fixtures.json")))
        for fixture in fixtures { XCTAssertEqual(Transliterator.convert(fixture.input), fixture.expected) }
    }
}
