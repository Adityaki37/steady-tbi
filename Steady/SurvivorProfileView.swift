import SwiftUI

enum SymptomCategory: String, Codable, CaseIterable, Identifiable {
    case physical, movement, balance, tremor, cognitive, sensory, other

    var id: Self { self }
    var title: String { rawValue.capitalized }

    var suggestions: [String] {
        switch self {
        case .physical: return ["Headache", "Fatigue", "Nausea", "Muscle tension"]
        case .movement: return ["Slower movement", "Stiffness", "Weakness", "Trouble coordinating movements"]
        case .balance: return ["Dizziness", "Feeling unsteady", "Trouble walking straight", "Feeling off balance when standing"]
        case .tremor: return ["Shaky hands", "Shaky legs", "Head shaking", "Shaking during movement"]
        case .cognitive: return ["Trouble concentrating", "Mental fatigue", "Slower thinking", "Trouble finding words", "Forgetfulness"]
        case .sensory: return ["Light sensitivity", "Noise sensitivity", "Blurry vision", "Feeling overwhelmed in busy places"]
        case .other: return []
        }
    }
}

struct ProfileSymptom: Codable, Identifiable, Equatable {
    var id = UUID()
    let category: SymptomCategory
    let name: String
}

struct SurvivorProfile: Decodable, Equatable {
    var display_name = ""
    var injury_date: String?
    var injury_description = ""
    var injury_notes = ""
    var symptoms: [ProfileSymptom] = []

    static let symptomLimit = 50

    // Preserve the calendar day when a profile is opened in a different time zone.
    static var dateFormat: DateFormatter {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.calendar = Calendar(identifier: .gregorian)
        format.dateFormat = "yyyy-MM-dd"
        return format
    }
}

struct SharedSurvivorProfile: Decodable {
    let injury_date: String?
    let injury_description: String
    let injury_notes: String
    let symptoms: [ProfileSymptom]
}

struct SharedSurvivorProfileView: View {
    let profile: SharedSurvivorProfile

    var body: some View {
        DisclosureGroup("Injury details and ranked symptoms") {
            VStack(alignment: .leading, spacing: 12) {
                if let day = profile.injury_date.flatMap({ SurvivorProfile.dateFormat.date(from: $0) }) {
                    Text("Injury date \(day.formatted(date: .long, time: .omitted))")
                }
                if !profile.injury_description.isEmpty { Text(profile.injury_description) }
                if !profile.injury_notes.isEmpty { Text(profile.injury_notes) }
                if profile.injury_date == nil && profile.injury_description.isEmpty && profile.injury_notes.isEmpty {
                    Text("No injury details entered").foregroundStyle(Palette.secondaryText)
                }
                Text("Symptoms from first noticed to last").font(.headline).accessibilityAddTraits(.isHeader)
                if profile.symptoms.isEmpty {
                    Text("No symptoms entered").foregroundStyle(Palette.secondaryText)
                }
                ForEach(Array(profile.symptoms.enumerated()), id: \.element.id) { index, symptom in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(index + 1). \(symptom.name)")
                        Text(symptom.category.title).font(.caption).foregroundStyle(Palette.secondaryText)
                    }.accessibilityElement(children: .combine)
                }
            }.padding(.vertical, 8)
        }.privacySensitive()
    }
}

struct SurvivorProfileView: View {
    private enum Step: Int, CaseIterable {
        case details, symptoms, order

