import XCTest
@testable import DeepCuts

/// The tester-feedback function answers failures as `{"error": "<a sentence for the tester>"}`.
final class FeedbackErrorTests: XCTestCase {
    private let draft = FeedbackDraft(installID: "install-12345", name: "", text: "A fine app", context: [:], screenshot: nil)

    private func makeService(status: Int, body: String) -> FeedbackService {
        let session = StubURLProtocol.session { _ in (status: status, body: Data(body.utf8)) }
        return FeedbackService(endpoint: URL(string: "https://example.test/tester-feedback"), key: "key", session: session)
    }

    func testTheServersSentenceIsWhatTheTesterReads() async {
        let service = makeService(status: 429, body: #"{"error":"That's plenty for today. Try again tomorrow."}"#)
        do {
            _ = try await service.send(draft)
            XCTFail("a 429 is not a sent suggestion")
        } catch {
            XCTAssertEqual(error.localizedDescription, "That's plenty for today. Try again tomorrow.")
        }
    }

    func testAnErrorWithNoSentenceStillSaysSomething() async {
        let service = makeService(status: 502, body: "")
        do {
            _ = try await service.send(draft)
            XCTFail("a 502 is not a sent suggestion")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testASentSuggestionReturnsItsID() async throws {
        let id = try await makeService(status: 200, body: #"{"id":41}"#).send(draft)
        XCTAssertEqual(id, 41)
    }
}
