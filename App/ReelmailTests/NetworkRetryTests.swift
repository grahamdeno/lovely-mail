import XCTest
@testable import Reelmail

final class NetworkRetryTests: XCTestCase {
    func testRetriesADroppedConnectionThenSucceeds() async throws {
        let calls = Counter()
        let request = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/x/modify")!)
        let (data, _) = try await NetworkRetry.data(for: request) { r in
            if await calls.next() == 1 { throw URLError(.networkConnectionLost) }
            return (Data("{}".utf8), HTTPURLResponse(url: r.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "{}")
        let n = await calls.value
        XCTAssertEqual(n, 2)
    }

    func testDoesNotRetryOtherErrors() async {
        let calls = Counter()
        let request = URLRequest(url: URL(string: "https://example.com")!)
        do {
            _ = try await NetworkRetry.data(for: request) { _ in _ = await calls.next(); throw URLError(.badURL) }
            XCTFail("Should throw")
        } catch {}
        let n = await calls.value
        XCTAssertEqual(n, 1)
    }
}

private actor Counter {
    var value = 0
    func next() -> Int { value += 1; return value }
}
