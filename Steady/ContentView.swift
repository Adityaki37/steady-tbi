import SwiftUI
import SteadyCore
import UniformTypeIdentifiers
import PDFKit
import CoreText

enum Palette {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    // Accessible secondary text (>= 7:1 on both grouped surfaces, light and dark). Replaces .secondary.
    static let secondaryText = Color("SecondaryText")
}

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension Section where Parent == SectionHeader, Content: View, Footer == EmptyView {
    /// Section with a header in the accessible secondary color (the default header uses low-contrast .secondary).
    init(secondary title: String, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { SectionHeader(title) })
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var feelingPrompt = FeelingPrompt.shared
    @State private var previewingDemo = false
    @State private var demoTab: DemoTab = .settings

    private enum DemoTab: Hashable {
        case today, journal, files, control, settings
    }

    var body: some View {
        AccountView {
            demoTab = .settings
            previewingDemo = true
        }
        .fullScreenCover(isPresented: $previewingDemo) {
            if let error = store.loadFailure {
                NavigationStack {
                    RecoveryView(message: error)
                        .toolbar { Button("Back to sign in") { previewingDemo = false } }
                }
            } else {
                TabView(selection: $demoTab) {
                    NavigationStack { HomeView() }.tabItem { Label("Today", systemImage: "sun.max") }.tag(DemoTab.today)
                    NavigationStack { JournalView() }.tabItem { Label("Journal", systemImage: "book.closed") }.tag(DemoTab.journal)
                    NavigationStack { FilesView() }.tabItem { Label("Files", systemImage: "folder") }.tag(DemoTab.files)
                    NavigationStack { SharingView() }.tabItem { Label("Control", systemImage: "hand.raised") }.tag(DemoTab.control)
                    demoSettings.tabItem { Label("Demo settings", systemImage: "gearshape") }.tag(DemoTab.settings)
                }
                .id(store.role)
                .sheet(isPresented: feelingSheet(inDemo: true)) { FeelingRatingView() }
            }
        }
        .sheet(isPresented: feelingSheet(inDemo: false)) { FeelingRatingView() }
    }

    /// A tapped reminder shows the rating screen on top of whichever screen is visible.
    private func feelingSheet(inDemo: Bool) -> Binding<Bool> {
        Binding(get: { feelingPrompt.isShowing && previewingDemo == inDemo },
                set: { if !$0 { feelingPrompt.isShowing = false } })
    }

    private var demoSettings: some View {
        NavigationStack {
            Form {
                Section("Choose a view to preview") {
                    ForEach(DemoRole.allCases) { role in
                        Button("Preview \(role.title)") {
                            store.role = role
                            demoTab = .today
                        }
                    }
                }
                Button("Back to sign in") { previewingDemo = false }
            }
            .navigationTitle("Demo settings")
        }
    }
}

