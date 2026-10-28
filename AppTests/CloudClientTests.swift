import XCTest
import Foundation
@testable import Steady

private final class OfflineRegressionProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var offline = false
    static func setOffline(_ value: Bool) { lock.lock(); defer { lock.unlock() }; offline = value }
    private static func isOffline() -> Bool { lock.lock(); defer { lock.unlock() }; return offline }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard !Self.isOffline() else { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
        let circle = "00000000-0000-4000-8000-000000000001"
        let user = "00000000-0000-4000-8000-000000000002"
        let payload: Any
        switch request.url?.path {
        case "/rest/v1/circles": payload = [["id": circle, "name": "Fictional circle", "owner_id": user]]
        case "/rest/v1/rpc/my_role": payload = "survivor"
        case "/rest/v1/rpc/my_permissions": payload = [["kind": "symptoms", "can_read": true, "can_add": true, "can_edit": true, "can_delete": true]] as [[String: Any]]
        case "/rest/v1/records": payload = [["id": "00000000-0000-4000-8000-000000000003", "circle_id": circle, "kind": "symptoms", "author_id": user, "title": "Fictional symptom", "body": "Fictional test only", "created_at": "2026-10-28T12:00:00Z", "updated_at": "2026-10-28T12:00:00Z"]]
        case "/rest/v1/check_ins", "/rest/v1/circle_permissions", "/rest/v1/circle_members", "/rest/v1/circle_invitations": payload = [Any]()
        default: client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.fragmentsAllowed])
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class CloudClientTests: XCTestCase {
    @MainActor func testManualRefreshFailureClearsHistoryButKeepsSessionForRetry() async throws {
        OfflineRegressionProtocol.setOffline(false)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineRegressionProtocol.self]
        let network = URLSession(configuration: configuration)
        defer { network.invalidateAndCancel(); OfflineRegressionProtocol.setOffline(false) }
        let session = CloudSession(access_token: "fictional-access-token", refresh_token: "fictional-refresh-token",
            expires_at: Date().timeIntervalSince1970 + 3600,
            user: CloudUser(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, email: "fictional@example.test"))
        let client = CloudClient(config: BackendConfig(url: URL(string: "https://fictional.invalid")!, key: "sb_publishable_TEST_PLACEHOLDER"), network: network, initialSession: session)
        try await client.loadCircles()
        XCTAssertEqual(client.records.count, 1, "Positive precondition: history was loaded")
        XCTAssertTrue(client.can(.symptoms, .read))
        OfflineRegressionProtocol.setOffline(true)
        var failed = false
        do { try await client.loadCircles() } catch { failed = true }
        XCTAssertTrue(failed)
        XCTAssertTrue(client.records.isEmpty)
        XCTAssertTrue(client.permissions.isEmpty)
        XCTAssertTrue(client.circles.isEmpty)
        XCTAssertTrue(client.checkIns.isEmpty)
        XCTAssertTrue(client.members.isEmpty)
        XCTAssertTrue(client.invitations.isEmpty)
        XCTAssertTrue(client.grants.isEmpty)
        XCTAssertNil(client.role)
        XCTAssertEqual(client.session?.user.id, session.user.id, "Network failure must not erase the account session")
        OfflineRegressionProtocol.setOffline(false)
        try await client.loadCircles()
        XCTAssertEqual(client.records.count, 1, "Refresh can recover when the connection returns")
    }
}
