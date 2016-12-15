import XCTest
@testable import Perfect_Session

class Perfect_SessionTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        XCTAssertEqual(Perfect_Session().text, "Hello, World!")
    }


    static var allTests : [(String, (Perfect_SessionTests) -> () throws -> Void)] {
        return [
            ("testExample", testExample),
        ]
    }
}
