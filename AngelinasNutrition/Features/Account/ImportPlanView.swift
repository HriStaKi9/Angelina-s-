import SwiftUI
import UniformTypeIdentifiers
import PDFKit

/// Import an eating plan from a PDF: Claude reads it and fills the app's plan structure.
struct ImportPlanView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(AssistantStore.self) private var assistant
    @Environment(\.dismiss) private var dismiss

    enum Phase: Equatable { case choose, reading, preview, failed(String) }

    @State private var phase: Phase = .choose
    @State private var pickingFile = false
    @State private var pdf: Data?
    @State private var fileName = ""
    @State private var pageCount = 0
    @State private var target: PlanImporter.Target = .newPerson("")
    @State private var newName = ""
    @State private var received = 0
    @State private var started = Date.now
    @State private var result: PersonalPlan?
    @State private var task: Task<Void, Never>?

    private var library: PlanLibrary { .shared }

    var body: some View {
        NavigationStack {
            Group {
                if !assistant.hasKey {
                    APIKeySetupView()
                } else {
                    switch phase {
                    case .choose: chooseForm
                    case .reading: reading
                    case .preview: preview
                    case .failed(let message): failed(message)
                    }
                }
            }
            .background(Theme.Palette.background.ignoresSafeArea())
            .navigationTitle("Import plan from PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { task?.cancel(); dismiss() }
                }
            }
            .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.pdf]) { picked in
                guard case .success(let url) = picked else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                pdf = try? Data(contentsOf: url)
                fileName = url.lastPathComponent
                pageCount = pdf.flatMap { PDFDocument(data: $0)?.pageCount } ?? 0
            }
        }
    }

    // MARK: Steps

    private var chooseForm: some View {
        Form {
            Section {
                Button { pickingFile = true } label: {
                    Label(pdf == nil ? "Choose a PDF" : fileName, systemImage: pdf == nil ? "doc.badge.plus" : "doc.richtext.fill")
                }
                if pdf != nil {
                    Text("\(pageCount) pages").font(.caption).foregroundStyle(Theme.Palette.inkSecondary)
                }
            } footer: {
                Text("An eating plan with meal options, ingredients and calories works best – like the coach's PDFs.")
            }
            Section("Use it for") {
                Picker("Use it for", selection: $target) {
                    Text("A new person").tag(PlanImporter.Target.newPerson(""))
                    ForEach(library.plans) { plan in
                        Text("Replace \(plan.name.en)'s eating plan").tag(PlanImporter.Target.replaceNutrition(plan.id))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                if case .newPerson = target {
                    TextField("Name (optional – taken from the PDF)", text: $newName)
                }
            }
            Section {
                Button { start() } label: {
                    Label("Read with Claude", systemImage: "sparkles")
                }
                .disabled(pdf == nil)
            } footer: {
                Text("Uses \(ClaudeClient.model) with your API key. A plan of about 10 pages takes a few minutes and costs roughly $0.30–1. The training program of a person whose eating plan you replace is kept.")
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var reading: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Claude is reading \(fileName)…").font(.headline).foregroundStyle(Theme.Palette.ink)
            TimelineView(.periodic(from: started, by: 1)) { context in
                Text("\(Duration.seconds(context.date.timeIntervalSince(started)).formatted(.time(pattern: .minuteSecond))) · \(received.formatted()) characters received")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
            Text("You can keep using the phone; don't close this screen.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSecondary)
            Button("Cancel", role: .cancel) { task?.cancel(); phase = .choose }
            Spacer()
        }
        .padding(Theme.Spacing.l)
    }

    private var preview: some View {
        Form {
            if let plan = result {
                let n = plan.nutrition
                Section("Found") {
                    LabeledContent("Person", value: plan.name.en)
                    LabeledContent("Plan", value: n.title.bg)
                    LabeledContent("Calories", value: "\(n.kcal.text) kcal")
                    LabeledContent("Protein", value: "\(n.protein.text) g")
                    ForEach(Meal.Course.allCases) { course in
                        LabeledContent(course.pluralTitle.en, value: "\(n.meals(for: course).count) options")
                    }
                    LabeledContent("Rules & notes", value: "\(n.sections.count) sections")
                }
                Section("First day of the week") {
                    if let day = n.week.first {
                        ForEach(day.meals(in: n)) { meal in
                            Text("\(meal.course.title.en): №\(meal.number) \(meal.name.bg)").font(.subheadline)
                        }
                    }
                }
                Section {
                    Button("Save and use this plan") { save(plan) }
                    Button("Try again", role: .cancel) { phase = .choose }
                } footer: {
                    Text("Check the numbers against the PDF – Claude can misread a value. You can re-import any time.")
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(Theme.Palette.apricot)
            Text(message).multilineTextAlignment(.center).foregroundStyle(Theme.Palette.ink)
            Button("Try again") { phase = .choose }.buttonStyle(PrimaryButtonStyle())
            Spacer()
        }
        .padding(Theme.Spacing.xl)
    }

    // MARK: Actions

    private func start() {
        guard let pdf, let key = APIKeyStore.load() else { return }
        let target: PlanImporter.Target = {
            if case .newPerson = self.target { return .newPerson(newName) }
            return self.target
        }()
        phase = .reading
        started = .now
        received = 0
        task = Task { @MainActor in
            var json = ""
            var stop: String?
            do {
                for try await event in ClaudeClient(apiKey: key).stream(body: PlanImporter.requestBody(pdf: pdf)) {
                    switch event {
                    case .text(let chunk):
                        json += chunk
                        received = json.count
                    case .stop(let reason):
                        stop = reason
                    case .model:
                        break
                    }
                }
                if stop == "refusal" { throw PlanImporter.ImportError.refused }
                if stop == "max_tokens" { throw PlanImporter.ImportError.truncated }
                let dto = try PlanImporter.parse(json)
                result = try PlanImporter.makePlan(dto, target: target)
                phase = .preview
            } catch is CancellationError {
                phase = .choose
            } catch {
                if (error as? URLError)?.code == .cancelled { phase = .choose } else { phase = .failed(error.localizedDescription) }
            }
        }
    }

    private func save(_ plan: PersonalPlan) {
        do {
            try library.save(plan)
            if store.profile.planID != plan.id { store.selectPlan(plan.id) }
            dismiss()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