// Filled primary button with readable text in both appearances. The dark-mode
// accent is a light mint, so white text there would fall far below WCAG AA.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(scheme == .dark ? Color(red: 0.04, green: 0.13, blue: 0.11) : .white)
            .padding(.horizontal, 20).padding(.vertical, 14)
            .frame(minHeight: 44)
            .background(Color.accentColor.opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4),
                        in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { VStack(alignment: .leading, spacing: 12) { content }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 20)) }
}

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editor = false
    @State private var notify = false
    @State private var sending = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("A little awareness. At your pace.")
                    .font(.largeTitle.bold())
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                Text("Notice how you feel and leave a useful note for your circle.").foregroundStyle(Palette.secondaryText)
                Card {
                    Label("\(store.role.title) view", systemImage: store.role.contribution.symbol).font(.headline)
                    Text(roleDescription)
                    if store.can(store.role.contribution, .add) {
                        Button(contributionTitle) { editor = true }
                            .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("primaryAddButton")
                    } else { Label("Adding is off for this role", systemImage: "lock").foregroundStyle(Palette.secondaryText) }
                    if store.role == .survivor {
                        NavigationLink("Activity log") {
                            ActivityLogView(privacyNote: "Demo activities are stored on this device.",
                                            load: store.activityEntries, save: store.saveActivity, remove: store.deleteActivity)
                        }
                    }
                }
                if store.role == .survivor {
                    Card {
                        Label("How are you feeling?", systemImage: "face.smiling").font(.headline)
                        Text("Get 3 gentle reminders a day to rate how you feel, from 1 (extremely overwhelmed) to 5 (perfectly fine).")
                        NavigationLink { FeelingCheckInsView() } label: {
                            Text("Feeling check-ins").frame(maxWidth: .infinity)
                        }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("openFeelingCheckIns")
                    }
                    Card {
                        Label("For your next visit", systemImage: "doc.text").font(.headline)
                        Text("Make a short summary of your symptoms, activities and notes. Save it as a PDF or share it with your clinician.")
                        NavigationLink { ClinicianReportView() } label: {
                            Text("Clinician summary").frame(maxWidth: .infinity)
                        }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("openClinicianSummary")
                    }
                }
                if store.role == .survivor, let message = store.checkIn() {
                    Card {
                        Label("A gentle check-in", systemImage: "bell").font(.headline)
                        Text(message)
                        Button("Dismiss check-in") { do { try store.dismissCheckIn() } catch { store.report(error) } }
                    }
                }
                if store.role == .caregiver {
                    Card {
                        Label("Suggest a check-in", systemImage: "bell").font(.headline)
                        Text("Leave a gentle prompt for the survivor on this device.")
                        Toggle("Also show a local notification", isOn: $notify)
                        Text("Optional, five seconds from now. Same iPhone only; no remote push.").font(.caption).foregroundStyle(Palette.secondaryText)
                        Button(sending ? "Saving…" : "Suggest a check-in") {
                            sending = true
                            Task { await store.requestCheckIn(withNotification: notify); sending = false }
                        }.buttonStyle(PrimaryButtonStyle()).disabled(sending)
                        Divider()
                        Text("Noticed a possible symptom? Send a supportive prompt to consider taking a break. This is not a diagnosis and does not predict overload.").font(.subheadline)
                        Button(sending ? "Saving…" : "Suggest taking a break") {
                            sending = true
                            Task { await store.requestCheckIn(withNotification: notify, symptomBreak: true); sending = false }
                        }.buttonStyle(PrimaryButtonStyle()).disabled(sending)
                    }
                }
                Card {
                    Label("You decide what is shared", systemImage: "hand.raised").font(.headline)
                    Text("The survivor controls history access and contributions separately. A caregiver can add observations without seeing symptom history.")
                }
            }.padding(20)
        }.background(Palette.background).navigationTitle("Today").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $editor) { EditorView(kind: store.role.contribution, existing: nil) }
    }
    private var roleDescription: String {
        switch store.role {
        case .survivor: return "A quick note is enough. You can rate an experience from 1 (mild) to 5 (intense) and describe what was happening."
        case .caregiver: return "Describe what you noticed in your own words."
        case .clinician: return "Review shared information and leave a note."
        case .physician: return "Review shared symptoms and files before adding a note for the survivor."
        }
    }

    private var contributionTitle: String {
        switch store.role {
        case .survivor: return "Log a symptom"
        case .caregiver: return "Add an observation"
        case .clinician: return "Add a clinician note"
        case .physician: return "Add a physician note"
        }
    }
}

