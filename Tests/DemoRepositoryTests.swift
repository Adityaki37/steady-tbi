import XCTest
@testable import SteadyCore

private final class MemoryPersistence: DemoPersistence {
    var data: Data?
    var fail = false
    func load() throws -> Data? { data }
    func save(_ data: Data) throws {
        if fail { throw DemoError.invalid("Simulated disk failure") }
        self.data = data
    }
}

final class DemoRepositoryTests: XCTestCase {
    @MainActor func testPrivateActivityPersistenceAndRetry() async throws {
        let memory = MemoryPersistence()
        let original = try DemoRepository(persistence: memory)
        let repository = try DemoRepository(persistence: memory)
        XCTAssertTrue(try repository.activityEntries(.survivor).isEmpty)
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let entry = ActivityEntry(activity: "Reading", startedAt: start, durationMinutes: 25, fatigue: 3, symptoms: "Headache")
        XCTAssertThrowsError(try repository.saveActivity(.caregiver, entry, editing: false))
        XCTAssertThrowsError(try repository.activityEntries(.clinician))
        try repository.saveActivity(.survivor, entry, editing: false)
        try repository.saveActivity(.survivor, entry, editing: false)
        let reopened = try DemoRepository(persistence: memory)
        XCTAssertEqual(try reopened.activityEntries(.survivor), [entry])
        XCTAssertEqual(try reopened.records(.survivor, .symptoms), try original.records(.survivor, .symptoms))
        let updated = ActivityEntry(id: entry.id, activity: "Reading", startedAt: start, durationMinutes: 30, fatigue: 0, symptoms: "")
        memory.fail = true
        XCTAssertThrowsError(try reopened.saveActivity(.survivor, updated, editing: true))
        XCTAssertEqual(try reopened.activityEntries(.survivor), [entry])
        memory.fail = false
        try reopened.saveActivity(.survivor, updated, editing: true)
        XCTAssertEqual(try reopened.activityEntries(.survivor), [updated])
        try reopened.deleteActivity(.survivor, entry.id)
        XCTAssertThrowsError(try reopened.saveActivity(.survivor, updated, editing: true))
        XCTAssertTrue(try DemoRepository(persistence: memory).activityEntries(.survivor).isEmpty)
    }

    @MainActor func testEveryPermissionCombination() async throws {
        var combinations = 0
        for role in [DemoRole.caregiver, .clinician] {
            for kind in RecordKind.allCases {
                for bits in 0..<16 {
                    let repository = try DemoRepository(persistence: MemoryPersistence())
                    for (index, action) in DemoAction.allCases.enumerated() {
                        try repository.setGrant(actor: .survivor, target: role, kind: kind, action: action, value: bits & (1 << index) != 0)
                    }
                    let read = bits & 1 != 0, add = bits & 2 != 0
                    let edit = read && bits & 4 != 0, delete = read && bits & 8 != 0
                    XCTAssertEqual(repository.can(role, kind, .read), read)
                    XCTAssertEqual(repository.can(role, kind, .add), add)
                    XCTAssertEqual(repository.can(role, kind, .edit), edit)
                    XCTAssertEqual(repository.can(role, kind, .delete), delete)
                    let seed = try XCTUnwrap(repository.records(.survivor, kind).first)
                    if read { XCTAssertFalse(try repository.records(role, kind).isEmpty) }
                    else {
                        XCTAssertThrowsError(try repository.records(role, kind))
                        XCTAssertThrowsError(try repository.record(role, kind, seed.id))
                    }
                    let file = kind == .attachments ? DemoAttachment(filename: "fictional.png", displayName: "fictional.png", isBundledSample: false) : nil
                    if add { try repository.add(role, kind, title: "Fictional contribution", body: "Made up.", attachment: file) }
                    else { XCTAssertThrowsError(try repository.add(role, kind, title: "Denied", body: "", attachment: file)) }
                    if edit { try repository.edit(role, kind, seed.id, title: "Fictional update", body: "Edited.") }
                    else { XCTAssertThrowsError(try repository.edit(role, kind, seed.id, title: "Denied", body: "")) }
                    if delete { try repository.delete(role, kind, seed.id) }
                    else { XCTAssertThrowsError(try repository.delete(role, kind, seed.id)) }
                    combinations += 1
                }
            }
        }
        XCTAssertEqual(combinations, 128)
    }

    @MainActor func testCaregiverContributesWithNoHistoryRead() async throws {
        let repository = try DemoRepository(persistence: MemoryPersistence())
        for kind in RecordKind.allCases { try repository.setGrant(actor: .survivor, target: .caregiver, kind: kind, action: .read, value: false) }
        try repository.add(.caregiver, .observations, title: "Fictional observation", body: "Alex asked for quiet.")
        for kind in RecordKind.allCases { XCTAssertThrowsError(try repository.records(.caregiver, kind)) }
        XCTAssertEqual(try repository.records(.survivor, .observations).count, 2)
        XCTAssertThrowsError(try repository.add(.caregiver, .notes, title: "Denied", body: ""))
    }

