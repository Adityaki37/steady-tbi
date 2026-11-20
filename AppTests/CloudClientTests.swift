import XCTest
import Foundation
@testable import Steady

private final class OfflineRegressionProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var offline = false
    private static var profileSharing: Bool?
    static func setOffline(_ value: Bool) { lock.lock(); defer { lock.unlock() }; offline = value }
    static func setProfileSharing(_ value: Bool?) { lock.lock(); defer { lock.unlock() }; profileSharing = value }
    private static func isOffline() -> Bool { lock.lock(); defer { lock.unlock() }; return offline }
    private static func sharing() -> Bool? { lock.lock(); defer { lock.unlock() }; return profileSharing }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard !Self.isOffline() else { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
        let circle = "00000000-0000-4000-8000-000000000001"
        let invitedCircle = "00000000-0000-4000-8000-000000000004"
        let user = Self.returningSurvivorID
        let payload: Any
        switch request.url?.path {
        case "/auth/v1/token", "/auth/v1/signup":
            let body = try? JSONDecoder().decode([String: String].self, from: requestBody())
            let address = body?["email"] ?? ""
            let isNew = request.url?.path == "/auth/v1/signup" || address == "new@example.test"
            payload = ["access_token": isNew ? "new-test-token" : "returning-test-token", "refresh_token": "test-refresh-token",
                       "expires_at": Date().timeIntervalSince1970 + 3600,
                       "user": ["id": isNew ? Self.newSurvivorID : user, "email": address, "user_metadata": ["steady_role": "survivor"]]] as [String: Any]
        case "/auth/v1/logout": payload = NSNull()
        case "/rest/v1/survivor_profiles":
            let isReturning = request.url?.query?.lowercased().contains(user.lowercased()) == true &&
                request.value(forHTTPHeaderField: "Authorization") == "Bearer returning-test-token"
            payload = isReturning ? [["display_name": "Fictional Alex", "injury_description": "", "injury_notes": "", "symptoms": [Any]()]] as [[String: Any]] : []
        case "/rest/v1/circles" where request.value(forHTTPHeaderField: "Authorization") == "Bearer new-test-token": payload = [Any]()
        case "/rest/v1/circles": payload = [
            ["id": circle, "name": "Fictional circle", "owner_id": user],
            ["id": invitedCircle, "name": "Another fictional circle", "owner_id": user]
        ]
        case "/rest/v1/rpc/accept_invite": payload = invitedCircle
        case "/rest/v1/rpc/my_role": payload = Self.sharing() == nil ? "survivor" : "caregiver"
        case "/rest/v1/rpc/my_permissions": payload = [["kind": "symptoms", "can_read": true, "can_add": true, "can_edit": true, "can_delete": true]] as [[String: Any]]
        case "/rest/v1/records": payload = [["id": "00000000-0000-4000-8000-000000000003", "circle_id": circle, "kind": "symptoms", "author_id": user, "title": "Fictional symptom", "body": "Fictional test only", "created_at": "2026-10-28T12:00:00Z", "updated_at": "2026-10-28T12:00:00Z"]]
        case "/rest/v1/circle_members":
            if let shared = Self.sharing() {
                payload = [["user_id": user, "role": "caregiver", "shares_survivor_profile": shared]] as [[String: Any]]
            } else { payload = [Any]() }
        case "/rest/v1/rpc/shared_survivor_profile":
            payload = [["injury_description": "Fictional injury", "injury_notes": "", "symptoms": [
                ["id": "00000000-0000-4000-8000-000000000005", "category": "balance", "name": "Dizziness"],
                ["id": "00000000-0000-4000-8000-000000000006", "category": "physical", "name": "Headache"]
            ]]] as [[String: Any]]
        case "/rest/v1/check_ins", "/rest/v1/circle_permissions", "/rest/v1/circle_invitations": payload = [Any]()
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

    private func requestBody() -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 512)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { return data }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    static let returningSurvivorID = "00000000-0000-4000-8000-000000000002"
    static let newSurvivorID = "00000000-0000-4000-8000-000000000007"
}

