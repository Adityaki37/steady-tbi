import SwiftUI
import SteadyCore
import UniformTypeIdentifiers

struct AccountView: View {
    @StateObject private var client = CloudClient()
    @Environment(\.scenePhase) private var scenePhase
    @State private var email = ""
    @State private var password = ""
    @State private var creating = false
    @State private var busy = false
    @State private var kind: RecordKind = .symptoms
    @State private var editor = false
    @State private var editing: CloudRecord?
    @State private var preview: FilePreview?
    @State private var importing = false
    @State private var deleting: CloudRecord?
    @State private var inviteEmail = ""
    @State private var inviteRole = "caregiver"
    @State private var invitationToken = ""
    @State private var acceptToken = ""
    var body: some View {
        NavigationStack {
            Form {
                if client.config == nil { setupSection }
                else if client.session == nil { signInSection }
                else {
                    accountSection
                    circlesSection
                    if client.circleID != nil {
                        journalSection
                        if client.role == "survivor" { accessSection; invitationsSection; membersSection }
                        checkInSection
                    }
                }
                Section("Fictional-data prototype") {
                    Text("Use fictional records only. Account mode syncs with the configured backend. Local demo data is separate and is never uploaded automatically.")
                    Text("Check-ins sync in the app while open (every 15 seconds or on refresh). No APNs or background remote push is configured.").font(.footnote).foregroundStyle(.secondary)
                    Text("After a network error, shared history is cleared until a successful refresh. Previously viewed or exported information cannot be taken back by revocation.").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Separate accounts").navigationBarTitleDisplayMode(.inline)
                .refreshable { await perform { try await client.loadCircles() } }
                .sheet(isPresented: $editor) { CloudEditor(client: client, kind: kind, existing: nil) }
                .sheet(item: $editing) { CloudEditor(client: client, kind: RecordKind(rawValue: $0.kind) ?? .notes, existing: $0) }
                .sheet(item: $preview) { item in
                    NavigationStack { QuickLookView(url: item.url).navigationTitle("Fictional file").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { preview = nil } } } }
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.png,.jpeg,.pdf], allowsMultipleSelection: false) { result in
                    Task { await perform { if let file = try result.get().first { try await client.upload(file) } } }
                }
                .confirmationDialog("Delete this shared entry?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                    Button("Delete shared entry", role: .destructive) {
                        guard let record = deleting else { return }; deleting = nil
                        Task { await perform { try await client.delete(record) } }
                    }
                }
                .alert("Account update", isPresented: Binding(get: { client.message != nil }, set: { if !$0 { client.message = nil } })) { Button("OK") { client.message = nil } } message: { Text(client.message ?? "") }
                .task {
                    if client.session != nil { await perform { try await client.loadCircles() } }
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(15)) } catch { return }
                        if scenePhase == .active, client.session != nil, !busy {
                            do { try await client.refresh() } catch { client.message = error.localizedDescription }
                        }
                    }
                }
                .onChange(of: scenePhase) { _, value in
                    if value != .active { preview = nil; client.clearVisibleData() }
                    else if client.session != nil { Task { await perform { try await client.refresh() } } }
                }
                .onChange(of: client.can(.attachments, .read)) { _, allowed in if !allowed { preview = nil } }
                .onChange(of: client.circleID) { _, _ in editing = nil; editor = false; preview = nil }
                .onChange(of: client.session?.user.id) { _, _ in editing = nil; editor = false; preview = nil; invitationToken = "" }
                .onDisappear { preview = nil; client.clearVisibleData() }
        }
    }
    private var setupSection: some View {
        Section("Backend setup is pending") {
            Label("The local demo works now", systemImage: "checkmark.circle")
            Text("A new Supabase project must be configured before separate devices can share fictional data. No hosted database was provisioned with this source project.")
            Text("On your Mac, follow backend/README.md. Copy Resources/Backend.example.plist to Backend.local.plist and enter the project URL and publishable key, then rebuild.")
        }
    }
    private var signInSection: some View {
        Section(creating ? "Create a test account" : "Sign in") {
            TextField("Email", text: $email).textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("Password", text: $password).textContentType(creating ? .newPassword : .password)
            Toggle("Create a new account", isOn: $creating)
            Button(busy ? "Working…" : creating ? "Create account" : "Sign in") {
                Task {
                    await perform { try await client.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password, create: creating) }
                    password = ""
                }
            }.disabled(busy || email.isEmpty || password.isEmpty)
            Text("Confirm the email if requested, then sign in. Use separate test accounts for each person. Passwords are not stored by this app; session tokens are stored in iOS Keychain.").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var accountSection: some View {
        Section {
            Text(client.session?.user.email ?? "Signed in")
            if let role = client.role { Label("Assigned role: \(role.capitalized)", systemImage: "person.crop.circle.badge.checkmark") }
            Button("Sign out", role: .destructive) {
                invitationToken = ""; acceptToken = ""; password = ""; preview = nil
                Task { await client.signOut() }
            }
        }
    }
    private var circlesSection: some View {
        Section("Fictional circles") {
            if !client.circles.isEmpty {
                Picker("Circle", selection: Binding(get: { client.circleID }, set: { value in
                    preview = nil; invitationToken = ""; client.clearVisibleData(); client.circleID = value
                    Task { await perform { try await client.refresh() } }
                })) {
                    ForEach(client.circles) { Text($0.name).tag(Optional($0.id)) }
                }
                Button("Refresh shared data") { Task { await perform { try await client.loadCircles() } } }.disabled(busy)
            }
            if !client.circles.contains(where: { $0.owner_id == client.session?.user.id }) {
                Button("Start my survivor circle") { Task { await perform { try await client.createCircle() } } }.disabled(busy)
            }
            TextField("Invitation token", text: $acceptToken, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
            Button("Accept invitation") { Task { await perform { try await client.accept(acceptToken.trimmingCharacters(in: .whitespacesAndNewlines)); acceptToken = "" } } }.disabled(busy || acceptToken.isEmpty)
        }
    }
    private var journalSection: some View {
        Section("Shared journal") {
            Picker("Type", selection: $kind) { ForEach(RecordKind.allCases) { Text($0.title).tag($0) } }
            if client.can(kind, .add) {
                Button(kind == .attachments ? "Import a fictional file" : "Add fictional entry") { if kind == .attachments { importing = true } else { editor = true } }.disabled(busy)
                if kind == .attachments, client.role == "survivor" {
                    Button("Upload bundled fictional MRI illustration") {
                        guard let url = Bundle.main.url(forResource: "Fictional-brain-MRI", withExtension: "png", subdirectory: "Resources") else { return }
                        Task { await perform { try await client.upload(url) } }
                    }.disabled(busy)
                }
            }
            if !client.can(kind, .read) {
                Label("History is private", systemImage: "lock.shield")
                Text(client.can(kind, .add) ? "You can add an entry without reading this history." : "The survivor has not granted access to this history.")
            } else {
                let entries = client.records.filter { $0.kind == kind.rawValue }
                if entries.isEmpty { Text("No shared entries yet. Add a fictional example.").foregroundStyle(.secondary) }
                ForEach(entries) { record in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(record.title).font(.headline)
                        if let severity = record.severity { Text("Self-reported intensity \(severity) of 5").font(.subheadline) }
                        Text(record.body)
                        Text(record.created_at).font(.caption).foregroundStyle(.secondary)
                        if record.file_path != nil {
                            Button("Preview fictional file") { Task { await perform { preview = FilePreview(url: try await client.preview(record)) } } }.disabled(busy)
                        }
                        HStack {
                            if client.can(kind, .edit) { Button("Edit") { editing = record } }
                            if client.can(kind, .delete) { Button("Delete", role: .destructive) { deleting = record } }
                        }.buttonStyle(.borderless)
                    }.padding(.vertical, 8)
                }
                Text("Showing up to 200 most recent shared records. This demo does not paginate older records.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var accessSection: some View {
        Section("Survivor access control") {
            Text("Read/add/edit/delete apply per role and entry type. Edit/delete also require read. Changes are enforced by server policies on the next request.").font(.footnote)
            ForEach(client.grants) { grant in
                DisclosureGroup("\(grant.role.capitalized) · \(RecordKind(rawValue: grant.kind)?.title ?? grant.kind)") {
                    ForEach(DemoAction.allCases) { action in
                        Toggle(action.rawValue.capitalized, isOn: Binding(get: { grant[action] }, set: { value in Task { await perform { try await client.setGrant(grant, action: action, value: value) } } }))
                            .disabled(busy).accessibilityLabel("\(grant.role) \(action.rawValue) \(grant.kind)")
                    }
                }
            }
        }
    }
    private var invitationsSection: some View {
        Section("Invite a test caregiver or clinician") {
            TextField("Recipient account email", text: $inviteEmail).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
            Picker("Invite role", selection: $inviteRole) { Text("Caregiver").tag("caregiver"); Text("Clinician").tag("clinician") }
            Button("Create one-time invitation") { Task { await perform { invitationToken = try await client.invite(email: inviteEmail, role: inviteRole) } } }.disabled(busy || inviteEmail.isEmpty)
            if !invitationToken.isEmpty {
                Text("Share this token privately with the named recipient. Expires after seven days; accepted only by their confirmed email account.").font(.footnote)
                Text(invitationToken).font(.caption.monospaced()).textSelection(.enabled).privacySensitive()
                ShareLink("Share invitation token", item: invitationToken)
            }
            ForEach(client.invitations.filter { $0.revoked_at == nil && $0.accepted_at == nil }) { invitation in
                VStack(alignment: .leading) {
                    Text("\(invitation.recipient_email) · \(invitation.role)").font(.subheadline)
                    Text("Expires: \(invitation.expires_at)").font(.caption)
                    Button("Revoke invitation", role: .destructive) { Task { await perform { try await client.revoke(invitation.id) } } }.disabled(busy)
                }
            }
            Text("No invitation email is sent automatically.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var membersSection: some View {
        Section("Connected test accounts") {
            ForEach(client.members) { member in
                VStack(alignment: .leading) {
                    Text(member.role.capitalized)
                    Text(member.user_id.uuidString).font(.caption.monospaced())
                    Button("Remove access", role: .destructive) { Task { await perform { try await client.removeMember(member.user_id) } } }.disabled(busy)
                }
            }
        }
    }
    private var checkInSection: some View {
        Section("Check-ins") {
            if client.role == "caregiver" {
                Button("Suggest a survivor check-in") { Task { await perform { try await client.checkIn() } } }.disabled(busy)
            }
            ForEach(client.checkIns) { checkIn in
                Text(checkIn.body)
                if client.role == "survivor" { Button("Dismiss check-in") { Task { await perform { try await client.dismissCheckIn(checkIn.id) } } }.disabled(busy) }
            }
        }
    }
    private func perform(_ operation: () async throws -> Void) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { try await operation() } catch is CancellationError { } catch { client.message = error.localizedDescription }
    }
}

struct CloudEditor: View {
    @ObservedObject var client: CloudClient
    @Environment(\.dismiss) private var dismiss
    let kind: RecordKind
    let existing: CloudRecord?
    @State private var title: String
    @State private var note: String
    @State private var severity: Int
    @State private var saving = false
    @State private var error: String?
    init(client: CloudClient, kind: RecordKind, existing: CloudRecord?) {
        self.client = client; self.kind = kind; self.existing = existing
        _title = State(initialValue: existing?.title ?? ""); _note = State(initialValue: existing?.body ?? "")
        _severity = State(initialValue: existing?.severity ?? 2)
    }
    var body: some View {
        NavigationStack {
            Form {
                Text("Fictional records only. This entry syncs with the configured test circle.").font(.footnote)
                TextField("Short title", text: $title)
                TextField("What did you notice?", text: $note, axis: .vertical).lineLimit(4...10)
                if kind == .symptoms { Stepper("Intensity \(severity) of 5", value: $severity, in: 1...5) }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle(existing == nil ? "Add shared entry" : "Edit shared entry").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saving ? "Saving…" : "Save") {
                            saving = true
                            Task {
                                defer { saving = false }
                                do { try await client.save(kind: kind, existing: existing, title: title, body: note, severity: kind == .symptoms ? severity : nil); dismiss() }
                                catch { self.error = error.localizedDescription }
                            }
                        }.disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 100 || note.count > 3000)
                    }
                }.interactiveDismissDisabled(saving)
        }
    }
}
