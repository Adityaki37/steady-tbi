import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import SteadyCore

struct AppNotice: Identifiable { let id = UUID(); let title: String; let message: String }
struct FilePreview: Identifiable { let id = UUID(); let url: URL }

@MainActor final class AppStore: ObservableObject {
    @Published var role: DemoRole = .survivor
    @Published private(set) var revision = 0
    @Published private(set) var loadFailure: String?
    @Published var notice: AppNotice?
    private var repository: DemoRepository?
    private let directory: URL
    private let persistence: DiskPersistence
    private var filesDirectory: URL { directory.appendingPathComponent("Attachments", isDirectory: true) }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // UI tests reset a separate directory for a fresh fictional state on every launch.
        #if DEBUG
        let isUITest = ProcessInfo.processInfo.arguments.contains("-STEADY_UITEST")
        directory = support.appendingPathComponent(isUITest ? "SteadyUITestDemo" : "SteadyDemo", isDirectory: true)
        if isUITest { try? FileManager.default.removeItem(at: directory) }
        #else
        directory = support.appendingPathComponent("SteadyDemo", isDirectory: true)
        #endif
        persistence = DiskPersistence(url: directory.appendingPathComponent("demo-v1.json"))
        do {
            repository = try DemoRepository(persistence: persistence)
            var excluded = directory
            var flags = URLResourceValues(); flags.isExcludedFromBackup = true
            try excluded.setResourceValues(flags)
        } catch { loadFailure = error.localizedDescription }
    }
    private func repo() throws -> DemoRepository {
        guard let repository, loadFailure == nil else { throw DemoError.unavailable }; return repository
    }
    func can(_ kind: RecordKind, _ action: DemoAction) -> Bool { repository?.can(role, kind, action) == true && loadFailure == nil }
    func records(_ kind: RecordKind) throws -> [DemoRecord] { try repo().records(role, kind) }
    func activityEntries() throws -> [ActivityEntry] { try repo().activityEntries(role) }
    func saveActivity(_ entry: ActivityEntry, editing: Bool) throws { try repo().saveActivity(role, entry, editing: editing) }
    func deleteActivity(_ id: UUID) throws { try repo().deleteActivity(role, id) }
    func grants() throws -> [DemoRole: [RecordKind: Grant]] { try repo().grants(role) }
    func setGrant(_ target: DemoRole, _ kind: RecordKind, _ action: DemoAction, _ value: Bool) throws {
        try repo().setGrant(actor: role, target: target, kind: kind, action: action, value: value); revision += 1
    }
    func save(_ kind: RecordKind, existing: DemoRecord?, title: String, body: String, severity: Int?) throws {
        if let existing { try repo().edit(role, kind, existing.id, title: title, body: body, severity: severity) }
        else { try repo().add(role, kind, title: title, body: body, severity: severity) }
        revision += 1
    }
    func delete(_ record: DemoRecord) throws {
        let file = try repo().delete(role, record.kind, record.id); revision += 1
        if let file, !file.isBundledSample {
            do { try FileManager.default.removeItem(at: filesDirectory.appendingPathComponent(file.filename)) }
            catch { show("Entry deleted", "The entry was removed, but its local file could not be cleaned up. Reset demo to retry cleanup.") }
        }
    }
    func importFile(_ source: URL) throws {
        guard try repo().can(role, .attachments, .add) else { throw DemoError.denied }
        guard source.isFileURL else { throw DemoError.invalid("Choose a local PDF, PNG or JPEG.") }
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        let ext = source.pathExtension.lowercased()
        guard ["pdf", "png", "jpg", "jpeg"].contains(ext) else { throw DemoError.invalid("Choose a PDF, PNG or JPEG.") }
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        guard let bytes = attributes[.size] as? NSNumber, bytes.int64Value <= 15 * 1024 * 1024 else { throw DemoError.invalid("Choose a file up to 15 MB.") }
        let handle = try FileHandle(forReadingFrom: source); defer { try? handle.close() }
        let prefix = [UInt8](try handle.read(upToCount: 8) ?? Data())
        let signatureOK: Bool
        switch ext {
        case "png": signatureOK = prefix == [137, 80, 78, 71, 13, 10, 26, 10]
        case "jpg", "jpeg": signatureOK = prefix.starts(with: [255, 216, 255])
        default: signatureOK = prefix.starts(with: [37, 80, 68, 70, 45])
        }
        guard signatureOK else { throw DemoError.invalid("The file contents do not match its PDF/image extension.") }
        try FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
        let basename = UUID().uuidString + "." + ext
        let destination = filesDirectory.appendingPathComponent(basename)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: destination.path)
            try repo().add(role, .attachments, title: String(source.deletingPathExtension().lastPathComponent.prefix(100)),
                           body: "",
                           attachment: DemoAttachment(filename: basename, displayName: source.lastPathComponent, isBundledSample: false))
            revision += 1
        } catch { try? FileManager.default.removeItem(at: destination); throw error }
    }
    func preview(_ id: UUID) throws -> URL {
        // Re-read through the gate, rather than trusting a previously displayed row.
        let record = try repo().record(role, .attachments, id)
        guard let file = record.attachment else { throw DemoError.missing }
        let url: URL
        if file.isBundledSample {
            guard let sample = Bundle.main.url(forResource: "Fictional-brain-MRI", withExtension: "png", subdirectory: "SteadyResources") else { throw DemoError.missing }; url = sample
        } else { url = filesDirectory.appendingPathComponent(file.filename) }
        guard FileManager.default.fileExists(atPath: url.path) else { throw DemoError.invalid("The local file is missing. Import it again.") }
        return url
    }
    func clinicianSummary(_ period: ReportPeriod) throws -> ClinicianSummary { try repo().clinicianSummary(role, period: period) }
    /// Writes the summary PDF to a private temporary folder, replacing any earlier copy.
    func clinicianReportPDF(_ summary: ClinicianSummary) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ClinicianReport", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = summary.generatedAt.formatted(.iso8601.year().month().day())
        let url = folder.appendingPathComponent("Steady-clinician-summary-\(stamp).pdf")
        try ClinicianReportPDF.render(summary).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        return url
    }
    func feelingChecks() throws -> [FeelingCheck] { try repo().feelingChecks(role) }
    func saveFeeling(_ rating: Double) throws { try repo().saveFeeling(role, rating: rating); revision += 1 }
    func checkIn() -> String? { try? repo().checkIn(role) }
    func dismissCheckIn() throws { try repo().dismissCheckIn(role); revision += 1 }
    func requestCheckIn(withNotification: Bool, symptomBreak: Bool = false) async {
        do {
            try repo().requestCheckIn(role, symptomBreak: symptomBreak); revision += 1
            if withNotification {
                let center = UNUserNotificationCenter.current()
                let allowed = try await center.requestAuthorization(options: [.alert, .sound])
                guard allowed else {
                    show(symptomBreak ? "Prompt saved" : "Check-in saved", "Notifications are off. Switch to Survivor to see the message here. You can allow notifications in iPhone Settings."); return
                }
                let content = UNMutableNotificationContent()
                content.title = symptomBreak ? "Steady demo: consider a break" : "Steady demo check-in"
                content.body = symptomBreak
                    ? "A caregiver noticed a possible symptom and suggests taking a break. Open Steady when convenient."
                    : "A same-device demo check-in is ready. Open Steady when convenient."
                content.sound = .default
                let request = UNNotificationRequest(identifier: "steady-demo-check-in", content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
                try await center.add(request)
            }
            show(symptomBreak ? "Prompt saved" : "Check-in saved", withNotification ? "A local notification is scheduled in five seconds on this iPhone. Switch to Survivor to see the message. This is not cross-device push." : "Switch to Survivor to see the message. This is a single-device demo.")
        } catch { show("Check-in status", "The request may have been saved, but the alert could not complete: \(error.localizedDescription)") }
    }
    func reset() throws {
        guard role == .survivor else { throw DemoError.denied }
        if loadFailure != nil {
            try DemoRepository.explicitlyResetSavedData(persistence, actor: role)
            repository = try DemoRepository(persistence: persistence); loadFailure = nil
        } else { try repo().reset(role) }
        revision += 1
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["steady-demo-check-in"])
        center.removeDeliveredNotifications(withIdentifiers: ["steady-demo-check-in"])
        if FileManager.default.fileExists(atPath: filesDirectory.path) {
            do { try FileManager.default.removeItem(at: filesDirectory) }
            catch { show("Demo reset", "Sample entries and permissions were restored. Reset again to remove the remaining files.") }
        }
    }
    func show(_ title: String, _ message: String) { notice = AppNotice(title: title, message: message) }
    func report(_ error: Error) { show("Could not complete action", error.localizedDescription) }
}