/// "How are you feeling?" 1 (extremely overwhelmed) to 5 (perfectly fine), in steps of 0.5.
struct FeelingRatingView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var rating = 3.0
    @State private var errorMessage: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    Text("How are you feeling right now?")
                        .font(.title.bold()).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(FeelingCheck.format(rating))
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .accessibilityHidden(true)
                    HStack(spacing: 16) {
                        stepButton("minus", label: "Lower by half", change: -FeelingCheck.step)
                        Slider(value: $rating, in: FeelingCheck.lowest...FeelingCheck.highest, step: FeelingCheck.step)
                            .accessibilityLabel("Feeling, 1 extremely overwhelmed to 5 perfectly fine")
                            .accessibilityValue("\(FeelingCheck.format(rating)) of 5")
                            .accessibilityIdentifier("feelingSlider")
                        stepButton("plus", label: "Raise by half", change: FeelingCheck.step)
                    }
                    HStack(alignment: .top) {
                        Text("1\n\(FeelingCheck.lowestLabel)").multilineTextAlignment(.leading)
                        Spacer(minLength: 16)
                        Text("5\n\(FeelingCheck.highestLabel)").multilineTextAlignment(.trailing)
                    }.font(.subheadline).foregroundStyle(Palette.secondaryText).accessibilityHidden(true)
                    Button("Save") {
                        do { try store.saveFeeling(rating); dismiss() }
                        catch DemoError.denied { errorMessage = "Only the survivor can answer. Switch to Survivor in Demo settings." }
                        catch { errorMessage = error.localizedDescription }
                    }.buttonStyle(PrimaryButtonStyle()).frame(maxWidth: .infinity).accessibilityIdentifier("saveFeeling")
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                    Text("Your answer stays on this iPhone. It is a personal rating, not a medical score.")
                        .font(.footnote).foregroundStyle(Palette.secondaryText).multilineTextAlignment(.center)
                }.padding(24)
            }
            .background(Palette.background)
            .navigationTitle("Feeling check-in").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } } }
        }
    }
    private func stepButton(_ symbol: String, label: String, change: Double) -> some View {
        Button {
            withAnimation { rating = min(max(rating + change, FeelingCheck.lowest), FeelingCheck.highest) }
        } label: {
            Image(systemName: symbol).font(.title3.weight(.semibold)).frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered).buttonBorderShape(.circle)
        .accessibilityLabel(label)
    }
}

/// Survivor settings for the random reminders, plus recent answers.
struct FeelingCheckInsView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var reminders = FeelingReminders.shared
    @State private var rating = false
    @State private var working = false
    private var recent: [FeelingCheck] { Array(((try? store.feelingChecks()) ?? []).prefix(10)) }
    var body: some View {
        List {
            Section {
                Toggle("Remind me 3 times a day", isOn: Binding(get: { reminders.isEnabled }, set: { value in
                    working = true
                    Task {
                        let ok = await reminders.setEnabled(value)
                        working = false
                        if !ok { store.show("Notifications are off", "Allow notifications for Steady in iPhone Settings, then try again.") }
                    }
                })).disabled(working).accessibilityIdentifier("feelingRemindersToggle")
                Text("Steady picks 3 random times each day between 9 AM and 9 PM. Tap a reminder to rate how you feel.")
                    .font(.footnote).foregroundStyle(Palette.secondaryText)
                if reminders.isEnabled, let next = reminders.nextReminder {
                    LabeledContent("Next reminder", value: next.formatted(date: .abbreviated, time: .shortened))
                }
            }
            Section {
                Button("Rate how I feel now") { rating = true }.accessibilityIdentifier("rateFeelingNow")
            }
            Section(secondary: "Recent answers") {
                if recent.isEmpty {
                    Text("No answers yet.").foregroundStyle(Palette.secondaryText)
                } else {
                    ForEach(recent) { check in
                        LabeledContent(check.recordedAt.formatted(date: .abbreviated, time: .shortened),
                                       value: "\(FeelingCheck.format(check.rating)) of 5")
                    }
                }
            }
        }
        .navigationTitle("Feeling check-ins")
        .task { await reminders.refresh() }
        .sheet(isPresented: $rating) { FeelingRatingView() }
    }
}