        var title: String {
            switch self {
            case .details: return "About you"
            case .symptoms: return "Choose your symptoms"
            case .order: return "Put symptoms in order"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.timeZone) private var timeZone
    @State private var draft: SurvivorProfile
    @State private var showingInjuryDate = false
    @State private var pendingInjuryDate = Date.now
    @State private var step = Step.details
    @State private var expandedCategory: SymptomCategory?
    @State private var customSymptom = ""
    @State private var saving = false
    @State private var error: String?

    let isNew: Bool
    let save: (SurvivorProfile) async throws -> Void

    init(profile: SurvivorProfile?, save: @escaping (SurvivorProfile) async throws -> Void) {
        _draft = State(initialValue: profile ?? SurvivorProfile())
        isNew = profile == nil
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                if step != .details {
                    Section {
                        Text(step.title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    } header: {
                        stepProgress
                    }
                }
                switch step {
                case .details: details
                case .symptoms: symptoms
                case .order: order
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    if step == .order {
                        Button(saving ? "Saving…" : "Save profile", action: saveProfile).disabled(saving)
                    } else {
                        Button(step == .details ? "Continue to symptoms" : "Continue to symptom order") {
                            advance()
                        }.disabled(step == .details && !canContinueFromDetails)
                    }
                }
            }
            .id(step)
            .privacySensitive()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(step == .details ? step.title : "Survivor profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step == .details {
                        Button(isNew ? "Later" : "Cancel") { dismiss() }
                    } else {
                        Button("Back") {
                            error = nil
                            step = Step(rawValue: step.rawValue - 1) ?? .details
                        }.disabled(saving)
                    }
                }
            }
        }.interactiveDismissDisabled(saving)
    }

    private var name: String { draft.display_name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canContinueFromDetails: Bool {
        !name.isEmpty && name.unicodeScalars.count <= 100 &&
        draft.injury_description.unicodeScalars.count <= 300 && draft.injury_notes.unicodeScalars.count <= 1000
    }

    private var stepProgress: some View {
        Text("Step \(step.rawValue + 1) of \(Step.allCases.count)")
    }

    private var details: some View {
        Group {
            Section {
                TextField("Your name", text: $draft.display_name).textContentType(.name)
                if name.unicodeScalars.count > 100 { Text("Use up to 100 characters.").foregroundStyle(.red) }
            } header: {
                stepProgress
            }
            Section("Your injury") {
                injuryDateRow
                TextField("Injury type or diagnosis (optional)", text: $draft.injury_description, axis: .vertical)
                    .lineLimit(1...3)
                if draft.injury_description.unicodeScalars.count > 300 { Text("Use up to 300 characters.").foregroundStyle(.red) }
                TextField("Anything else about the injury? (optional)", text: $draft.injury_notes, axis: .vertical)
                    .lineLimit(2...5)
                if draft.injury_notes.unicodeScalars.count > 1000 { Text("Use up to 1,000 characters.").foregroundStyle(.red) }
            }
        }
    }

    private var injuryDateRow: some View {
        let format = SurvivorProfile.dateFormat
        format.timeZone = timeZone
        let selectedDate = draft.injury_date.flatMap { format.date(from: $0) }
        let displayFormat = Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: timeZone)
        let dateLabel = selectedDate?.formatted(displayFormat) ?? "Select date"

        return Button {
            pendingInjuryDate = selectedDate ?? .now
            showingInjuryDate = true
        } label: {
            HStack {
                Text("Injury date")
                Spacer()
                Text(dateLabel)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Injury date")
        .accessibilityValue(dateLabel)
        .popover(isPresented: $showingInjuryDate) {
            VStack {
                DatePicker("Injury date", selection: $pendingInjuryDate, in: ...Date.now, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                HStack {
                    if selectedDate != nil {
                        Button("Clear date") {
                            draft.injury_date = nil
                            showingInjuryDate = false
                        }
                    }
                    Spacer()
                    Button("Use date") {
                        draft.injury_date = format.string(from: pendingInjuryDate)
                        showingInjuryDate = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(idealWidth: 320)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var symptoms: some View {
        Group {
            Section {
                Text("Choose the symptoms you notice. You can add your own under Other or continue with an empty list.")
                Text("\(draft.symptoms.count) selected").foregroundStyle(Palette.secondaryText)
            }
            Section("Symptom categories") {
                ForEach(SymptomCategory.allCases) { category in
                    DisclosureGroup(category.title, isExpanded: Binding(
                        get: { expandedCategory == category },
                        set: { expandedCategory = $0 ? category : nil }
                    )) {
                        if category == .other {
                            ForEach(draft.symptoms.filter { $0.category == .other }) { symptom in
                                symptomToggle(symptom.name, category: .other)
                            }
                            TextField("Add a symptom in your own words", text: $customSymptom)
                                .onSubmit(addCustomSymptom)
                            Button("Add symptom", action: addCustomSymptom).disabled(!canAddCustomSymptom)
                        } else {
                            ForEach(category.suggestions, id: \.self) { symptom in
                                symptomToggle(symptom, category: category)
                            }
                        }
                    }
                }
            }
            if draft.symptoms.count == SurvivorProfile.symptomLimit {
                Section { Text("You can keep up to \(SurvivorProfile.symptomLimit) symptoms. Remove one to add another.") }
            }
        }
    }

    private func symptomToggle(_ name: String, category: SymptomCategory) -> some View {
        let selected = draft.symptoms.first { $0.name == name && $0.category == category }
        return Toggle(name, isOn: Binding(
            get: { draft.symptoms.contains { $0.name == name && $0.category == category } },
            set: { isOn in
                if isOn {
                    guard draft.symptoms.count < SurvivorProfile.symptomLimit,
                          !draft.symptoms.contains(where: { $0.name == name && $0.category == category }) else { return }
                    draft.symptoms.append(ProfileSymptom(category: category, name: name))
                } else {
                    draft.symptoms.removeAll { $0.name == name && $0.category == category }
                }
            }
        )).disabled(selected == nil && draft.symptoms.count >= SurvivorProfile.symptomLimit)
    }

    private var customName: String { customSymptom.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canAddCustomSymptom: Bool {
        !customName.isEmpty && customName.unicodeScalars.count <= 80 && draft.symptoms.count < SurvivorProfile.symptomLimit &&
        !draft.symptoms.contains { $0.name.caseInsensitiveCompare(customName) == .orderedSame }
    }

    private func addCustomSymptom() {
        guard canAddCustomSymptom else { return }
        draft.symptoms.append(ProfileSymptom(category: .other, name: customName))
        customSymptom = ""
    }

    private var order: some View {
        Section {
            if draft.symptoms.isEmpty {
                Text("You haven’t selected any symptoms. You can add them later in your survivor profile.")
            } else {
                ForEach(draft.symptoms.indices, id: \.self) { index in
                    let symptom = draft.symptoms[index]
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(index + 1). \(symptom.name)")
                            Text(symptom.category.title).font(.caption).foregroundStyle(Palette.secondaryText)
                        }
                        Spacer()
                        if draft.symptoms.count > 1 {
                            moveButton(symptom, at: index, by: -1)
                            moveButton(symptom, at: index, by: 1)
                        }
                    }
                }
            }
        } header: {
            Text("First noticed to last noticed")
        } footer: {
            Text("Use the arrows to put the symptom you usually notice first at the top. This is your own estimate.")
        }
    }

    private func moveButton(_ symptom: ProfileSymptom, at index: Int, by offset: Int) -> some View {
        let direction = offset < 0 ? "up" : "down"
        let next = index + offset
        return Button {
            guard draft.symptoms.indices.contains(index), draft.symptoms.indices.contains(next) else { return }
            draft.symptoms.swapAt(index, next)
        } label: {
            Image(systemName: "arrow.\(direction)").frame(minWidth: 44, minHeight: 44)
        }.buttonStyle(.borderless)
            .accessibilityLabel("Move \(symptom.name) \(direction)")
            .disabled(saving || !draft.symptoms.indices.contains(next))
    }

    private func advance() {
        if step == .symptoms { addCustomSymptom() }
        step = Step(rawValue: step.rawValue + 1) ?? .order
    }

    private func saveProfile() {
        draft.display_name = name
        draft.injury_description = draft.injury_description.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.injury_notes = draft.injury_notes.trimmingCharacters(in: .whitespacesAndNewlines)
        saving = true
        error = nil
        Task {
            defer { saving = false }
            do {
                try await save(draft)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
