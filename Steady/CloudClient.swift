import Foundation
import SwiftUI
import Security
import SteadyCore

struct BackendConfig {
    let url: URL
    let key: String
    static func load() -> BackendConfig? {
        guard let file = Bundle.main.url(forResource: "Backend.local", withExtension: "plist", subdirectory: "Resources"),
              let data = try? Data(contentsOf: file),
              let dictionary = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              let value = dictionary["SUPABASE_URL"], let url = URL(string: value), url.scheme == "https", url.host != nil,
              let key = dictionary["SUPABASE_PUBLISHABLE_KEY"], key.hasPrefix("sb_publishable_") else { return nil }
        return BackendConfig(url: url, key: key)
    }
}
struct CloudUser: Codable { let id: UUID; let email: String? }
struct CloudSession: Codable {
    let access_token: String; let refresh_token: String; let expires_at: TimeInterval; let user: CloudUser
}
struct CloudCircle: Codable, Identifiable, Hashable { let id: UUID; let name: String; let owner_id: UUID }
struct CloudPermission: Codable, Identifiable {
    let kind: String; var can_read: Bool; var can_add: Bool; var can_edit: Bool; var can_delete: Bool
    var id: String { kind }
    func allows(_ action: DemoAction) -> Bool {
        switch action { case .read: return can_read; case .add: return can_add; case .edit: return can_read && can_edit; case .delete: return can_read && can_delete }
    }
}
struct CloudRecord: Codable, Identifiable {
    let id: UUID; let circle_id: UUID; let kind: String; let author_id: UUID
    let title: String; let body: String; let severity: Int?; let file_path: String?; let file_name: String?
    let created_at: String; let updated_at: String
}
struct CloudCheckIn: Codable, Identifiable { let id: UUID; let body: String; let created_at: String }
struct CloudMember: Codable, Identifiable { let user_id: UUID; let role: String; var id: UUID { user_id } }
struct CloudInvitation: Codable, Identifiable { let id: UUID; let recipient_email: String; let role: String; let expires_at: String; let accepted_at: String?; let revoked_at: String? }
struct RoleGrant: Codable, Identifiable {
    let role: String; let kind: String; var can_read: Bool; var can_add: Bool; var can_edit: Bool; var can_delete: Bool
    var id: String { role + kind }
    subscript(_ action: DemoAction) -> Bool {
        get { switch action { case .read: return can_read; case .add: return can_add; case .edit: return can_edit; case .delete: return can_delete } }
        set { switch action { case .read: can_read = newValue; case .add: can_add = newValue; case .edit: can_edit = newValue; case .delete: can_delete = newValue } }
    }
}

private enum SessionKeychain {
    static let service = "Steady.AccountSession.v1"
    static func query(_ account: String) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] }
    static func load(_ account: String) throws -> CloudSession? {
        var q = query(account); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?; let result = SecItemCopyMatching(q as CFDictionary, &value)
        if result == errSecItemNotFound { return nil }
        guard result == errSecSuccess, let data = value as? Data else { throw DemoError.invalid("Could not open the saved account session.") }
        return try JSONDecoder().decode(CloudSession.self, from: data)
    }
    static func save(_ session: CloudSession, _ account: String) throws {
        let data = try JSONEncoder().encode(session)
        let result = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecSuccess { return }
        guard result == errSecItemNotFound else { throw DemoError.invalid("Could not update the account session in Keychain.") }
        var q = query(account); q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw DemoError.invalid("Could not save the account session in Keychain.") }
    }
    static func remove(_ account: String) throws {
        let result = SecItemDelete(query(account) as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw DemoError.invalid("Could not remove the saved session from Keychain.") }
    }
}