struct ClinicianReportView: View {
    @EnvironmentObject private var store: AppStore
    @State private var period: ReportPeriod = .month
    @State private var summary: ClinicianSummary?
    @State private var pdfURL: URL?
    @State private var preview: FilePreview?
    @State private var errorMessage: String?
    var body: some View {
        List {
            Section {
                Text("Pick a time period. Steady builds a PDF you can save to Files, print, or send to your clinician.")
                Picker("Time period", selection: $period) {
                    ForEach(ReportPeriod.allCases) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("reportPeriod")
            }
            if let summary {
                Section(secondary: "At a glance") {
                    ForEach(summary.glance, id: \.self) { Text($0) }
                }
                Section(secondary: "Included") {
                    LabeledContent("Symptoms", value: "\(summary.symptoms.count)")
                    LabeledContent("Activities", value: "\(summary.activities.count)")
                    LabeledContent("Caregiver observations", value: "\(summary.observations.count)")
                    LabeledContent("Clinician notes", value: "\(summary.notes.count)")
                    LabeledContent("Files (names only)", value: "\(summary.files.count)")
                }
                if summary.isEmpty {
                    Section { Text("Nothing was logged in this period. Try a longer one.").foregroundStyle(Palette.secondaryText) }
                }
                Section {
                    if let pdfURL {
                        ShareLink(item: pdfURL) {
                            Label("Save or share PDF", systemImage: "square.and.arrow.up")
                        }.accessibilityIdentifier("shareClinicianSummary")
                        Button { preview = FilePreview(url: pdfURL) } label: {
                            Label("Preview PDF", systemImage: "doc.text.magnifyingglass")
                        }.accessibilityIdentifier("previewClinicianSummary")
                    }
                } footer: {
                    Text("The report stays on this iPhone until you save or share it. It is self-reported and is not a diagnosis.")
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle("Clinician summary").navigationBarTitleDisplayMode(.inline)
        .task(id: period) { build() }
        .sheet(item: $preview) { item in FilePreviewView(url: item.url, title: "Clinician summary") { preview = nil } }
    }

    private func build() {
        do {
            let next = try store.clinicianSummary(period)
            summary = next
            pdfURL = try store.clinicianReportPDF(next)
            errorMessage = nil
        } catch {
            pdfURL = nil
            errorMessage = error.localizedDescription
        }
    }
}

/// Draws a ClinicianSummary as a paginated US Letter PDF.
enum ClinicianReportPDF {
    static func render(_ summary: ClinicianSummary) -> Data {
        let text = NSMutableAttributedString()
        func add(_ string: String, _ font: UIFont, spacingAfter: CGFloat, color: UIColor = .black) {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = spacingAfter
            style.lineBreakMode = .byWordWrapping
            text.append(NSAttributedString(string: string + "\n", attributes: [
                .font: font, .paragraphStyle: style, .foregroundColor: color
            ]))
        }
        add("Steady · Clinician summary", .systemFont(ofSize: 22, weight: .bold), spacingAfter: 4)
        add(summary.coverage, .systemFont(ofSize: 12), spacingAfter: 16, color: .darkGray)
        for section in summary.sections {
            add(section.title, .systemFont(ofSize: 15, weight: .semibold), spacingAfter: 6)
            for (index, line) in section.lines.enumerated() {
                let last = index == section.lines.count - 1
                add(section.title == "About this report" ? line : "•  " + line, .systemFont(ofSize: 11),
                    spacingAfter: last ? 16 : 4)
            }
        }

        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "Steady clinician summary",
                               kCGPDFContextCreator as String: "Steady"]
        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        return UIGraphicsPDFRenderer(bounds: page, format: format).pdfData { context in
            var location = 0
            var pageNumber = 1
            repeat {
                context.beginPage()
                let cg = context.cgContext
                cg.saveGState()
                cg.textMatrix = .identity
                cg.translateBy(x: 0, y: page.height)
                cg.scaleBy(x: 1, y: -1)
                let path = CGPath(rect: CGRect(x: 54, y: 72, width: page.width - 108, height: page.height - 126), transform: nil)
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
                CTFrameDraw(frame, cg)
                let visible = CTFrameGetVisibleStringRange(frame)
                cg.restoreGState()
                let footer = "Self-reported · not a diagnosis · page \(pageNumber)"
                (footer as NSString).draw(at: CGPoint(x: 54, y: page.height - 44), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.darkGray
                ])
                guard visible.length > 0 else { break }
                location += visible.length
                pageNumber += 1
            } while location < text.length
        }
    }
}

struct JournalView: View {
    @EnvironmentObject private var store: AppStore
    @State private var kind: RecordKind = .symptoms
    @State private var editor = false
    private var entries: [DemoRecord] { (try? store.records(kind)) ?? [] }
    var body: some View {
        List {
            Section {
                if store.role == .survivor {
                    NavigationLink("Activity log") {
                        ActivityLogView(privacyNote: "Demo activities are stored on this device.",
                                        load: store.activityEntries, save: store.saveActivity, remove: store.deleteActivity)
                    }
                }
                Picker("Entry type", selection: $kind) {
                    ForEach(RecordKind.allCases.filter { $0 != .attachments }) { Text($0.title).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("entryTypePicker")
                if store.can(kind, .add) { Button { editor = true } label: { Label("Add entry", systemImage: "plus.circle.fill").fixedSize(horizontal: false, vertical: true) } }
            }
            if !store.can(kind, .read) {
                Section {
                    Label("History is private", systemImage: "lock.shield").font(.headline)
                    Text(store.can(kind, .add) ? "You can contribute an entry, but this role cannot read this history." : "The survivor has not shared this history with this role.")
                }
            } else if entries.isEmpty {
                Section { Text("No entries here yet. A short note is a useful start.").foregroundStyle(Palette.secondaryText) }
            } else {
                Section(secondary: "Demo entries") {
                    ForEach(entries) { record in
                        NavigationLink { RecordDetailView(recordID: record.id, kind: kind) } label: { RecordRow(record: record) }
                    }
                }
            }
        }.navigationTitle("Journal")
            .onAppear { kind = store.role.initialJournalKind }
            .sheet(isPresented: $editor) { EditorView(kind: kind, existing: nil) }
    }
}

private struct RecordRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let record: DemoRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(record.title).font(.headline)
            if let severity = record.severity { Text("Intensity \(severity) of 5").font(.subheadline).foregroundStyle(Palette.secondaryText) }
            Text(record.body).font(.subheadline).lineLimit(typeSize.isAccessibilitySize ? 6 : 2).fixedSize(horizontal: false, vertical: true).foregroundStyle(Palette.secondaryText)
            Text("\(record.author.title) · \(record.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(Palette.secondaryText)
        }.padding(.vertical, 6).accessibilityElement(children: .combine)
    }
}

struct RecordDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let recordID: UUID
    let kind: RecordKind
    @State private var editing = false
    @State private var confirmDelete = false
    private var record: DemoRecord? { (try? store.records(kind))?.first { $0.id == recordID } }
    var body: some View {
        Group {
            if let record {
                List {
                    Section {
                        Text(record.title).font(.title2.bold())
                            .lineLimit(nil).minimumScaleFactor(0.6)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAddTraits(.isHeader)
                        if let severity = record.severity { Text("Intensity: \(severity) of 5 (self-reported)") }
                        Text(record.body).textSelection(.enabled)
                    }
                    Section(secondary: "Entry details") {
                        LabeledContent("Author", value: record.author.title)
                        LabeledContent("Added", value: record.createdAt.formatted())
                        LabeledContent("Updated", value: record.updatedAt.formatted())
                    }
                    Section {
                        if store.can(kind, .edit) { Button("Edit entry") { editing = true } }
                        if store.can(kind, .delete) { Button("Delete entry", role: .destructive) { confirmDelete = true } }
                    }
                }.sheet(isPresented: $editing) { EditorView(kind: kind, existing: record) }
            } else { ContentUnavailableView("Entry unavailable", systemImage: "lock", description: Text("This role may not have access, or the entry was deleted.")) }
        }.navigationTitle("Entry").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Delete this entry from this device?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete entry", role: .destructive) {
                    guard let record else { return }
                    do { try store.delete(record); dismiss() } catch { store.report(error) }
                }
            }
    }
}