final class CloudClientTests: XCTestCase {
    @MainActor func testSignOutAndSwitchingSurvivorsReadsEachAccountsOwnSetup() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineRegressionProtocol.self]
        let network = URLSession(configuration: configuration)
        defer { network.invalidateAndCancel() }
        let config = BackendConfig(url: URL(string: "https://\(UUID().uuidString).invalid")!, key: "sb_publishable_TEST_PLACEHOLDER")
        let client = CloudClient(config: config, network: network)

        try await client.signIn(email: "returning@example.test", password: "fictional-password")
        let firstProfile = try await client.loadSurvivorProfile()
        XCTAssertEqual(firstProfile?.display_name, "Fictional Alex")
        XCTAssertFalse(client.records.isEmpty)

        await client.signOut()
        XCTAssertNil(client.session)
        XCTAssertNil(client.circleID)
        XCTAssertTrue(client.records.isEmpty)
        XCTAssertNil(CloudClient(config: config, network: network).session)

        try await client.signUp(email: "new@example.test", password: "fictional-password", role: .survivor)
        XCTAssertEqual(client.session?.user.id.uuidString, OfflineRegressionProtocol.newSurvivorID)
        let restoredClient = CloudClient(config: config, network: network)
        XCTAssertEqual(restoredClient.session?.user.id, client.session?.user.id)
        let newProfile = try await client.loadSurvivorProfile()
        XCTAssertNil(newProfile)
        XCTAssertTrue(client.circles.isEmpty)

        await client.signOut()
        try await client.signIn(email: "returning@example.test", password: "fictional-password")
        let returningProfile = try await client.loadSurvivorProfile()
        XCTAssertEqual(returningProfile, firstProfile)
        await client.signOut()
    }

    func testAccountRoleDecodesWithExistingAndNewSessions() throws {
        let decoder = JSONDecoder()
        let account = """
        {"id":"00000000-0000-4000-8000-000000000002","email":"fictional@example.test"}
        """
        let legacy = try decoder.decode(CloudUser.self, from: Data(account.utf8))
        XCTAssertNil(legacy.profileRole)
        for role in ["survivor", "clinician", "physician", "caregiver"] {
            let json = """
            {"id":"\(legacy.id)","user_metadata":{"steady_role":"\(role)","email_verified":true}}
            """
            XCTAssertEqual(try decoder.decode(CloudUser.self, from: Data(json.utf8)).profileRole?.rawValue, role)
        }
        let invalid = """
        {"id":"\(legacy.id)","user_metadata":{"steady_role":42}}
        """
        XCTAssertNil(try decoder.decode(CloudUser.self, from: Data(invalid.utf8)).profileRole)
    }

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
        XCTAssertNil(client.circleID)
        XCTAssertEqual(client.session?.user.id, session.user.id, "Network failure must not erase the account session")
        OfflineRegressionProtocol.setOffline(false)
        try await client.loadCircles()
        XCTAssertEqual(client.records.count, 1, "Refresh can recover when the connection returns")
        try await client.accept("fictional invitation")
        XCTAssertEqual(client.circleID?.uuidString, "00000000-0000-4000-8000-000000000004",
                       "Joining another circle selects it immediately")
    }

    @MainActor func testRefreshClearsRevokedProfileWhileKeepingCircleAccess() async throws {
        OfflineRegressionProtocol.setProfileSharing(true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineRegressionProtocol.self]
        let network = URLSession(configuration: configuration)
        defer { network.invalidateAndCancel(); OfflineRegressionProtocol.setProfileSharing(nil) }
        let session = CloudSession(access_token: "fictional-access-token", refresh_token: "fictional-refresh-token",
            expires_at: Date().timeIntervalSince1970 + 3600,
            user: CloudUser(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, email: "fictional@example.test"))
        let client = CloudClient(config: BackendConfig(url: URL(string: "https://fictional.invalid")!, key: "sb_publishable_TEST_PLACEHOLDER"), network: network, initialSession: session)
        try await client.loadCircles()
        XCTAssertEqual(client.sharedSurvivorProfile?.symptoms.map(\.name), ["Dizziness", "Headache"])
        OfflineRegressionProtocol.setProfileSharing(false)
        try await client.refresh()
        XCTAssertNil(client.sharedSurvivorProfile)
        XCTAssertEqual(client.role, "caregiver")
        XCTAssertEqual(client.records.count, 1)
        OfflineRegressionProtocol.setProfileSharing(true)
        try await client.refresh()
        XCTAssertNotNil(client.sharedSurvivorProfile)
        client.clearVisibleData()
        XCTAssertNil(client.sharedSurvivorProfile)
    }

    func testCareTeamCodesAreRecognisedAndOldAndNewRowsDecode() throws {
        XCTAssertTrue(InviteCode.isShortCode("K7QF-29MD"))
        XCTAssertTrue(InviteCode.isShortCode(" k7qf 29md "))
        XCTAssertEqual(InviteCode.normalized("k7qf-29 md"), "K7QF29MD")
        XCTAssertFalse(InviteCode.isShortCode("K7QF-29M0"), "0 is not in the alphabet")
        XCTAssertFalse(InviteCode.isShortCode("K7QF-29M"), "too short")
        XCTAssertFalse(InviteCode.isShortCode(UUID().uuidString + UUID().uuidString), "old long codes use the email path")

        let oldInvite = Data(#"{"id":"\#(UUID())","recipient_email":"a@example.com","recipient_user_id":null,"role":"caregiver","expires_at":"2026-11-27T00:00:00Z","accepted_at":null,"revoked_at":null}"#.utf8)
        let decodedOld = try JSONDecoder().decode(CloudInvitation.self, from: oldInvite)
        XCTAssertEqual(decodedOld.recipient_email, "a@example.com"); XCTAssertNil(decodedOld.is_code)
        let codeInvite = Data(#"{"id":"\#(UUID())","recipient_email":null,"recipient_user_id":null,"role":"physician","expires_at":"2026-11-23T00:00:00Z","accepted_at":null,"revoked_at":null,"recipient_name":"Dr. Lee","recipient_details":"Neurologist","is_code":true}"#.utf8)
        let decodedCode = try JSONDecoder().decode(CloudInvitation.self, from: codeInvite)
        XCTAssertNil(decodedCode.recipient_email); XCTAssertEqual(decodedCode.recipient_details, "Neurologist"); XCTAssertEqual(decodedCode.is_code, true)

        let oldMember = try JSONDecoder().decode(CloudMember.self, from: Data(#"{"user_id":"\#(UUID())","role":"caregiver","shares_survivor_profile":false}"#.utf8))
        XCTAssertNil(oldMember.display_name)
        let newMember = try JSONDecoder().decode(CloudMember.self, from: Data(#"{"user_id":"\#(UUID())","role":"caregiver","shares_survivor_profile":false,"display_name":"Sam","details":"Sibling"}"#.utf8))
        XCTAssertEqual(newMember.display_name, "Sam"); XCTAssertEqual(newMember.details, "Sibling")
        XCTAssertEqual(CareTeamDetail.label(for: .physician), "Kind of doctor")
        XCTAssertEqual(CareTeamDetail.label(for: .caregiver), "Relationship")
        XCTAssertTrue(CareTeamDetail.options(for: .caregiver).contains(CareTeamDetail.other))
    }
}
