import Foundation

public enum DemoRole: String, Codable, CaseIterable, Identifiable, Hashable {
    case survivor, caregiver, clinician
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public var contribution: RecordKind {
        switch self { case .survivor: return .symptoms; case .caregiver: return .observations; case .clinician: return .notes }
    }
}

public enum RecordKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case symptoms, observations, notes, attachments
    public var id: String { rawValue }
    public var title: String {
        switch self { case .symptoms: return "Symptoms"; case .observations: return "Observations"; case .notes: return "Clinician notes"; case .attachments: return "Files" }
    }
    public var symbol: String {
        switch self { case .symptoms: return "heart.text.square"; case .observations: return "person.2"; case .notes: return "note.text"; case .attachments: return "doc" }
    }
}

public enum DemoAction: String, Codable, CaseIterable, Identifiable, Hashable {
    case read, add, edit, delete
    public var id: String { rawValue }
}

public struct Grant: Codable, Equatable {
    public var read: Bool; public var add: Bool; public var edit: Bool; public var delete: Bool
    public static let all = Grant(read: true, add: true, edit: true, delete: true)
    public static let none = Grant(read: false, add: false, edit: false, delete: false)
    public subscript(_ action: DemoAction) -> Bool {
        get { switch action { case .read: return read; case .add: return add; case .edit: return edit; case .delete: return delete } }
        set { switch action { case .read: read = newValue; case .add: add = newValue; case .edit: edit = newValue; case .delete: delete = newValue } }
    }
}

public struct DemoAttachment: Codable, Equatable {
    // A managed basename, never an arbitrary path. The fictional sample is bundled.
    public let filename: String
    public let displayName: String
    public let isBundledSample: Bool
    public init(filename: String, displayName: String, isBundledSample: Bool) {
        self.filename = filename; self.displayName = displayName; self.isBundledSample = isBundledSample
    }
}

public struct DemoRecord: Codable, Identifiable, Equatable {
    public let id: UUID
    public let kind: RecordKind
    public let author: DemoRole
    public var title: String
    public var body: String
    public var severity: Int?
    public let createdAt: Date
    public var updatedAt: Date
    public let attachment: DemoAttachment?
}

public enum DemoError: LocalizedError {
    case denied, missing, invalid(String), unavailable
    public var errorDescription: String? {
        switch self {
        case .denied: return "This demo role does not have permission for that action."
        case .missing: return "That entry is no longer available."
        case .invalid(let message): return message
        case .unavailable: return "Saved demo data could not be opened. Reset explicitly to start again."
        }
    }
}

public protocol DemoPersistence {
    func load() throws -> Data?
    func save(_ data: Data) throws
}

public final class DiskPersistence: DemoPersistence {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
    public func save(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}

private struct DemoState: Codable {
    var version = 1
    var permissions: [DemoRole: [RecordKind: Grant]]
    var records: [DemoRecord]
    var checkIn: String?

    static func seed() -> DemoState {
        var permissions = Dictionary(uniqueKeysWithValues: DemoRole.allCases.map { role in
            (role, Dictionary(uniqueKeysWithValues: RecordKind.allCases.map { ($0, role == .survivor ? Grant.all : Grant.none) }))
        })
        permissions[.caregiver]?[.observations] = .all
        permissions[.clinician]?[.symptoms]?.read = true
        permissions[.clinician]?[.observations]?.read = true
        permissions[.clinician]?[.attachments]?.read = true
        permissions[.clinician]?[.notes] = .all
        let day = Date(timeIntervalSince1970: 1793113200)
        func record(_ kind: RecordKind, _ author: DemoRole, _ title: String, _ body: String, severity: Int? = nil, file: DemoAttachment? = nil) -> DemoRecord {
            DemoRecord(id: UUID(), kind: kind, author: author, title: title, body: body, severity: severity,
                       createdAt: day, updatedAt: day, attachment: file)
        }
        return DemoState(permissions: permissions, records: [
            record(.symptoms, .survivor, "Noise felt tiring", "Fictional example: a busy cafe felt overwhelming. A quiet room felt more comfortable afterward.", severity: 3),
            record(.symptoms, .survivor, "Screen fatigue", "Fictional example: I noticed tired eyes while reading. I logged it to talk about at my next visit.", severity: 2),
            record(.observations, .caregiver, "A quieter afternoon", "Fictional observation: Alex asked to lower the music and chose to rest."),
            record(.notes, .clinician, "Topics for the next visit", "Fictional note: ask which daily environments feel difficult and review the symptom log together. No diagnosis or treatment advice is provided."),
            record(.attachments, .survivor, "Fictional brain MRI illustration", "Synthetic illustration for testing file preview. Not a patient scan, not diagnostic, and not interpreted by this app.",
                   file: DemoAttachment(filename: "Fictional-brain-MRI.png", displayName: "Fictional-brain-MRI.png", isBundledSample: true))
        ])
    }

    func validate() throws {
        guard version == 1 else { throw DemoError.invalid("Unsupported saved demo version.") }
        for role in DemoRole.allCases { for kind in RecordKind.allCases {
            guard let grant = permissions[role]?[kind] else { throw DemoError.invalid("Saved permissions are incomplete.") }
            if role == .survivor && grant != .all { throw DemoError.invalid("The survivor must retain control.") }
        } }
        guard Set(records.map(\.id)).count == records.count else { throw DemoError.invalid("Saved entries have duplicate identifiers.") }
        for record in records { try Self.validate(record) }
    }