struct EditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let kind: RecordKind
    let existing: DemoRecord?
    @State private var title: String
    @State private var bodyText: String
    @State private var severity: Int
    @State private var errorMessage: String?
    init(kind: RecordKind, existing: DemoRecord?) {
        self.kind = kind; self.existing = existing
        _title = State(initialValue: existing?.title ?? "")
        _bodyText = State(initialValue: existing?.body ?? "")
        _severity = State(initialValue: existing?.severity ?? 2)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(secondary: kind.title) {
                    TextField("Short title", text: $title).accessibilityLabel("Entry title").accessibilityIdentifier("entryTitle")
                    TextField("What did you notice?", text: $bodyText, axis: .vertical).lineLimit(4...10).accessibilityIdentifier("entryBody")
                    Text("\(title.count)/100 title · \(bodyText.count)/3,000 note").font(.caption).foregroundStyle(Palette.secondaryText)
                }
                if kind == .symptoms {
                    Section(secondary: "Self-reported intensity") {
                        Stepper("\(severity) of 5", value: $severity, in: 1...5).accessibilityIdentifier("intensityStepper")
                        Text("1 = mild · 5 = intense. This is a personal description, not a medical score.").font(.footnote).foregroundStyle(Palette.secondaryText)
                    }
                }
                Section { Text("Demo entries stay on this device.").font(.footnote).foregroundStyle(Palette.secondaryText) }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red).accessibilityAddTraits(.isStaticText) } }
            }.navigationTitle(existing == nil ? "Add entry" : "Edit entry").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            do { try store.save(kind, existing: existing, title: title.trimmingCharacters(in: .whitespacesAndNewlines), body: bodyText, severity: kind == .symptoms ? severity : nil); dismiss() }
                            catch { errorMessage = error.localizedDescription }
                        }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 100 || bodyText.count > 3000).accessibilityIdentifier("saveEntry")
                    }
                }
        }
    }
}