// REST client with no service-role key and no persistent record cache. The database
// and private storage enforce authorization on every request across devices.
@MainActor final class CloudClient: ObservableObject {
    @Published private(set) var session: CloudSession?
    @Published private(set) var circles: [CloudCircle] = []
    @Published private(set) var role: String?
    @Published private(set) var permissions: [CloudPermission] = []
    @Published private(set) var records: [CloudRecord] = []
    @Published private(set) var checkIns: [CloudCheckIn] = []
    @Published private(set) var members: [CloudMember] = []
    @Published private(set) var invitations: [CloudInvitation] = []
    @Published private(set) var grants: [RoleGrant] = []
    @Published var circleID: UUID?
    @Published var message: String?
    let config = BackendConfig.load()
    private let network: URLSession
    private var refreshTask: Task<CloudSession, Error>?
    private var generation = UUID()
    private var sessionEpoch = UUID()
    private var temporaryFiles: [URL] = []
    init() {
        let configuration = URLSessionConfiguration.ephemeral; configuration.urlCache = nil; configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        network = URLSession(configuration: configuration)
        if let config {
            do { session = try SessionKeychain.load(config.url.absoluteString) }
            catch { message = error.localizedDescription }
        }
    }
    private func clearCircleData() { role = nil; permissions = []; records = []; checkIns = []; members = []; invitations = []; grants = [] }
    func clearVisibleData() {
        generation = UUID(); clearCircleData()
        for url in temporaryFiles { try? FileManager.default.removeItem(at: url) }; temporaryFiles = []
    }
    private func token() async throws -> String {
        guard let session else { throw DemoError.invalid("Sign in first.") }
        if session.expires_at > Date().timeIntervalSince1970 + 60 { return session.access_token }
        if let refreshTask { return try await refreshTask.value.access_token }
        let expected = sessionEpoch
        let task = Task { () throws -> CloudSession in
            let data = try await request("auth/v1/token?grant_type=refresh_token", method: "POST", body: ["refresh_token": session.refresh_token], authenticated: false)
            return try JSONDecoder().decode(CloudSession.self, from: data)
        }
        refreshTask = task
        defer { refreshTask = nil }
        let updated = try await task.value
        guard sessionEpoch == expected, let config else { throw CancellationError() }
        try SessionKeychain.save(updated, config.url.absoluteString); self.session = updated
        return updated.access_token
    }
    private func request(_ path: String, method: String = "GET", body: Any? = nil, authenticated: Bool = true,
                         bytes: Data? = nil, mime: String = "application/json", representation: Bool = false) async throws -> Data {
        guard let config, let url = URL(string: path, relativeTo: config.url.appendingPathComponent("/")) else { throw DemoError.invalid("Configure a new backend first.") }
        var request = URLRequest(url: url); request.httpMethod = method; request.timeoutInterval = 30
        request.setValue(config.key, forHTTPHeaderField: "apikey")
        if authenticated { request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization") }
        request.setValue(mime, forHTTPHeaderField: "Content-Type")
        request.setValue(representation ? "return=representation" : "return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try body.map { try JSONSerialization.data(withJSONObject: $0) } ?? bytes
        let (data, response) = try await network.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            let details = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw DemoError.invalid((details?["message"] as? String) ?? (details?["msg"] as? String) ?? (details?["error_description"] as? String) ?? "The backend request failed. Refresh access or sign in again.")
        }
        return data
    }
    private func rpc(_ name: String, _ body: [String: Any]) async throws -> Data { try await request("rest/v1/rpc/" + name, method: "POST", body: body) }
    func signIn(email: String, password: String, create: Bool) async throws {
        sessionEpoch = UUID()
        clearVisibleData(); circles = []; circleID = nil
        let data = try await request(create ? "auth/v1/signup" : "auth/v1/token?grant_type=password", method: "POST", body: ["email": email, "password": password], authenticated: false)
        if let value = try? JSONDecoder().decode(CloudSession.self, from: data), let config {
            try SessionKeychain.save(value, config.url.absoluteString); session = value; try await loadCircles()
        } else { message = "Check your email to confirm this test account, then sign in. No circle has been joined yet." }
    }
    func signOut() async {
        sessionEpoch = UUID()
        let credential = session?.access_token
        clearVisibleData(); refreshTask?.cancel(); refreshTask = nil; session = nil; circles = []; circleID = nil
        do { if let config { try SessionKeychain.remove(config.url.absoluteString) } }
        catch { message = error.localizedDescription }
        if let credential, let config, let url = URL(string: "auth/v1/logout?scope=local", relativeTo: config.url.appendingPathComponent("/")) {
            var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue(config.key, forHTTPHeaderField: "apikey"); request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
            _ = try? await network.data(for: request)
        }
    }
    func loadCircles() async throws {
        let expected = sessionEpoch
        let data = try await request("rest/v1/circles?select=id,name,owner_id&order=created_at")
        guard sessionEpoch == expected, session != nil else { throw CancellationError() }
        circles = try JSONDecoder().decode([CloudCircle].self, from: data)
        if circleID == nil || !circles.contains(where: { $0.id == circleID }) { circleID = circles.first?.id }
        try await refresh()
    }
    func refresh() async throws {
        guard let id = circleID else { clearVisibleData(); return }
        generation = UUID(); let expected = generation
        do {
            let roleData = try await rpc("my_role", ["c": id.uuidString])
            let assigned = try JSONDecoder().decode(String?.self, from: roleData)
            let permissionData = try await rpc("my_permissions", ["c": id.uuidString])
            let newPermissions = try JSONDecoder().decode([CloudPermission].self, from: permissionData)
            let recordData = try await request("rest/v1/records?circle_id=eq.\(id.uuidString)&order=created_at.desc&limit=200")
            let newRecords = try JSONDecoder().decode([CloudRecord].self, from: recordData)
            let checkData = try await request("rest/v1/check_ins?circle_id=eq.\(id.uuidString)&order=created_at.desc&limit=25")
            let newCheckIns = try JSONDecoder().decode([CloudCheckIn].self, from: checkData)
            guard expected == generation, circleID == id else { return }
            role = assigned; permissions = newPermissions; records = newRecords; checkIns = newCheckIns
            if assigned != "survivor" { grants = []; members = []; invitations = [] }
            if assigned == "survivor" {
                let grantData = try await request("rest/v1/circle_permissions?circle_id=eq.\(id.uuidString)&order=role,kind")
                let memberData = try await request("rest/v1/circle_members?circle_id=eq.\(id.uuidString)")
                let inviteData = try await request("rest/v1/circle_invitations?select=id,recipient_email,role,expires_at,accepted_at,revoked_at&circle_id=eq.\(id.uuidString)")
                guard expected == generation, circleID == id else { return }
                grants = try JSONDecoder().decode([RoleGrant].self, from: grantData)
                members = try JSONDecoder().decode([CloudMember].self, from: memberData)
                invitations = try JSONDecoder().decode([CloudInvitation].self, from: inviteData)
            }
        } catch { if expected == generation { clearVisibleData() }; throw error }
    }
    func can(_ kind: RecordKind, _ action: DemoAction) -> Bool { permissions.first { $0.kind == kind.rawValue }?.allows(action) == true }
    func createCircle() async throws {
        _ = try await rpc("create_circle", ["n": "Fictional Alex’s circle"]); try await loadCircles()
    }
    func invite(email: String, role: String) async throws -> String {
        guard let id = circleID else { throw DemoError.missing }
        let data = try await rpc("invite_member", ["c": id.uuidString, "email": email, "r": role])
        let token = try JSONDecoder().decode(String.self, from: data); try await refresh(); return token
    }
    func accept(_ token: String) async throws { _ = try await rpc("accept_invite", ["token": token]); try await loadCircles() }
    func revoke(_ id: UUID) async throws { _ = try await rpc("revoke_invite", ["i": id.uuidString]); try await refresh() }
    func removeMember(_ id: UUID) async throws {
        guard let circle = circleID else { throw DemoError.missing }
        _ = try await request("rest/v1/circle_members?circle_id=eq.\(circle.uuidString)&user_id=eq.\(id.uuidString)", method: "DELETE"); try await refresh()
    }
    func setGrant(_ grant: RoleGrant, action: DemoAction, value: Bool) async throws {
        guard let id = circleID else { throw DemoError.missing }
        _ = try await request("rest/v1/circle_permissions?circle_id=eq.\(id.uuidString)&role=eq.\(grant.role)&kind=eq.\(grant.kind)", method: "PATCH", body: ["can_" + action.rawValue: value]); try await refresh()
    }
    func save(kind: RecordKind, existing: CloudRecord?, title: String, body: String, severity: Int?) async throws {
        guard let id = circleID, let session else { throw DemoError.missing }
        var values: [String: Any] = ["title": title, "body": body, "severity": severity.map { $0 as Any } ?? NSNull()]
        if let existing {
            let result = try await request("rest/v1/records?id=eq.\(existing.id.uuidString)&circle_id=eq.\(id.uuidString)", method: "PATCH", body: values, representation: true)
            guard try !JSONDecoder().decode([CloudRecord].self, from: result).isEmpty else { throw DemoError.denied }
        } else {
            values["circle_id"] = id.uuidString; values["author_id"] = session.user.id.uuidString; values["kind"] = kind.rawValue
            // Minimal response is essential for add-without-read: RETURNING would require SELECT.
            _ = try await request("rest/v1/records", method: "POST", body: values)
        }
        try await refresh()
    }
    func delete(_ record: CloudRecord) async throws {
        if let path = record.file_path {
            _ = try await request("storage/v1/object/steady-fictional", method: "DELETE", body: ["prefixes": [path]])
        }
        let result = try await request("rest/v1/records?id=eq.\(record.id.uuidString)", method: "DELETE", representation: true)
        guard try !JSONDecoder().decode([CloudRecord].self, from: result).isEmpty else { throw DemoError.denied }
        try await refresh()
    }
    func checkIn() async throws {
        guard let id = circleID, let session else { throw DemoError.missing }
        _ = try await request("rest/v1/check_ins", method: "POST", body: ["circle_id": id.uuidString, "sender_id": session.user.id.uuidString, "body": "Your demo caregiver suggested a check-in or a quiet break."])
        try await refresh(); message = "Check-in saved on the server. The survivor sees it when their app refreshes. No remote iOS push is sent."
    }
    func dismissCheckIn(_ id: UUID) async throws { _ = try await request("rest/v1/check_ins?id=eq.\(id.uuidString)", method: "DELETE"); try await refresh() }
    func upload(_ source: URL) async throws {
        guard let id = circleID, let session, can(.attachments, .add) else { throw DemoError.denied }
        let accessing = source.startAccessingSecurityScopedResource(); defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        let ext = source.pathExtension.lowercased()
        guard ["png", "jpg", "jpeg", "pdf"].contains(ext) else { throw DemoError.invalid("Use a fictional PNG, JPEG or PDF.") }
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= 15 * 1024 * 1024 else { throw DemoError.invalid("Choose a file below 15 MB.") }
        let data = try Data(contentsOf: source)
        let mime = ext == "pdf" ? "application/pdf" : ext == "png" ? "image/png" : "image/jpeg"
        let path = id.uuidString.lowercased() + "/" + UUID().uuidString.lowercased() + "." + ext
        _ = try await request("storage/v1/object/steady-fictional/" + path, method: "POST", bytes: data, mime: mime)
        do {
            _ = try await request("rest/v1/records", method: "POST", body: ["circle_id": id.uuidString, "kind": "attachments", "author_id": session.user.id.uuidString,
                "title": String(source.deletingPathExtension().lastPathComponent.prefix(100)), "body": "Imported fictional attachment. No diagnostic interpretation.", "file_path": path, "file_name": source.lastPathComponent])
        } catch {
            // Add-only users may not delete an orphan; report it rather than claiming cleanup.
            throw DemoError.invalid("The file uploaded but its entry could not be saved. The survivor must remove orphan path \(path) using Storage administration. \(error.localizedDescription)")
        }
        try await refresh()
    }
    func preview(_ record: CloudRecord) async throws -> URL {
        guard let path = record.file_path else { throw DemoError.missing }
        let expected = generation
        let data = try await request("storage/v1/object/authenticated/steady-fictional/" + path)
        guard generation == expected else { throw CancellationError() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + (path as NSString).pathExtension)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen]); temporaryFiles.append(url); return url
    }
}
