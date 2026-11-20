import SwiftUI
import SteadyCore
import UniformTypeIdentifiers

struct AccountView: View {
    let openDemo: () -> Void
    @StateObject private var client = CloudClient()
    @ObservedObject private var push = PushRegistrar.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var email = ""
    @State private var password = ""
    @State private var creating = false
    @State private var profileRole: DemoRole?
    @State private var busy = false
    @State private var kind: RecordKind = .symptoms
    @State private var editor = false
    @State private var editing: CloudRecord?
    @State private var preview: FilePreview?
    @State private var importing = false
    @State private var deleting: CloudRecord?
    @State private var inviteEmail = ""
    @State private var inviteRole: DemoRole = .caregiver
    @State private var invitationToken = ""
    @State private var acceptToken = ""
    @State private var joiningAnotherCircle = false
    @State private var profileEditor: ProfileEditor?
    @State private var setupErrorFor: UUID?
    @State private var setupRetry = UUID()
    private var hostedDemo: Bool { client.config?.isHostedDemo == true }
    private var accountRole: DemoRole? { client.session?.user.profileRole }
    private struct ProfileEditor: Identifiable {
        let id: UUID
        let profile: SurvivorProfile?
    }
    private struct SetupCheck: Equatable {
        let userID: UUID?
        let role: DemoRole?
        let retry: UUID
    }
    var body: some View {
        NavigationStack {
            Form {
                if client.config == nil { setupSection }
                else if client.session == nil { signInSection }
                else {
                    if let accountRole {
                        if accountRole == .survivor { survivorSection }
                        circlesSection
                        if client.circles.isEmpty, accountRole != .survivor { joinSection }
                        if client.circleID != nil {
                            if accountRole == .survivor, client.role == "survivor" {
                                Section(secondary: "Sharing") {
                                    NavigationLink("Manage sharing") { sharingView }
                                }
                            }
                            if let profile = client.sharedSurvivorProfile {
                                Section("Shared survivor profile") {
                                    SharedSurvivorProfileView(profile: profile)
                                }
                            }
                            journalSection
                            if accountRole == .survivor || accountRole == .caregiver { checkInSection }
                        }
                    }
                    accountSection
                }
                if client.session == nil {
                    Section {
                        Button("Demo settings", action: openDemo)
                            .disabled(busy)
                            .accessibilityIdentifier("openDemoSettings")
                    }
                }
            }.navigationTitle(accountRole.map { "\($0.title) workspace" } ?? "Steady").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if client.session != nil {
                        ToolbarItem(placement: .primaryAction) {
                            Menu("Account", systemImage: "person.crop.circle") {
                                Button("Sign out", role: .destructive) {
                                    email = ""; password = ""; creating = false
                                    Task { await client.signOut() }
                                }
                            }
                            .disabled(busy)
                        }
                    }
                }
                .refreshable {
                    if client.session != nil { await perform { try await client.loadCircles() } }
                }
                .sheet(isPresented: $editor) { CloudEditor(client: client, kind: kind, existing: nil) }
                .sheet(item: $editing) { CloudEditor(client: client, kind: RecordKind(rawValue: $0.kind) ?? .notes, existing: $0) }
                .sheet(item: $preview) { item in
                    FilePreviewView(url: item.url, title: "File preview") { preview = nil }
                }
                .sheet(isPresented: $joiningAnotherCircle) {
                    NavigationStack {
                        Form { joinSection }
                            .navigationTitle("Join a circle")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Cancel") { joiningAnotherCircle = false }
                                }
                            }
                    }
                }
                .sheet(item: $profileEditor) { editor in
                    SurvivorProfileView(profile: editor.profile) { profile in
                        guard client.session?.user.id == editor.id else { throw CancellationError() }
                        try await client.saveSurvivorProfile(profile)
                    }
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
                .onChange(of: scenePhase) { _, value in
                    if value != .active { preview = nil; client.clearVisibleData() }
                    else if client.session != nil { Task { await perform { try await client.loadCircles() } } }
                }
                .onChange(of: client.can(.attachments, .read)) { _, allowed in if !allowed { preview = nil } }
                .onChange(of: client.circleID) { _, _ in
                    editing = nil; editor = false; preview = nil; invitationToken = ""; inviteEmail = ""
                }
                .onChange(of: accountRole, initial: true) { _, role in
                    kind = role?.initialJournalKind ?? .symptoms
                }
                .onChange(of: push.deviceToken) { _, _ in Task { await registerPushTokenIfPossible() } }
        }
        .id(client.session?.user.id)
        .onChange(of: client.session?.user.id) { _, userID in
            editing = nil; editor = false; preview = nil; deleting = nil; importing = false
            joiningAnotherCircle = false; acceptToken = ""; inviteEmail = ""; invitationToken = ""
            inviteRole = .caregiver
            profileRole = nil
            if profileEditor?.id != userID { profileEditor = nil }
            if setupErrorFor != userID { setupErrorFor = nil }
            if userID != nil {
                push.requestAuthorizationAndRegister()
                Task { await registerPushTokenIfPossible() }
            }
        }
        .task(id: SetupCheck(userID: client.session?.user.id, role: client.session?.user.profileRole, retry: setupRetry)) {
            guard client.session?.user.profileRole == .survivor, let id = client.session?.user.id else { return }
            do {
                let profile = try await client.loadSurvivorProfile()
                guard !Task.isCancelled, client.session?.user.id == id else { return }
                setupErrorFor = nil
                if profile == nil && profileEditor == nil { profileEditor = ProfileEditor(id: id, profile: nil) }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, client.session?.user.id == id else { return }
                setupErrorFor = id
            }
        }
        .task {
            if client.session != nil {
                push.requestAuthorizationAndRegister()
                await perform { try await client.loadCircles() }
                await registerPushTokenIfPossible()
            }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                if scenePhase == .active, client.session != nil, !busy {
                    await perform { try await client.loadCircles() }
                }
            }
        }
        .onDisappear { preview = nil; client.clearVisibleData() }
        .alert("Account update", isPresented: Binding(get: { client.message != nil }, set: { if !$0 { client.message = nil } })) { Button("OK") { client.message = nil } } message: { Text(client.message ?? "") }
    }
    private var setupSection: some View {
        Section(secondary: "Backend setup is pending") {
            Text("This build is missing its backend settings. Download the latest Steady project or follow backend/README.md to configure a test backend.")
        }
    }
    private var signInSection: some View {
        Section(creating ? "Create an account" : "Sign in") {
            Picker("Account action", selection: $creating) {
                Text("Sign in").tag(false)
                Text("Sign up").tag(true)
            }.pickerStyle(.segmented).disabled(busy)
            if creating {
                profileRolePicker("I’m signing up as")
                if let profileRole { Text(profileDescription(profileRole)).font(.footnote).foregroundStyle(Palette.secondaryText) }
            }
            TextField(hostedDemo ? "Demo username" : "Email", text: $email).textContentType(.username)
                .keyboardType(hostedDemo ? .asciiCapable : .emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(busy)
            SecureField(hostedDemo ? "Demo password" : "Password", text: $password).textContentType(creating ? .newPassword : .password).disabled(busy)
            if hostedDemo && creating {
                Text("Choose a demo username and a password of at least 10 characters. Keep your password for later sign-in. Demo accounts have no email recovery.")
                    .font(.footnote).foregroundStyle(Palette.secondaryText)
            }
            Button(busy ? "Working…" : creating ? "Create account" : "Sign in") {
                Task {
                    await perform {
                        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
                        if creating, let profileRole {
                            try await client.signUp(email: address, password: password, role: profileRole)
                            creating = false
                        } else {
                            try await client.signIn(email: address, password: password)
                        }
                        password = ""
                    }
                }
            }.disabled(busy || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || (creating && profileRole == nil))
        }
    }
    private func profileRolePicker(_ label: String) -> some View {
        Picker(label, selection: $profileRole) {
            Text("Choose a role").tag(DemoRole?.none)
            ForEach(DemoRole.allCases) { Text($0.title).tag(Optional($0)) }
        }.disabled(busy)
    }
    private func profileDescription(_ role: DemoRole) -> String {
        switch role {
        case .survivor: return "Create your own circle and choose what to share."
        case .caregiver: return "Accept a survivor’s invitation to share observations and suggest check-ins."
        case .clinician: return "Accept a survivor’s invitation to review shared records and contribute notes."
        case .physician: return "Accept a survivor’s invitation to review their shared symptoms, injury details, and files."
        }
    }
    private var survivorSection: some View {
        Section(secondary: "Your recovery") {
            if let setupErrorFor, setupErrorFor == client.session?.user.id {
                Text("Couldn’t check your survivor setup. Try again when you’re connected.")
                    .font(.footnote).foregroundStyle(Palette.secondaryText)
                Button("Retry setup") { self.setupErrorFor = nil; setupRetry = UUID() }
            }
            Button("Survivor profile") {
                Task {
                    await perform {
                        guard let id = client.session?.user.id else { return }
                        let profile = try await client.loadSurvivorProfile()
                        guard client.session?.user.id == id else { return }
                        setupErrorFor = nil
                        profileEditor = ProfileEditor(id: id, profile: profile)
                    }
                }
            }.disabled(busy)
            if let userID = client.session?.user.id {
                NavigationLink("Activity log") {
                    ActivityLogView(load: client.loadActivities, save: client.saveActivity, remove: client.deleteActivity)
                        .id(userID)
                }
            }
            NavigationLink("Feeling check-ins") { FeelingCheckInsView() }
        }
    }
    private var accountSection: some View {
        Section(secondary: "Account") {
            Text(accountLabel(client.session?.user.email ?? "Signed in"))
            if accountRole == nil {
                Text("Choose your role to finish setting up this account.").font(.footnote)
                profileRolePicker("Account role")
                Button("Save account role") {
                    Task { await perform { if let profileRole { try await client.saveProfileRole(profileRole) } } }
                }.disabled(busy || profileRole == nil)
            }
        }
    }
    private var circlesSection: some View {
        Section(secondary: "Circles") {
            if !client.circles.isEmpty {
                Picker("Circle", selection: Binding(get: { client.circleID }, set: { value in
                    preview = nil; invitationToken = ""; client.clearVisibleData(); client.circleID = value
                    Task { await perform { try await client.refresh() } }
                })) {
                    ForEach(client.circles) { Text($0.name).tag(Optional($0.id)) }
                }
                Button("Join another circle") { joiningAnotherCircle = true }.disabled(busy)
            }
            if let role = client.role { LabeledContent("Role in this circle", value: role.capitalized) }
            if client.session?.user.profileRole == .survivor,
               !client.circles.contains(where: { $0.owner_id == client.session?.user.id }) {
                Button("Create my circle") { Task { await perform { try await client.createCircle() } } }.disabled(busy)
            }
            Button("Refresh shared data") { Task { await perform { try await client.loadCircles() } } }.disabled(busy)
        }
    }
    private var joinSection: some View {
        Section(secondary: "Join a survivor’s circle") {
            Text(hostedDemo ? "Use the code the survivor shares with you. Sign in with the demo username they invited."
                 : "Use the invitation code the survivor shares with you. Sign in with the email address they invited.")
                .font(.footnote).foregroundStyle(Palette.secondaryText)
            TextField("Invitation code", text: $acceptToken, axis: .vertical)
                .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
            Button("Join circle") {
                Task {
                    await perform {
                        try await client.accept(acceptToken.trimmingCharacters(in: .whitespacesAndNewlines))
                        acceptToken = ""
                        joiningAnotherCircle = false
                    }
                }
            }.disabled(busy || acceptToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    private var sharingView: some View {
        Form {
            if client.role == "survivor" {
                invitationsSection
                membersSection
                accessSection
            } else {
                ContentUnavailableView("Sharing unavailable", systemImage: "person.crop.circle.badge.exclamationmark")
            }
        }.navigationTitle("Manage sharing")
    }
    private var journalSection: some View {
        Section(secondary: accountRole == .physician ? "Survivor records" : "Shared journal") {
            Picker("Type", selection: $kind) { ForEach(RecordKind.allCases) { Text($0.title).tag($0) } }
            if client.can(kind, .add) {
                Button(journalAddTitle) { if kind == .attachments { importing = true } else { editor = true } }.disabled(busy)
                if kind == .attachments {
                    Button("Upload sample MRI illustration") {
                        guard let url = Bundle.main.url(forResource: "Fictional-brain-MRI", withExtension: "png", subdirectory: "SteadyResources") else { return }
                        Task { await perform { try await client.upload(url, displayName: "Sample-brain-MRI.png") } }
                    }.disabled(busy)
                }
            } else if kind == .attachments, accountRole == .clinician || accountRole == .physician {
                Text("Ask the survivor to grant Files → Add to upload a file.").font(.caption).foregroundStyle(Palette.secondaryText)
            }
            if !client.can(kind, .read) {
                Label("History is private", systemImage: "lock.shield")
                Text(client.can(kind, .add) ? "You can add an entry without reading this history." : "The survivor has not granted access to this history.")
            } else {
                let entries = client.records.filter { $0.kind == kind.rawValue }
                if entries.isEmpty { Text("No shared entries yet.").foregroundStyle(Palette.secondaryText) }
                ForEach(entries) { record in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(record.title).font(.headline)
                        if let severity = record.severity { Text("Self-reported intensity \(severity) of 5").font(.subheadline) }
                        Text(record.body)
                        Text(record.created_at).font(.caption).foregroundStyle(Palette.secondaryText)
                        if record.file_path != nil {
                            Button("Preview file") { Task { await perform { preview = FilePreview(url: try await client.preview(record)) } } }.disabled(busy)
                        }
                        HStack {
                            if client.can(kind, .edit) { Button("Edit") { editing = record } }
                            if client.can(kind, .delete) { Button("Delete", role: .destructive) { deleting = record } }
                        }.buttonStyle(.borderless)
                    }.padding(.vertical, 8)
                }
                Text("Showing up to 200 most recent shared records. This demo does not paginate older records.").font(.caption).foregroundStyle(Palette.secondaryText)
            }
        }
    }
    private var journalAddTitle: String {
        switch kind {
        case .attachments: return "Import a file"
        case .notes where accountRole == .physician: return "Add a physician note"
        case .notes where accountRole == .clinician: return "Add a clinician note"
        default: return "Add entry"
        }
    }
    private var accessSection: some View {
        Section(secondary: "What each role can access") {
            Text("These permissions apply to everyone with that role in this circle. Review them before sharing an invitation. Editing or deleting also requires read access.").font(.footnote)
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
        Section(secondary: "Invite someone to your circle") {
            TextField(hostedDemo ? "Recipient’s demo username" : "Recipient account email", text: $inviteEmail)
                .keyboardType(hostedDemo ? .asciiCapable : .emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
            Picker("Role in your circle", selection: $inviteRole) {
                ForEach(DemoRole.allCases.filter { $0 != .survivor }) { role in
                    Text(role.title).tag(role)
                }
            }
            if hostedDemo {
                Text("Ask the recipient to create a demo account first, then enter their username here.")
                    .font(.footnote).foregroundStyle(Palette.secondaryText)
            }
            Text("Review the role’s permissions below before sharing the code.").font(.footnote).foregroundStyle(Palette.secondaryText)
            Button("Create invitation code") {
                Task {
                    await perform {
                        invitationToken = try await client.invite(email: inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines), role: inviteRole.rawValue)
                        inviteEmail = ""
                        try await client.refresh()
                    }
                }
            }.disabled(busy || inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !invitationToken.isEmpty {
                Text("Share this code privately with the person you invited. They can use it once within seven days.").font(.footnote)
                Text(invitationToken).font(.caption.monospaced()).textSelection(.enabled).privacySensitive()
                ShareLink("Share invitation code", item: invitationToken)
            }
            ForEach(client.invitations.filter { $0.revoked_at == nil && $0.accepted_at == nil }) { invitation in
                VStack(alignment: .leading) {
                    Text("\(accountLabel(invitation.recipient_email)) · \(invitation.role)").font(.subheadline)
                    Text("Expires: \(invitation.expires_at)").font(.caption)
                    Button("Revoke invitation", role: .destructive) { Task { await perform { try await client.revoke(invitation.id) } } }.disabled(busy)
                }
            }
        }
    }
    private var membersSection: some View {
        Section {
            if client.members.isEmpty { Text("No one has joined your circle yet.").foregroundStyle(Palette.secondaryText) }
            ForEach(client.members) { member in
                let address = client.invitations.first {
                    $0.recipient_user_id == member.user_id && $0.accepted_at != nil
                }?.recipient_email ?? member.user_id.uuidString
                VStack(alignment: .leading, spacing: 10) {
                    Text(member.role.capitalized)
                    Text(accountLabel(address)).font(.subheadline)
                    if let sharing = member.shares_survivor_profile {
                        Toggle("Share injury details and ranked symptoms", isOn: Binding(get: { sharing }, set: { enabled in
                            Task { await perform { try await client.setProfileSharing(for: member.id, enabled: enabled) } }
                        }))
                        .disabled(busy)
                        .accessibilityHint("Applies to \(accountLabel(address))")
                    }
                    Button("Remove access", role: .destructive) { Task { await perform { try await client.removeMember(member.user_id) } } }.disabled(busy)
                }
            }
        } header: {
            Text("People with access")
        } footer: {
            if client.members.contains(where: { $0.shares_survivor_profile != nil }) {
                Text("Each switch gives that person read-only access to your current injury date, description, notes, and symptom order. You can turn it off at any time.")
            }
        }
    }
    private var checkInSection: some View {
        Section(secondary: "Check-ins") {
            if client.role == "caregiver" {
                Button("Suggest a survivor check-in") { Task { await perform { try await client.checkIn() } } }.disabled(busy)
                Button("I noticed a possible symptom - suggest a break") { Task { await perform { try await client.requestSymptomBreak() } } }.disabled(busy)
                Text("This is a supportive prompt from you, not a diagnosis and not a prediction of overload. Live cross-device push needs a paid Apple Developer account and configured APNs; until then the survivor sees it on the next foreground refresh, and in local demo mode via a same-device notification.").font(.footnote).foregroundStyle(Palette.secondaryText)
            }
            ForEach(client.checkIns) { checkIn in
                Text(checkIn.body)
                if client.role == "survivor" { Button("Dismiss check-in") { Task { await perform { try await client.dismissCheckIn(checkIn.id) } } }.disabled(busy) }
            }
        }
    }
    private func perform(_ operation: () async throws -> Void) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { try await operation() }
        catch is CancellationError { }
        catch let error as URLError where error.code == .cancelled { }
        catch { client.message = error.localizedDescription }
    }
    private func accountLabel(_ address: String) -> String {
        hostedDemo ? DemoAccount.username(for: address) : address
    }
    // Upload the captured APNs token once the user is signed in. Silent on failure
    // (for example without a paid Apple account); the foreground refresh is the fallback.
    private func registerPushTokenIfPossible() async {
        guard client.session != nil, let token = push.deviceToken else { return }
        do { try await client.registerDeviceToken(token) } catch { }
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