struct FilesView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var importing = false
    @State private var preview: FilePreview?
    @State private var editing: DemoRecord?
    @State private var deleting: DemoRecord?
    private var files: [DemoRecord] { (try? store.records(.attachments)) ?? [] }
    var body: some View {
        List {
            Section {
                Text("Preview the sample MRI illustration or import a PDF, PNG or JPEG up to 15 MB.").font(.subheadline)
                if store.can(.attachments, .add) { Button { importing = true } label: { Label("Import a file", systemImage: "plus.circle").fixedSize(horizontal: false, vertical: true) }.accessibilityIdentifier("importFile") }
            }
            if !store.can(.attachments, .read) {
                Section { Label("Files are private to this role", systemImage: "lock"); Text("Importing, if enabled, does not grant access to existing files.") }
            } else if files.isEmpty {
                Section { Text("No files yet.") }
            } else {
                Section(secondary: "On this device") {
                    ForEach(files) { file in
                        VStack(alignment: .leading, spacing: 10) {
                            RecordRow(record: file)
                            Button("Preview file") { do { preview = FilePreview(url: try store.preview(file.id)) } catch { store.report(error) } }.accessibilityIdentifier("previewFile")
                            // Row actions: body-size text, at least 44x44 pt hit area, spaced apart; stacked at accessibility sizes.
                            let actions = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 24))
                            actions {
                                if store.can(.attachments, .edit) { Button("Edit details") { editing = file }.frame(minWidth: 44, minHeight: 44, alignment: .leading).contentShape(Rectangle()) }
                                if store.can(.attachments, .delete) { Button("Delete", role: .destructive) { deleting = file }.frame(minWidth: 44, minHeight: 44, alignment: .leading).contentShape(Rectangle()) }
                            }.font(.body)
                        }.padding(.vertical, 5).buttonStyle(.borderless)
                    }
                }
            }
        }.navigationTitle("Files")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .png, .jpeg], allowsMultipleSelection: false) { result in
                do { if let url = try result.get().first { try store.importFile(url); store.show("File added", "The file is saved on this device.") } }
                catch { store.report(error) }
            }
            .sheet(item: $preview) { item in FilePreviewView(url: item.url, title: "File preview") { preview = nil } }
            .sheet(item: $editing) { EditorView(kind: .attachments, existing: $0) }
            .confirmationDialog("Delete file and its entry?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete file", role: .destructive) {
                    guard let deleting else { return }
                    do { try store.delete(deleting); self.deleting = nil } catch { store.report(error) }
                }
            }
    }
}

struct FilePreviewView: View {
    let url: URL
    let title: String
    let onDone: () -> Void
    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.background)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) } }
        }
    }
    @ViewBuilder private var content: some View {
        if url.pathExtension.lowercased() == "pdf" {
            PDFPreview(url: url).accessibilityIdentifier("filePreviewPDF")
        } else if let image = UIImage(contentsOfFile: url.path) {
            ZoomableImage(image: image)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).accessibilityHidden(true)
                Text("This file could not be previewed.").font(.headline)
            }.accessibilityElement(children: .combine).accessibilityIdentifier("filePreviewError")
        }
    }
}

