import XCTest
import CoreGraphics
@testable import TransliterationCore

final class NotchLayoutTests: XCTestCase {
    func testExpansionIsSmallAndSharesBandPadding() {
        let layout = NotchLayout(notchWidth: 185)
        XCTAssertEqual(layout.bandWidth, 317)
        XCTAssertEqual(layout.resultWidth, 339)
        XCTAssertEqual(layout.contentWidth, 269)
        XCTAssertEqual(layout.bodyInset(in: layout.bandWidth), NotchLayout.horizontalPadding)
        XCTAssertEqual(layout.bodyInset(in: layout.resultWidth), 35)
        XCTAssertLessThan(layout.resultWidth / layout.bandWidth, 1.08)
    }
    func testBandAnchorsAndBodyEdgesStayFixedAcrossExpansion() {
        let cases: [(CGRect, CGFloat, CGFloat, CGFloat)] = [
            (CGRect(x: 0, y: 0, width: 1512, height: 982), 755.5, 185, 32),
            (CGRect(x: -1920, y: 240, width: 1920, height: 1080), -960, 150, 0),
            (CGRect(x: 1512, y: -100, width: 1920, height: 1080), 2472, 150, 0)
        ]
        for (screen, center, notch, safeTop) in cases {
            for scale: CGFloat in [1, 2] {
                let layout = NotchLayout(notchWidth: notch)
                let compact = NotchGeometry.compactFrame(screen: screen, notchWidth: notch, safeTop: safeTop,
                                                         centerX: center, backingScale: scale)
                let expanded = NotchGeometry.expandedFrame(screen: screen, width: layout.resultWidth,
                                                           contentHeight: 220, safeTop: safeTop,
                                                           centerX: center, backingScale: scale)
                let bandHeight = max(28, safeTop)
                XCTAssertEqual(layout.logoFrame(in: compact, bandHeight: bandHeight), layout.logoFrame(in: expanded, bandHeight: bandHeight))
                XCTAssertEqual(layout.waveformFrame(in: compact, bandHeight: bandHeight), layout.waveformFrame(in: expanded, bandHeight: bandHeight))
                XCTAssertEqual(expanded.minX + layout.bodyInset(in: expanded.width), layout.logoFrame(in: expanded, bandHeight: bandHeight).minX)
                XCTAssertEqual(expanded.maxX - layout.bodyInset(in: expanded.width), layout.waveformFrame(in: expanded, bandHeight: bandHeight).maxX)
                XCTAssertEqual(compact.union(expanded).midX, compact.midX)
            }
        }
    }
    func testNativeWholePointRoundingCannotShiftCenterBetweenModes() {
        for notch: CGFloat in [150, 185, 185.5, 212] {
            let layout = NotchLayout(notchWidth: notch)
            let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
            let compact = NotchGeometry.compactFrame(screen: screen, notchWidth: notch, safeTop: 32, centerX: 755.5)
            let expanded = NotchGeometry.expandedFrame(screen: screen, width: layout.resultWidth, safeTop: 32, centerX: 755.5)
            let compactCenter = compact.minX.rounded() + compact.width.rounded() / 2
            let expandedCenter = expanded.minX.rounded() + expanded.width.rounded() / 2
            XCTAssertEqual(compactCenter, expandedCenter)
        }
    }
}
