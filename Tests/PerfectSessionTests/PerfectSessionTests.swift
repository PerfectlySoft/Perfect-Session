import XCTest
@testable import PerfectSession

class PerfectSessionTests: XCTestCase {
//    func testExample() {
//        // This is an example of a functional test case.
//        // Use XCTAssert and related functions to verify your tests produce the correct results.
//        XCTAssertEqual(Perfect_Session().text, "Hello, World!")
//    }

	func testValids() {
		XCTAssert(CSRFSecurity.isValid(origin: "www.example.com", host: "www.example.com"))
		XCTAssert(CSRFSecurity.isValid(origin: "www.example.com", host: "something.example.com") == false)
		XCTAssert(CSRFSecurity.isValid(origin: "", host: "www.hello.com") == false)
		XCTAssert(CSRFSecurity.isValid(origin: "", host: "") == false)
		XCTAssert(CSRFSecurity.isValid(origin: "www.example.com", host: "") == false)
	}


//	func testValidWithArray() {
//		SessionConfig.CSRFacceptableHostnames.append("www.example2.com")
//		SessionConfig.CSRFacceptableHostnames.append("something.example2.com")
//		XCTAssert(CSRFSecurity.isValid(origin: "www.example2.com", host: ""))
//		XCTAssert(CSRFSecurity.isValid(origin: "www.example.com", host: "") == false)
//		XCTAssert(CSRFSecurity.isValid(origin: "example.com", host: "") == false)
//		XCTAssert(CSRFSecurity.isValid(origin: "something.example2.com", host: ""))
//	}


    static var allTests : [(String, (PerfectSessionTests) -> () throws -> Void)] {
        return [
			("testValids", testValids),
//			("testValidWithArray", testValidWithArray),
        ]
    }
}