private struct ZoomableImage: View {
    let image: UIImage
    @State private var scale: CGFloat = 1
    @State private var committed: CGFloat = 1
    var body: some View {
        Image(uiImage: image)
            .resizable().scaledToFit()
            .scaleEffect(scale)
            .gesture(MagnifyGesture()
                .onChanged { scale = min(max(committed * $0.magnification, 1), 5) }
                .onEnded { _ in committed = scale })
            .onTapGesture(count: 2) { scale = 1; committed = 1 }
            .clipped()
            .accessibilityElement()
            .accessibilityLabel("Image preview")
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("filePreviewImage")
    }
}

private struct PDFPreview: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.document = PDFDocument(url: url); return view
    }
    func updateUIView(_ view: PDFView, context: Context) {}
}

struct SharingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var reset = false
    var body: some View {
        List {
            Section {
                Text("The survivor stays in control").font(.headline)
                Text("Read and add are independent. Editing or deleting also requires read access. A granted edit/delete permission covers all entries of that type, not just the role’s own entries.")
            }
            if store.role == .survivor {
                ForEach(DemoRole.allCases.filter { $0 != .survivor }) { target in
                    Section(target.title) {
                        ForEach(RecordKind.allCases) { kind in
                            DisclosureGroup {
                                ForEach(DemoAction.allCases) { action in
                                    Toggle(action.rawValue.capitalized, isOn: binding(target, kind, action))
                                        .accessibilityLabel("\(target.title) \(action.rawValue) \(kind.title)")
                                        .accessibilityIdentifier("grant-\(target.rawValue)-\(action.rawValue)-\(kind.rawValue)")
                                }
                            } label: { Text(kind.title).accessibilityIdentifier("disclosure-\(target.rawValue)-\(kind.rawValue)") }
                        }
                    }
                }
                Section(secondary: "Start again") {
                    Button("Reset demo", role: .destructive) { reset = true }.accessibilityIdentifier("resetDemo")
                    Text("Restores example entries and default permissions, removes imported files, and clears the local check-in and notification.").font(.footnote).foregroundStyle(Palette.secondaryText)
                }
            } else {
                Section { Label("Only the survivor can change access", systemImage: "lock.shield"); Text("Switch to Survivor to explore permission settings in this single-device demo.") }
            }
            Section(secondary: "About this demo") {
                Text("No accounts, backend, sensor prediction, real patient data, or cross-device messaging. This switcher demonstrates permissions; it does not authenticate anyone who holds the phone.")
                Text("Data is saved locally with iOS file protection and excluded from app backup. This is a prototype, not a production medical record or privacy system.").font(.footnote).foregroundStyle(Palette.secondaryText)
            }
        }.navigationTitle("Your control")
            .confirmationDialog("Reset all demo data on this device?", isPresented: $reset, titleVisibility: .visible) {
                Button("Reset demo", role: .destructive) { do { try store.reset() } catch { store.report(error) } }
            }
    }
    private func binding(_ target: DemoRole, _ kind: RecordKind, _ action: DemoAction) -> Binding<Bool> {
        Binding(get: { (try? store.grants()[target]?[kind]?[action]) ?? false }, set: { value in
            do { try store.setGrant(target, kind, action, value) } catch { store.report(error) }
        })
    }
}

struct RecoveryView: View {
    @EnvironmentObject private var store: AppStore
    let message: String
    @State private var confirm = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("Saved demo needs attention", systemImage: "externaldrive.badge.exclamationmark").font(.title2.bold())
                    .minimumScaleFactor(0.6).fixedSize(horizontal: false, vertical: true)
                Text(message)
                Text("Resetting discards your saved file and restores the demo examples.")
                if store.role == .survivor { Button("Reset demo", role: .destructive) { confirm = true }.buttonStyle(.bordered) }
                else { Text("Switch to Survivor to reset.") }
            }.padding(24)
        }.confirmationDialog("Discard saved demo and reset?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Discard and reset", role: .destructive) { do { try store.reset() } catch { store.report(error) } }
        }
    }
}
