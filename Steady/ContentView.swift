import SwiftUI
import SteadyCore
import UniformTypeIdentifiers
import PDFKit

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
    @State private var accounts = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                // The header is outside any ScrollView, so every piece of text wraps instead of truncating,
                // and at accessibility sizes the brand and demo label stack vertically.
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                layout {
                    Label("Steady", systemImage: "leaf").font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                    if !typeSize.isAccessibilitySize { Spacer() }
                    Text("FICTIONAL DEMO").font(.caption.bold()).foregroundStyle(Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
                Toggle("Accounts and sharing", isOn: $accounts).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                if !accounts { Picker("Demo role", selection: $store.role) {
                    ForEach(DemoRole.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("rolePicker").accessibilityHint("Switches a fictional role on this device. This is not authentication.") }
                if !accounts {
                    Text("One device · role switcher, not secure sign-in").font(.caption).foregroundStyle(Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
            }.padding().background(Palette.surface)
            if accounts {
                AccountView()
            } else if let error = store.loadFailure {
                RecoveryView(message: error)
            } else {
                TabView {
                    NavigationStack { HomeView() }.tabItem { Label("Today", systemImage: "sun.max") }
                    NavigationStack { JournalView() }.tabItem { Label("Journal", systemImage: "book.closed") }
                    NavigationStack { FilesView() }.tabItem { Label("Files", systemImage: "folder") }
                    NavigationStack { SharingView() }.tabItem { Label("Control", systemImage: "hand.raised") }
                }.id(store.role) // Changing identity destroys role-specific editors and previews.
            }
        }.background(Palette.background)
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
                        Button(store.role == .survivor ? "Log a symptom" : store.role == .caregiver ? "Add an observation" : "Add a clinician note") { editor = true }
                            .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("primaryAddButton")
                    } else { Label("Adding is off for this role", systemImage: "lock").foregroundStyle(Palette.secondaryText) }
                    if store.role == .survivor {
                        NavigationLink("Activity log") {
                            ActivityLogView(privacyNote: "Use fictional entries in this on-device demo.",
                                            load: store.activityEntries, save: store.saveActivity, remove: store.deleteActivity)
                        }
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
                Text("All sample entries are fictional. Steady helps record experiences; it does not predict overload, interpret scans, or provide diagnosis or treatment.")
                    .font(.footnote).foregroundStyle(Palette.secondaryText)
            }.padding(20)
        }.background(Palette.background).navigationTitle("Today").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $editor) { EditorView(kind: store.role.contribution, existing: nil) }
    }
    private var roleDescription: String {
        switch store.role {
        case .survivor: return "A quick note is enough. You can rate an experience from 1 (mild) to 5 (intense) and describe what was happening."
        case .caregiver: return "Describe what you noticed in your own words. By default, symptom history stays private to the survivor and clinician."
        case .clinician: return "Review the fictional information shared with you and leave a note. This demo is not a clinical record system."
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
                        ActivityLogView(privacyNote: "Use fictional entries in this on-device demo.",
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
                Section(secondary: "Fictional demo entries") {
                    ForEach(entries) { record in
                        NavigationLink { RecordDetailView(recordID: record.id, kind: kind) } label: { RecordRow(record: record) }
                    }
                }
            }
        }.navigationTitle("Journal")
            .onAppear { kind = store.role.contribution }
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
                Section(secondary: "Fictional \(kind.title.lowercased()) entry") {
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
                Section { Text("Use made-up examples only. Entries stay in this app on this device.").font(.footnote).foregroundStyle(Palette.secondaryText) }
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
                Text("Fictional attachments only").font(.headline)
                Text("Preview a sample brain MRI illustration or import a made-up PDF, PNG or JPEG (up to 15 MB). No scan analysis or diagnostic interpretation.").font(.subheadline)
                if store.can(.attachments, .add) { Button { importing = true } label: { Label("Import a fictional file", systemImage: "plus.circle").fixedSize(horizontal: false, vertical: true) }.accessibilityIdentifier("importFile") }
            }
            if !store.can(.attachments, .read) {
                Section { Label("Files are private to this role", systemImage: "lock"); Text("Importing, if enabled, does not grant access to existing files.") }
            } else if files.isEmpty {
                Section { Text("No files yet. Import a fictional example to try preview.") }
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
                do { if let url = try result.get().first { try store.importFile(url); store.show("File added", "The fictional file was copied into this app on this device.") } }
                catch { store.report(error) }
            }
            .sheet(item: $preview) { item in FilePreviewView(url: item.url, title: "Fictional file preview") { preview = nil } }
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
            VStack(spacing: 12) {
                ZoomableImage(image: image)
                Text("Fictional illustration. Not a patient scan and not interpreted by Steady.")
                    .font(.footnote).foregroundStyle(Palette.secondaryText).multilineTextAlignment(.center).padding(.horizontal)
            }.padding(.bottom)
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
            .accessibilityLabel("Fictional brain MRI illustration. Not a patient scan.")
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
                ForEach([DemoRole.caregiver, .clinician]) { target in
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
                    Button("Reset fictional demo", role: .destructive) { reset = true }.accessibilityIdentifier("resetDemo")
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
                Text("Your saved file has not been silently replaced. Resetting discards it and restores fictional examples.")
                if store.role == .survivor { Button("Reset fictional demo", role: .destructive) { confirm = true }.buttonStyle(.bordered) }
                else { Text("Switch to Survivor to reset.") }
            }.padding(24)
        }.confirmationDialog("Discard saved demo and reset?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Discard and reset", role: .destructive) { do { try store.reset() } catch { store.report(error) } }
        }
    }
}
