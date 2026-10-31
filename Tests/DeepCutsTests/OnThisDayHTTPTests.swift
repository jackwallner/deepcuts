import XCTest
@testable import DeepCuts

/// Today keeps a loaded day for good, so a bad answer from Wikipedia must be a failure the
/// screen can retry, not an empty list of music history.
final class OnThisDayHTTPTests: XCTestCase {
    func testAServerErrorIsAFailureNotAnEmptyDay() async {
        let session = StubURLProtocol.session { _ in (status: 503, body: Data(#"{"type":"internal_server_error"}"#.utf8)) }
        do {
            let moments = try await OnThisDay.moments(month: 10, day: 21, artists: [], session: session)
            XCTFail("a 503 came back as \(moments.count) music moments")
        } catch {}
    }

    func testAPageThatIsNotTheFeedIsAFailureToo() async {
        let session = StubURLProtocol.session { _ in (status: 200, body: Data("<html>Sign in to the hotel Wi-Fi</html>".utf8)) }
        do {
            let moments = try await OnThisDay.moments(month: 10, day: 21, artists: [], session: session)
            XCTFail("a login page came back as \(moments.count) music moments")
        } catch {}
    }

    func testTheFeedStillParses() async throws {
        let feed = #"{"births":[{"text":"Steve Cropper, American guitarist","year":1941,"pages":[{"description":"American guitarist"}]}]}"#
        let session = StubURLProtocol.session { _ in (status: 200, body: Data(feed.utf8)) }
        let moments = try await OnThisDay.moments(month: 10, day: 21, artists: [], session: session)
        XCTAssertEqual(moments.map(\.year), [1941])
    }
}
