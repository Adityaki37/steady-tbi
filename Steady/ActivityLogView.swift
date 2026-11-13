import SwiftUI
import SteadyCore

struct ActivityLogView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var entries: [ActivityEntry] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var editor: Editor?
    @State private var deleting: ActivityEntry?
    @State private var removing = false
    @State private var refreshID = UUID()

    var privacyNote = "Your activity log is private to you."
    let load: () async throws -> [ActivityEntry]
    let save: (ActivityEntry, Bool) async throws -> Void
    let remove: (UUID) async throws -> Void

    private struct Editor: Identifiable {
        let id = UUID()
        var entry: ActivityEntry?
    }

    var body: some View {
        List {
            Section {
                Button { editor = Editor() } label: { Label("Log activity", systemImage: "plus.circle") }
            } footer: {
                Text(privacyNote)
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            } else if !loaded {
                ProgressView("Loading activities")
            } else if entries.isEmpty {
                ContentUnavailableView("No activities logged", systemImage: "clock")
            }
            if !entries.isEmpty {
                Section(secondary: "Past activities") {
                    ForEach(entries) { entry in
                        Button { editor = Editor(entry: entry) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.activity).font(.headline).foregroundStyle(.primary)
                                Text(entry.startedAt.formatted(date: .abbreviated, time: .shortened))
                                Text("\(entry.durationMinutes) min · Fatigue \(entry.fatigue) of 5")
                                Text(entry.symptoms.isEmpty ? "No symptoms recorded" : entry.symptoms)
                            }.foregroundStyle(Palette.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                                .accessibilityElement(children: .combine)
                        }.accessibilityHint("Opens this activity for editing")
                        .swipeActions(allowsFullSwipe: false) {
                            Button("Delete", role: .destructive) { deleting = entry }
                        }
                    }
                }
            }
        }
        .disabled(removing)
        .privacySensitive()
        .navigationTitle("Activity log")
        .task(id: scenePhase) {
            if scenePhase == .active { await refresh() }
            else if scenePhase == .background {
                refreshID = UUID()
                entries = []
                loaded = false
                error = nil
                deleting = nil
            }
        }
        .refreshable { await refresh() }
        .sheet(item: $editor) { selection in
            ActivityEditor(entry: selection.entry, id: selection.id) { entry in
                try await save(entry, selection.entry != nil)
                await refresh()
            }
        }
        .confirmationDialog("Delete this activity?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            Button("Delete activity", role: .destructive) {
                guard let entry = deleting else { return }
                deleting = nil
                removing = true
                Task {
                    defer { removing = false }
                    do { try await remove(entry.id); await refresh() }
                    catch { self.error = error.localizedDescription }
                }
            }
        }
    }

    private func refresh() async {
        guard scenePhase == .active else { return }
        let id = UUID()
        refreshID = id
        do {
            let updated = try await load()
            guard id == refreshID, !Task.isCancelled else { return }
            entries = updated
            loaded = true
            error = nil
        } catch {
            guard id == refreshID, !Task.isCancelled, !(error is CancellationError) else { return }
            entries = []
            self.error = error.localizedDescription
        }
    }
}

private struct ActivityEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var activity: String
    @State private var startedAt: Date
    @State private var minutes: String
    @State private var fatigue: Int?
    @State private var symptoms: String
    @State private var error: String?
    @State private var saving = false
    @FocusState private var focus: Field?

    private enum Field { case activity, minutes, symptoms }
    private let id: UUID
    private let editing: Bool
    private let save: (ActivityEntry) async throws -> Void

    init(entry: ActivityEntry?, id: UUID, save: @escaping (ActivityEntry) async throws -> Void) {
        self.id = entry?.id ?? id
        editing = entry != nil
        self.save = save
        _activity = State(initialValue: entry?.activity ?? "")
        _startedAt = State(initialValue: entry?.startedAt ?? Date())
        _minutes = State(initialValue: entry.map { String($0.durationMinutes) } ?? "")
        _fatigue = State(initialValue: entry?.fatigue)
        _symptoms = State(initialValue: entry?.symptoms ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(secondary: "Activity") {
                    TextField("Activity name", text: $activity).focused($focus, equals: .activity)
                        .accessibilityIdentifier("activityName")
                    DatePicker("Started at", selection: $startedAt, displayedComponents: [.date, .hourAndMinute])
                    TextField("Duration in minutes", text: $minutes)
                        .keyboardType(.numberPad)
                        .focused($focus, equals: .minutes)
                        .accessibilityIdentifier("activityDuration")
                }
                Section {
                    Picker("Cognitive fatigue", selection: $fatigue) {
                        Text("Choose a rating").tag(Int?.none)
                        Text("0 · None").tag(Optional(0))
                        ForEach(1...4, id: \.self) { Text("\($0)").tag(Optional($0)) }
                        Text("5 · Very fatigued").tag(Optional(5))
                    }
                    .accessibilityIdentifier("activityFatigue")
                } footer: {
                    Text("How mentally fatigued did you feel by the end of the activity?")
                }
                Section(secondary: "Symptoms noticed") {
                    TextField("Symptoms (optional)", text: $symptoms, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($focus, equals: .symptoms)
                        .accessibilityIdentifier("activitySymptoms")
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .privacySensitive()
            .disabled(saving)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(editing ? "Edit activity" : "Log activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save", action: submit).disabled(saving).accessibilityIdentifier("saveActivity")
                }
            }
        }.interactiveDismissDisabled(saving)
    }

    private func submit() {
        let input = minutes.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = input.compactMap(\.wholeNumberValue)
        guard digits.count == input.count, digits.allSatisfy({ $0 < 10 }),
              let duration = Int(digits.map(String.init).joined()), duration > 0 else {
            error = "Enter a positive duration in whole minutes."
            return
        }
        guard let fatigue else { error = "Choose a cognitive fatigue rating."; return }
        let entry = ActivityEntry(id: id, activity: activity, startedAt: startedAt, durationMinutes: duration, fatigue: fatigue, symptoms: symptoms)
        do { try entry.validate() } catch { self.error = error.localizedDescription; return }
        focus = nil
        error = nil
        saving = true
        Task {
            defer { saving = false }
            do { try await save(entry); dismiss() }
            catch { self.error = error.localizedDescription }
        }
    }
}
