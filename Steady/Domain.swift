import Foundation

public enum DemoRole: String, Codable, CaseIterable, Identifiable, Hashable {
    case survivor, clinician, physician, caregiver
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public var contribution: RecordKind {
        switch self { case .survivor: return .symptoms; case .caregiver: return .observations; case .clinician, .physician: return .notes }
    }
    public var initialJournalKind: RecordKind {
        self == .physician ? .symptoms : contribution
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

public struct ActivityEntry: Codable, Identifiable, Equatable {
    public let id: UUID
    public let activity: String
    public let startedAt: Date
    public let durationMinutes: Int
    public let fatigue: Int
    public let symptoms: String

    public init(id: UUID = UUID(), activity: String, startedAt: Date, durationMinutes: Int, fatigue: Int, symptoms: String) {
        self.id = id
        self.activity = activity.trimmingCharacters(in: .whitespacesAndNewlines)
        self.startedAt = startedAt
        self.durationMinutes = durationMinutes
        self.fatigue = fatigue
        self.symptoms = symptoms.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum CodingKeys: String, CodingKey {
        case id, activity, fatigue, symptoms
        case startedAt = "started_at"
        case durationMinutes = "duration_minutes"
    }

    public func validate() throws {
        guard !activity.isEmpty, activity.unicodeScalars.count <= 100 else {
            throw DemoError.invalid("Enter an activity name of up to 100 characters.")
        }
        guard (1...Int(Int32.max)).contains(durationMinutes) else {
            throw DemoError.invalid("Enter a positive duration in whole minutes.")
        }
        guard (0...5).contains(fatigue) else { throw DemoError.invalid("Choose a fatigue rating from 0 to 5.") }
        guard symptoms.unicodeScalars.count <= 1000 else { throw DemoError.invalid("Use up to 1,000 characters for symptoms.") }
    }
}

/// One answer to "How are you feeling?": 1 = extremely overwhelmed, 5 = perfectly fine, in steps of 0.5.
public struct FeelingCheck: Codable, Identifiable, Equatable {
    public let id: UUID
    public let rating: Double
    public let recordedAt: Date
    public init(id: UUID = UUID(), rating: Double, recordedAt: Date) {
        self.id = id; self.rating = rating; self.recordedAt = recordedAt
    }
    public static let lowest = 1.0
    public static let highest = 5.0
    public static let step = 0.5
    public static let allowedRatings: [Double] = Array(stride(from: lowest, through: highest, by: step))
    public static let lowestLabel = "Extremely overwhelmed"
    public static let highestLabel = "Perfectly fine"
    public static func format(_ rating: Double) -> String {
        rating.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(rating)) : String(format: "%.1f", rating)
    }
    public func validate() throws {
        guard Self.allowedRatings.contains(rating) else {
            throw DemoError.invalid("Choose a rating from 1 to 5 in steps of 0.5.")
        }
    }
}

/// Picks random reminder times: `perDay` per day inside a waking window, one in each equal slot,
/// so two reminders are never closer than `2 * edgeMinutes` apart. Times at or before `now` are dropped.
public enum FeelingSchedule {
    public static func times<R: RandomNumberGenerator>(
        days: Int, from now: Date, calendar: Calendar = .current,
        startHour: Int = 9, endHour: Int = 21, perDay: Int = 3, edgeMinutes: Int = 30,
        using generator: inout R
    ) -> [Date] {
        guard days > 0, perDay > 0, endHour > startHour else { return [] }
        let slotMinutes = (endHour - startHour) * 60 / perDay
        guard slotMinutes > edgeMinutes * 2 else { return [] }
        let today = calendar.startOfDay(for: now)
        var result: [Date] = []
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let windowStart = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: day) else { continue }
            for slot in 0..<perDay {
                let minute = slot * slotMinutes + Int.random(in: edgeMinutes...(slotMinutes - edgeMinutes), using: &generator)
                if let time = calendar.date(byAdding: .minute, value: minute, to: windowStart), time > now { result.append(time) }
            }
        }
        return result
    }
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
    var activities: [ActivityEntry]?
    var feelings: [FeelingCheck]?

    static let clinicalGrants: [RecordKind: Grant] = [
        .symptoms: Grant(read: true, add: false, edit: false, delete: false),
        .observations: Grant(read: true, add: false, edit: false, delete: false),
        .attachments: Grant(read: true, add: false, edit: false, delete: false),
        .notes: .all
    ]

