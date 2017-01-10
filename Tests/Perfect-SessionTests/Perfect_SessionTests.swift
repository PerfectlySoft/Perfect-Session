import XCTest
@testable import PerfectSession

class Perfect_SessionTests: XCTestCase {
//    func testExample() {
//        // This is an example of a functional test case.
//        // Use XCTAssert and related functions to verify your tests produce the correct results.
//        XCTAssertEqual(Perfect_Session().text, "Hello, World!")
//    }
	var obj = CSRFSecurity()

	func testValids() {
		XCTAssert(obj.isValid(origin: "www.example.com", host: "www.example.com"))
		XCTAssert(obj.isValid(origin: "www.example.com", host: "something.example.com") == false)
		XCTAssert(obj.isValid(origin: "", host: "www.hello.com") == false)
		XCTAssert(obj.isValid(origin: "", host: "") == false)
		XCTAssert(obj.isValid(origin: "www.example.com", host: "") == false)
	}


	func testValidWithArray() {
		SessionConfig.CSRFacceptableHostnames.append("www.example2.com")
		SessionConfig.CSRFacceptableHostnames.append("something.example2.com")
		XCTAssert(obj.isValid(origin: "www.example2.com", host: ""))
		XCTAssert(obj.isValid(origin: "www.example.com", host: "") == false)
		XCTAssert(obj.isValid(origin: "example.com", host: "") == false)
		XCTAssert(obj.isValid(origin: "something.example2.com", host: ""))
	}


    static var allTests : [(String, (Perfect_SessionTests) -> () throws -> Void)] {
        return [
			("testValids", testValids),
			("testValidWithArray", testValidWithArray),
        ]
    }
}