/// Set when the survivor taps a feeling reminder; the root view then shows the rating screen.
@MainActor final class FeelingPrompt: ObservableObject {
    static let shared = FeelingPrompt()
    @Published var isShowing = false
    private init() {
        #if DEBUG
        // UI tests open the rating screen as if a reminder had been tapped.
        if ProcessInfo.processInfo.arguments.contains("-STEADY_UITEST_FEELING") { isShowing = true }
        #endif
    }
}

/// Three local reminders a day at random times between 9 AM and 9 PM, on this iPhone only.
/// iOS allows 64 pending local notifications, so a rolling week (21) is scheduled and topped up on open.
@MainActor final class FeelingReminders: ObservableObject {
    static let shared = FeelingReminders()
    nonisolated static let identifierPrefix = "steady-feeling-"
    static let days = 7
    private static let enabledKey = "steady.feelingReminders.enabled"
    @Published private(set) var isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
    @Published private(set) var nextReminder: Date?
    private init() {}

    /// Returns false when the survivor has notifications turned off for Steady.
    func setEnabled(_ enabled: Bool) async -> Bool {
        if enabled {
            let allowed = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
            guard allowed else { store(false); await clearPending(); return false }
        }
        store(enabled)
        if enabled { await reschedule() } else { await clearPending() }
        return true
    }

    /// Keeps about a week of reminders queued: picks a new week once less than six days remain.
    func refresh() async {
        guard isEnabled else { await clearPending(); return }
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(Self.identifierPrefix) }
        let queued = pending.compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() }
        if queued.count >= Self.days * 3 - 3 { nextReminder = queued.min(); return }
        await reschedule()
    }

    private func reschedule() async {
        await clearPending()
        var generator = SystemRandomNumberGenerator()
        let times = FeelingSchedule.times(days: Self.days, from: Date(), using: &generator)
        let center = UNUserNotificationCenter.current()
        for time in times {
            let content = UNMutableNotificationContent()
            content.title = "How are you feeling?"
            content.body = "Tap to rate how you feel right now, from 1 to 5."
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: time)
            let request = UNNotificationRequest(identifier: Self.identifierPrefix + UUID().uuidString, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            try? await center.add(request)
        }
        nextReminder = times.min()
    }

    private func clearPending() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        nextReminder = nil
    }

    private func store(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
    }
}
