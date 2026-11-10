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
        directory = support.appendingPathComponent("SteadyDemo", isDirectory: true)
        // UI tests pass -STEADY_UITEST for a fresh, deterministic fictional state on every launch.
        if ProcessInfo.processInfo.arguments.contains("-STEADY_UITEST") { try? FileManager.default.removeItem(at: directory) }
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
        guard source.isFileURL else { throw DemoError.invalid("Choose a local fictional PDF, PNG or JPEG.") }
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        let ext = source.pathExtension.lowercased()
        guard ["pdf", "png", "jpg", "jpeg"].contains(ext) else { throw DemoError.invalid("Choose a PDF, PNG or JPEG.") }
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        guard let bytes = attributes[.size] as? NSNumber, bytes.int64Value <= 15 * 1024 * 1024 else { throw DemoError.invalid("Choose a fictional file smaller than 15 MB.") }
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
                           body: "Imported fictional file. For preview only; no diagnostic interpretation.",
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
        guard FileManager.default.fileExists(atPath: url.path) else { throw DemoError.invalid("The local file is missing. Reimport a fictional copy.") }
        return url
    }
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
            catch { show("Demo reset", "Fictional entries and permissions were restored. Some imported local files could not be removed; retry reset to clean them up.") }
        }
    }
    func show(_ title: String, _ message: String) { notice = AppNotice(title: title, message: message) }
    func report(_ error: Error) { show("Could not complete action", error.localizedDescription) }
}
