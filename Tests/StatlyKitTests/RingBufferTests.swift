import XCTest
@testable import StatlyKit

final class RingBufferTests: XCTestCase {
    func testPartialFill() {
        var buffer = RingBuffer(capacity: 3)
        buffer.push(1)
        buffer.push(2)
        XCTAssertEqual(buffer.values(), [1, 2])
    }

    func testWrapAroundKeepsNewestInOrder() {
        var buffer = RingBuffer(capacity: 3)
        for value in 1...5 { buffer.push(Double(value)) }
        XCTAssertEqual(buffer.values(), [3, 4, 5])
    }

    func testEmpty() {
        let buffer = RingBuffer(capacity: 3)
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.values(), [])
    }
}
