import XCTest
@testable import StatlyKit

final class FormatTests: XCTestCase {
    func testPercentPadsToFixedWidth() {
        let figureSpace = Format.figureSpace
        XCTAssertEqual(Format.percent(0.07), figureSpace + figureSpace + "7%")
        XCTAssertEqual(Format.percent(0.456), figureSpace + "46%")
        XCTAssertEqual(Format.percent(1.0), "100%")
        XCTAssertEqual(Format.percent(-0.5), figureSpace + figureSpace + "0%")
    }

    func testPercentUnpadded() {
        XCTAssertEqual(Format.percent(0.07, padded: false), "7%")
    }

    func testCompactRate() {
        XCTAssertEqual(Format.compactRate(0), "0K")
        XCTAssertEqual(Format.compactRate(10 * 1024), "10K")
        XCTAssertEqual(Format.compactRate(2_621_440), "2.5M")
        XCTAssertEqual(Format.compactRate(1_610_612_736), "1.5G")
        XCTAssertEqual(Format.compactRate(-5), "0K")
    }

    func testFullRate() {
        XCTAssertEqual(Format.fullRate(0), "0.0 KB/s")
        XCTAssertEqual(Format.fullRate(2_621_440), "2.5 MB/s")
    }

    func testDiskShortUsesDecimalUnits() {
        XCTAssertEqual(Format.diskShort(118_000_000_000), "118G")
        XCTAssertEqual(Format.diskShort(98_500_000_000), "98.5G")
        XCTAssertEqual(Format.diskShort(1_200_000_000_000), "1.20T")
    }

    func testMemoryGBUsesBinaryUnits() {
        XCTAssertEqual(Format.memoryGB(17_179_869_184), "16.0 GB")
    }
}