    static func validate(_ record: DemoRecord) throws {
        guard !record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, record.title.count <= 100, record.body.count <= 3000 else {
            throw DemoError.invalid("Use a title of 1–100 characters and a note of up to 3,000 characters.")
        }
        if let severity = record.severity, !(1...5).contains(severity) { throw DemoError.invalid("Choose a severity from 1 to 5.") }
        if record.kind != .symptoms && record.severity != nil { throw DemoError.invalid("Only symptoms have a severity rating.") }
        guard (record.kind == .attachments) == (record.attachment != nil) else { throw DemoError.invalid("Attachment details do not match the entry type.") }
        if let file = record.attachment {
            let path = file.filename as NSString
            guard path.lastPathComponent == file.filename, !file.filename.contains("\\"), !file.filename.contains(".."),
                  ["pdf", "png", "jpg", "jpeg"].contains(path.pathExtension.lowercased()), !file.displayName.isEmpty else {
                throw DemoError.invalid("Use a local PDF, PNG or JPEG attachment.")
            }
            if file.isBundledSample && file.filename != "Fictional-brain-MRI.png" { throw DemoError.invalid("Unknown bundled sample.") }
        }
    }
}

// All reads and mutations enter here. UI hiding is not the permission boundary.
// This role parameter is a demo identity, not authenticated production identity.
@MainActor public final class DemoRepository {
    private var state: DemoState
    private let persistence: DemoPersistence
    private let now: () -> Date
    public init(persistence: DemoPersistence, now: @escaping () -> Date = Date.init) throws {
        self.persistence = persistence; self.now = now
        if let data = try persistence.load() {
            let loaded = try JSONDecoder().decode(DemoState.self, from: data)
            try loaded.validate(); state = loaded
        } else {
            let seeded = DemoState.seed(); try seeded.validate()
            try persistence.save(JSONEncoder().encode(seeded)); state = seeded
        }
    }

    public func can(_ role: DemoRole, _ kind: RecordKind, _ action: DemoAction) -> Bool {
        guard let grant = state.permissions[role]?[kind], grant[action] else { return false }
        return (action != .edit && action != .delete) || grant.read
    }
    private func require(_ role: DemoRole, _ kind: RecordKind, _ action: DemoAction) throws {
        guard can(role, kind, action) else { throw DemoError.denied }
    }
    private func commit(_ next: DemoState) throws {
        try next.validate()
        // Save first: failed disk writes never become a successful UI mutation.
        try persistence.save(JSONEncoder().encode(next)); state = next
    }
    public func records(_ role: DemoRole, _ kind: RecordKind) throws -> [DemoRecord] {
        try require(role, kind, .read)
        return state.records.filter { $0.kind == kind }.sorted { $0.createdAt > $1.createdAt }
    }
    public func record(_ role: DemoRole, _ kind: RecordKind, _ id: UUID) throws -> DemoRecord {
        try require(role, kind, .read)
        guard let found = state.records.first(where: { $0.id == id && $0.kind == kind }) else { throw DemoError.missing }
        return found
    }
    public func grants(_ role: DemoRole) throws -> [DemoRole: [RecordKind: Grant]] {
        guard role == .survivor else { throw DemoError.denied }; return state.permissions
    }
    public func setGrant(actor: DemoRole, target: DemoRole, kind: RecordKind, action: DemoAction, value: Bool) throws {
        guard actor == .survivor, target != .survivor else { throw DemoError.denied }
        var next = state; next.permissions[target]?[kind]?[action] = value; try commit(next)
    }
    public func add(_ role: DemoRole, _ kind: RecordKind, title: String, body: String, severity: Int? = nil, attachment: DemoAttachment? = nil) throws {
        try require(role, kind, .add)
        let date = now()
        let record = DemoRecord(id: UUID(), kind: kind, author: role, title: title, body: body, severity: severity, createdAt: date, updatedAt: date, attachment: attachment)
        try DemoState.validate(record); var next = state; next.records.insert(record, at: 0); try commit(next)
    }
    public func edit(_ role: DemoRole, _ kind: RecordKind, _ id: UUID, title: String, body: String, severity: Int? = nil) throws {
        try require(role, kind, .edit)
        guard let index = state.records.firstIndex(where: { $0.id == id && $0.kind == kind }) else { throw DemoError.missing }
        var next = state; next.records[index].title = title; next.records[index].body = body
        next.records[index].severity = severity; next.records[index].updatedAt = now(); try commit(next)
    }
    @discardableResult public func delete(_ role: DemoRole, _ kind: RecordKind, _ id: UUID) throws -> DemoAttachment? {
        try require(role, kind, .delete)
        guard let index = state.records.firstIndex(where: { $0.id == id && $0.kind == kind }) else { throw DemoError.missing }
        var next = state; let deleted = next.records.remove(at: index); try commit(next); return deleted.attachment
    }
    public func requestCheckIn(_ role: DemoRole, symptomBreak: Bool = false) throws {
        guard role == .caregiver else { throw DemoError.denied }
        var next = state
        next.checkIn = symptomBreak
            ? "Your demo caregiver noticed a possible symptom and suggests taking a break. This is a supportive prompt, not a diagnosis."
            : "Your demo caregiver suggested a check-in. You can log how you feel or choose a quiet break."
        try commit(next)
    }
    public func checkIn(_ role: DemoRole) throws -> String? {
        guard role == .survivor else { throw DemoError.denied }; return state.checkIn
    }
    public func dismissCheckIn(_ role: DemoRole) throws {
        guard role == .survivor else { throw DemoError.denied }; var next = state; next.checkIn = nil; try commit(next)
    }
    public func reset(_ role: DemoRole) throws { guard role == .survivor else { throw DemoError.denied }; try commit(.seed()) }
    public static func explicitlyResetSavedData(_ persistence: DemoPersistence, actor: DemoRole) throws {
        guard actor == .survivor else { throw DemoError.denied }
        try persistence.save(JSONEncoder().encode(DemoState.seed()))
    }
}