    @MainActor func testOnlySurvivorControlsPermissionsAndReset() async throws {
        let memory = MemoryPersistence()
        let repository = try DemoRepository(persistence: memory)
        for role in [DemoRole.caregiver, .clinician] {
            XCTAssertThrowsError(try repository.grants(role))
            XCTAssertThrowsError(try repository.setGrant(actor: role, target: .caregiver, kind: .symptoms, action: .read, value: true))
            XCTAssertThrowsError(try repository.reset(role))
            XCTAssertThrowsError(try DemoRepository.explicitlyResetSavedData(memory, actor: role))
        }
        XCTAssertThrowsError(try repository.setGrant(actor: .survivor, target: .survivor, kind: .symptoms, action: .read, value: false))
        var copy = try repository.records(.survivor, .symptoms); copy[0].title = "Changed copy"
        XCTAssertNotEqual(try repository.records(.survivor, .symptoms)[0].title, "Changed copy")
    }

    @MainActor func testDiskPersistenceAndReset() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SteadyTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let disk = DiskPersistence(url: folder.appendingPathComponent("state.json"))
        let repository = try DemoRepository(persistence: disk)
        try repository.add(.survivor, .symptoms, title: "Fictional test", body: "", severity: 4)
        try repository.setGrant(actor: .survivor, target: .caregiver, kind: .symptoms, action: .read, value: true)
        try repository.requestCheckIn(.caregiver)
        let reopened = try DemoRepository(persistence: disk)
        XCTAssertEqual(try reopened.records(.caregiver, .symptoms).count, 3)
        XCTAssertNotNil(try reopened.checkIn(.survivor))
        try reopened.dismissCheckIn(.survivor)
        XCTAssertNil(try reopened.checkIn(.survivor))
        try reopened.reset(.survivor)
        let reset = try DemoRepository(persistence: disk)
        XCTAssertEqual(try reset.records(.survivor, .symptoms).count, 2)
        XCTAssertFalse(reset.can(.caregiver, .symptoms, .read))
        XCTAssertNil(try reset.checkIn(.survivor))
    }

    @MainActor func testDiskFailureRollsBack() async throws {
        let memory = MemoryPersistence(); let repository = try DemoRepository(persistence: memory)
        memory.fail = true
        XCTAssertThrowsError(try repository.add(.survivor, .symptoms, title: "Will fail", body: ""))
        XCTAssertEqual(try repository.records(.survivor, .symptoms).count, 2)
        XCTAssertThrowsError(try repository.setGrant(actor: .survivor, target: .caregiver, kind: .symptoms, action: .read, value: true))
        XCTAssertFalse(repository.can(.caregiver, .symptoms, .read))
        memory.fail = false
        try repository.add(.survivor, .symptoms, title: "Recovery", body: "")
        XCTAssertEqual(try repository.records(.survivor, .symptoms).count, 3)
    }

    @MainActor func testValidationAndCorruptDataRecovery() async throws {
        let memory = MemoryPersistence(); let repository = try DemoRepository(persistence: memory)
        XCTAssertThrowsError(try repository.add(.survivor, .symptoms, title: "", body: ""))
        XCTAssertThrowsError(try repository.add(.survivor, .symptoms, title: "Invalid", body: "", severity: 6))
        XCTAssertThrowsError(try repository.add(.survivor, .notes, title: "Invalid", body: "", severity: 2))
        XCTAssertThrowsError(try repository.add(.survivor, .attachments, title: "Bad path", body: "", attachment: DemoAttachment(filename: "../secret.png", displayName: "secret", isBundledSample: false)))
        memory.data = Data("{bad".utf8)
        XCTAssertThrowsError(try DemoRepository(persistence: memory))
        XCTAssertEqual(memory.data, Data("{bad".utf8), "Corrupt data must not be replaced silently")
        try DemoRepository.explicitlyResetSavedData(memory, actor: .survivor)
        XCTAssertEqual(try DemoRepository(persistence: memory).records(.survivor, .symptoms).count, 2)
    }

    @MainActor func testCheckInRoleRestrictions() async throws {
        let repository = try DemoRepository(persistence: MemoryPersistence())
        XCTAssertThrowsError(try repository.requestCheckIn(.survivor))
        XCTAssertThrowsError(try repository.requestCheckIn(.clinician))
        XCTAssertThrowsError(try repository.checkIn(.caregiver))
        XCTAssertThrowsError(try repository.dismissCheckIn(.clinician))
        try repository.requestCheckIn(.caregiver)
        let general = try XCTUnwrap(try repository.checkIn(.survivor))
        XCTAssertFalse(general.lowercased().contains("possible symptom"))
        // The symptom-break variant stays caregiver-only and carries the calm,
        // non-diagnostic wording mirrored by the account mode and the local notification.
        XCTAssertThrowsError(try repository.requestCheckIn(.survivor, symptomBreak: true))
        XCTAssertThrowsError(try repository.requestCheckIn(.clinician, symptomBreak: true))
        try repository.requestCheckIn(.caregiver, symptomBreak: true)
        let breakMessage = try XCTUnwrap(try repository.checkIn(.survivor))
        XCTAssertTrue(breakMessage.lowercased().contains("possible symptom"))
        XCTAssertTrue(breakMessage.lowercased().contains("break"))
        XCTAssertTrue(breakMessage.lowercased().contains("not a diagnosis"))
    }
}