    static func seed() -> DemoState {
        var permissions = Dictionary(uniqueKeysWithValues: DemoRole.allCases.map { role in
            (role, Dictionary(uniqueKeysWithValues: RecordKind.allCases.map { ($0, role == .survivor ? Grant.all : Grant.none) }))
        })
        permissions[.caregiver]?[.observations] = .all
        permissions[.clinician] = clinicalGrants
        permissions[.physician] = clinicalGrants
        let day = Date(timeIntervalSince1970: 1793113200)
        func record(_ kind: RecordKind, _ author: DemoRole, _ title: String, _ body: String, severity: Int? = nil, file: DemoAttachment? = nil) -> DemoRecord {
            DemoRecord(id: UUID(), kind: kind, author: author, title: title, body: body, severity: severity,
                       createdAt: day, updatedAt: day, attachment: file)
        }
        return DemoState(permissions: permissions, records: [
            record(.symptoms, .survivor, "Noise felt tiring", "A busy cafe felt overwhelming. A quiet room felt more comfortable afterward.", severity: 3),
            record(.symptoms, .survivor, "Screen fatigue", "I noticed tired eyes while reading. I logged it to talk about at my next visit.", severity: 2),
            record(.observations, .caregiver, "A quieter afternoon", "Alex asked to lower the music and chose to rest."),
            record(.notes, .clinician, "Topics for the next visit", "Ask which daily environments feel difficult and review the symptom log together."),
            record(.attachments, .survivor, "Sample brain MRI illustration", "Synthetic illustration for preview.",
                   file: DemoAttachment(filename: "Fictional-brain-MRI.png", displayName: "Sample-brain-MRI.png", isBundledSample: true))
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
        for activity in activities ?? [] { try activity.validate() }
        for feeling in feelings ?? [] { try feeling.validate() }
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

public enum ReportPeriod: String, CaseIterable, Identifiable, Hashable {
    case week, month, quarter, all
    public var id: String { rawValue }
    public var title: String {
        switch self { case .week: return "Last 7 days"; case .month: return "Last 30 days"; case .quarter: return "Last 90 days"; case .all: return "All time" }
    }
    public var days: Int? {
        switch self { case .week: return 7; case .month: return 30; case .quarter: return 90; case .all: return nil }
    }
}

public struct ReportSection: Equatable, Hashable {
    public let title: String
    public let lines: [String]
}

/// A survivor-prepared summary to bring to a clinical visit. Self-reported, not a diagnosis.
public struct ClinicianSummary: Equatable {
    public let generatedAt: Date
    public let period: ReportPeriod
    public let startDate: Date?
    public let symptoms: [DemoRecord]
    public let activities: [ActivityEntry]
    public let observations: [DemoRecord]
    public let notes: [DemoRecord]
    public let files: [DemoRecord]

    public var averageIntensity: Double? {
        let values = symptoms.compactMap(\.severity)
        return values.isEmpty ? nil : Double(values.reduce(0, +)) / Double(values.count)
    }
    public var highestIntensity: Int? { symptoms.compactMap(\.severity).max() }
    public var totalActivityMinutes: Int { activities.reduce(0) { $0 + $1.durationMinutes } }
    public var averageFatigue: Double? {
        activities.isEmpty ? nil : Double(activities.reduce(0) { $0 + $1.fatigue }) / Double(activities.count)
    }
    /// Activities with the highest fatigue (3 or more of 5), most tiring first.
    public var mostTiringActivities: [ActivityEntry] {
        Array(activities.filter { $0.fatigue >= 3 }.sorted { ($0.fatigue, $0.startedAt) > ($1.fatigue, $1.startedAt) }.prefix(3))
    }
    public var isEmpty: Bool { symptoms.isEmpty && activities.isEmpty && observations.isEmpty && notes.isEmpty && files.isEmpty }

    private static func day(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .omitted) }
    private static func one(_ value: Double) -> String { String(format: "%.1f", value) }
    private static func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }
    private static func entry(_ record: DemoRecord) -> String {
        let body = record.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(day(record.createdAt)) · \(record.title)" + (body.isEmpty ? "" : ": \(body)")
    }

    public var coverage: String {
        guard let startDate else { return "All entries up to \(Self.day(generatedAt))" }
        return "\(Self.day(startDate)) to \(Self.day(generatedAt)) (\(period.title.lowercased()))"
    }

    public var glance: [String] {
        var lines = ["\(symptoms.count) symptom \(symptoms.count == 1 ? "entry" : "entries")"]
        if let average = averageIntensity, let highest = highestIntensity {
            lines.append("Average intensity \(Self.one(average)) of 5 · highest \(highest) of 5")
        }
        lines.append("\(activities.count) \(activities.count == 1 ? "activity" : "activities") logged" +
                     (activities.isEmpty ? "" : " · \(Self.duration(totalActivityMinutes)) total"))
        if let fatigue = averageFatigue { lines.append("Average fatigue after activities \(Self.one(fatigue)) of 5") }
        lines.append("\(observations.count) caregiver \(observations.count == 1 ? "observation" : "observations") · \(notes.count) clinician \(notes.count == 1 ? "note" : "notes")")
        return lines
    }

    public var sections: [ReportSection] {
        func orNone(_ lines: [String]) -> [String] { lines.isEmpty ? ["None in this period."] : lines }
        return [
            ReportSection(title: "About this report", lines: [
                "Prepared by the survivor in Steady on \(Self.day(generatedAt)).",
                "Covers \(coverage).",
                "Everything here is self-reported or shared by the survivor's circle. Intensity and fatigue are personal 1–5 and 0–5 ratings, not medical scores. This report is not a diagnosis."
            ]),
            ReportSection(title: "At a glance", lines: glance),
            ReportSection(title: "Most tiring activities", lines: orNone(mostTiringActivities.map {
                "\($0.activity) · fatigue \($0.fatigue) of 5 · \(Self.duration($0.durationMinutes))"
            })),
            ReportSection(title: "Symptoms", lines: orNone(symptoms.map { record in
                Self.entry(record) + (record.severity.map { " (intensity \($0) of 5)" } ?? "")
            })),
            ReportSection(title: "Activities", lines: orNone(activities.map {
                "\(Self.day($0.startedAt)) · \($0.activity) · \(Self.duration($0.durationMinutes)) · fatigue \($0.fatigue) of 5" +
                ($0.symptoms.isEmpty ? "" : " · symptoms: \($0.symptoms)")
            })),
            ReportSection(title: "Caregiver observations", lines: orNone(observations.map(Self.entry))),
            ReportSection(title: "Clinician notes", lines: orNone(notes.map(Self.entry))),
            ReportSection(title: "Files on record", lines: orNone(files.map {
                "\(Self.day($0.createdAt)) · \($0.attachment?.displayName ?? $0.title)"
            }))
        ]
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
            var loaded = try JSONDecoder().decode(DemoState.self, from: data)
            if loaded.permissions[.physician] == nil {
                loaded.permissions[.physician] = DemoState.clinicalGrants
            }
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
    public func activityEntries(_ role: DemoRole) throws -> [ActivityEntry] {
        guard role == .survivor else { throw DemoError.denied }
        return (state.activities ?? []).sorted { $0.startedAt > $1.startedAt }
    }
    public func saveActivity(_ role: DemoRole, _ entry: ActivityEntry, editing: Bool) throws {
        guard role == .survivor else { throw DemoError.denied }
        try entry.validate()
        var next = state
        var activities = next.activities ?? []
        if let index = activities.firstIndex(where: { $0.id == entry.id }) {
            if !editing {
                guard activities[index] == entry else {
                    throw DemoError.invalid("This activity is already saved. Open it from your activity log to make changes.")
                }
                return
            }
            activities[index] = entry
        } else {
            guard !editing else { throw DemoError.missing }
            activities.append(entry)
        }
        next.activities = activities
        try commit(next)
    }
    public func deleteActivity(_ role: DemoRole, _ id: UUID) throws {
        guard role == .survivor else { throw DemoError.denied }
        var next = state
        next.activities?.removeAll { $0.id == id }
        try commit(next)
    }
    public func feelingChecks(_ role: DemoRole) throws -> [FeelingCheck] {
        guard role == .survivor else { throw DemoError.denied }
        return (state.feelings ?? []).sorted { $0.recordedAt > $1.recordedAt }
    }
    @discardableResult public func saveFeeling(_ role: DemoRole, rating: Double) throws -> FeelingCheck {
        guard role == .survivor else { throw DemoError.denied }
        let check = FeelingCheck(rating: rating, recordedAt: now())
        try check.validate()
        var next = state
        next.feelings = (next.feelings ?? []) + [check]
        try commit(next)
        return check
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
    /// Only the survivor builds their own summary; sharing it is their choice outside the app.
    public func clinicianSummary(_ role: DemoRole, period: ReportPeriod) throws -> ClinicianSummary {
        guard role == .survivor else { throw DemoError.denied }
        let generated = now()
        let start = period.days.map { generated.addingTimeInterval(-Double($0) * 86_400) }
        func inPeriod(_ date: Date) -> Bool { start.map { date >= $0 } ?? true }
        func list(_ kind: RecordKind) -> [DemoRecord] {
            state.records.filter { $0.kind == kind && inPeriod($0.createdAt) }.sorted { $0.createdAt > $1.createdAt }
        }
        return ClinicianSummary(
            generatedAt: generated, period: period, startDate: start,
            symptoms: list(.symptoms),
            activities: (state.activities ?? []).filter { inPeriod($0.startedAt) }.sorted { $0.startedAt > $1.startedAt },
            observations: list(.observations), notes: list(.notes), files: list(.attachments))
    }
    public func reset(_ role: DemoRole) throws { guard role == .survivor else { throw DemoError.denied }; try commit(.seed()) }
    public static func explicitlyResetSavedData(_ persistence: DemoPersistence, actor: DemoRole) throws {
        guard actor == .survivor else { throw DemoError.denied }
        try persistence.save(JSONEncoder().encode(DemoState.seed()))
    }
}
