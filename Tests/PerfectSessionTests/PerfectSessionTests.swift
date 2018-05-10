import XCTest
import Foundation
@testable import PerfectSession

class PerfectSessionTests: XCTestCase {

	func testValids() {
		XCTAssert(CSRFSecurity.isValid(origin: "www.example.com", host: "www.example.com"))
		XCTAssert(CSRFSecurity.isValid(origin: "www.example.com", host: "something.example.com") == false)
		XCTAssert(CSRFSecurity.isValid(origin: "", host: "www.hello.com") == false)
		XCTAssert(CSRFSecurity.isValid(origin: "", host: "") == false)
		XCTAssert(CSRFSecurity.isValid(origin: "www.example.com", host: "") == false)
	}

	func testMemory() {
		let token = UUID().uuidString
		var session = PerfectSession()
		session.token = token
		
		XCTAssertNil(MemorySessions.get(key: token))
		MemorySessions.set(key: token, session)
		let fnd = MemorySessions.get(key: token)
		XCTAssertNotNil(fnd)
		XCTAssertEqual(fnd!.token, token)
		MemorySessions.remove(key: token)
		XCTAssertNil(MemorySessions.get(key: token))
	}

    static var allTests : [(String, (PerfectSessionTests) -> () throws -> Void)] {
        return [
			("testValids", testValids),
			("testMemory", testMemory),
        ]
    }
}
