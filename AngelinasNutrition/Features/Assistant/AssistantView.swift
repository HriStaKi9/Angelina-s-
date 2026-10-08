import SwiftUI

/// Conversation state, kept for the app session so closing the sheet doesn't lose the chat.
@Observable
final class AssistantStore {
    struct Message: Identifiable, Hashable {
        let id = UUID()
        let role: ClaudeClient.Turn.Role
        var text: String
        var note: String?
    }

    var messages: [Message] = []
    var isStreaming = false
    var error: String?
    private var task: Task<Void, Never>?

    /// Providers with a saved key.
    private(set) var connected: Set<AIProvider> = Set(AIProvider.allCases.filter { ProviderKeys.load($0) != nil })
    /// The provider the chat uses.
    private(set) var provider: AIProvider? = {
        let saved = UserDefaults.standard.string(forKey: "ai.provider").flatMap(AIProvider.init(rawValue:))
        let withKeys = AIProvider.allCases.filter { ProviderKeys.load($0) != nil }
        return saved.flatMap { withKeys.contains($0) ? $0 : nil } ?? withKeys.first
    }()

    /// True when a provider is connected and selected for the chat.
    var hasKey: Bool { provider != nil }

    func isConnected(_ provider: AIProvider) -> Bool { connected.contains(provider) }

    func model(for provider: AIProvider) -> String {
        UserDefaults.standard.string(forKey: "ai.model.\(provider.rawValue)") ?? (provider == .claude ? ClaudeClient.model : "")
    }

    func connect(_ provider: AIProvider, key: String, model: String) {
        ProviderKeys.save(key, for: provider)
        UserDefaults.standard.set(model, forKey: "ai.model.\(provider.rawValue)")
        connected.insert(provider)
        use(provider)
    }

    func use(_ provider: AIProvider) {
        guard connected.contains(provider) else { return }
        if self.provider != provider { reset() }
        self.provider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: "ai.provider")
    }

    func disconnect(_ provider: AIProvider) {
        ProviderKeys.delete(provider)
        connected.remove(provider)
        if self.provider == provider {
            reset()
            self.provider = connected.sorted { $0.rawValue < $1.rawValue }.first
        }
    }

    /// Kept for the Claude key screen used by the PDF importer.
    func saveKey(_ key: String) {
        connect(.claude, key: key, model: ClaudeClient.model)
    }

    func removeKey() {
        if let provider { disconnect(provider) }
    }

    func reset() {
        task?.cancel()
        messages = []
        error = nil
        isStreaming = false
    }

    func stop() { task?.cancel() }

    func send(_ text: String, stablePrompt: String, context: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isStreaming, let provider, let key = ProviderKeys.load(provider) else { return }
        let model = model(for: provider)
        error = nil
        messages.append(Message(role: .user, text: question))
        // Only completed text turns are sent back; the conversation is append-only.
        let turns = messages.filter { !$0.text.isEmpty }.map { ClaudeClient.Turn(role: $0.role, text: $0.text) }
        messages.append(Message(role: .assistant, text: ""))
        let replyID = messages[messages.count - 1].id
        isStreaming = true

        task = Task { @MainActor in
            defer { isStreaming = false }
            // Look the reply up by id: "New chat" may clear the list while a reply is still streaming.
            func update(_ change: (inout Message) -> Void) {
                if let i = messages.firstIndex(where: { $0.id == replyID }) { change(&messages[i]) }
            }
            var failed = false
            do {
                for try await event in ChatBackend.stream(provider: provider, model: model, key: key, stablePrompt: stablePrompt,
                                                          context: context, turns: turns) {
                    switch event {
                    case .text(let chunk):
                        update { $0.text += chunk }
                    case .model(let served) where provider == .claude && served != ClaudeClient.model:
                        update { $0.note = "Answered by \(served)" }
                    case .stop(let reason) where reason == "refusal":
                        update { $0.note = "\(provider.title) declined to answer this one." }
                    case .stop(let reason) where reason == "max_tokens":
                        update { $0.note = "The answer was cut off." }
                    default:
                        break
                    }
                }
            } catch is CancellationError {
                update { $0.note = "Stopped." }
            } catch {
                if (error as? URLError)?.code == .cancelled {
                    update { $0.note = "Stopped." }
                } else {
                    failed = true
                    self.error = error.localizedDescription
                }
            }
            // An empty reply can't be sent back as history: drop it (and the unanswered question after an error).
            if let i = messages.firstIndex(where: { $0.id == replyID }), messages[i].text.isEmpty {
                messages.remove(at: i)
                if failed, i > 0, messages[i - 1].role == .user { messages.remove(at: i - 1) }
            }
        }
    }
}

struct AssistantView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(TrainingLog.self) private var log
    @Environment(WeekMenuStore.self) private var menus
    @Environment(AssistantStore.self) private var assistant
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var choosingProvider = false
    @FocusState private var inputFocused: Bool

    private var plan: PersonalPlan? { store.activePlan }
    private var tint: Color { plan?.accentColor ?? Theme.Palette.berry }

    var body: some View {
        NavigationStack {
            Group {
                if assistant.hasKey {
                    chat
                } else {
                    ProviderPickerView()
                }
            }
            .background(Theme.Palette.background.ignoresSafeArea())
            .navigationTitle(assistant.provider?.title ?? "AI")
            .sheet(isPresented: $choosingProvider) {
                NavigationStack {
                    ProviderPickerView()
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(store.t("Готово", "Done")) { choosingProvider = false } } }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.t("Затвори", "Close")) { dismiss() } }
                if assistant.hasKey {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button(store.t("Нов разговор", "New chat"), systemImage: "square.and.pencil") { assistant.reset() }
                            Menu(store.t("Смени AI", "Switch AI")) {
                                ForEach(AIProvider.allCases) { provider in
                                    Button {
                                        if assistant.isConnected(provider) { assistant.use(provider) } else { choosingProvider = true }
                                    } label: {
                                        if assistant.provider == provider { Label(provider.title, systemImage: "checkmark") } else { Text(provider.title) }
                                    }
                                }
                                Button(store.t("Управление…", "Manage…"), systemImage: "slider.horizontal.3") { choosingProvider = true }
                            }
                            if let provider = assistant.provider {
                                Button(store.t("Изключи \(provider.title)", "Disconnect \(provider.title)"), systemImage: "key.slash", role: .destructive) {
                                    assistant.disconnect(provider)
                                }
                            }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
        }
    }

    private var chat: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    if assistant.messages.isEmpty { welcome }
                    ForEach(assistant.messages) { message in
                        bubble(message).id(message.id)
                    }
                    if let error = assistant.error {
                        Callout(title: store.t("Грешка", "Something went wrong"), items: [error], isWarning: true)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(Theme.Spacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: assistant.messages.last?.text) { proxy.scrollTo("bottom", anchor: .bottom) }
            .safeAreaInset(edge: .bottom) { inputBar }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(tint)
            Text(plan == nil
                 ? store.t("Питай за хранене и тренировки.", "Ask about nutrition and training.")
                 : store.t("\(assistant.provider?.title ?? "AI") знае режима и програмата на \(plan!.name.bg), днешното меню и последните ти тренировки.",
                           "Claude knows \(plan!.name.en)'s eating plan and program, today's menu and your recent workouts."))
                .font(.body)
                .foregroundStyle(Theme.Palette.ink)
            ForEach(suggestions, id: \.self) { suggestion in
                Button { send(suggestion) } label: {
                    Text(suggestion)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(Theme.Palette.ink)
                        .padding(Theme.Spacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).strokeBorder(Theme.Palette.hairline))
                }
                .buttonStyle(.plain)
            }
            Text(store.t("\(assistant.provider.map { "\($0.title) · \(assistant.model(for: $0))" } ?? "") – по твоя ключ; разговорите се таксуват по сметката ти.",
                         "\(assistant.provider.map { "\($0.title) · \(assistant.model(for: $0))" } ?? "") – your own key; chats are billed to your account."))
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSecondary)
        }
        .padding(.top, Theme.Spacing.l)
    }

    private var suggestions: [String] {
        guard plan != nil else {
            return [store.t("Какво да ям преди тренировка?", "What should I eat before a workout?")]
        }
        return [
            store.t("С какво да сменя вечерята днес, за да остана в калориите?", "What can I swap tonight's dinner for and stay within my calories?"),
            store.t("Пропуснах тренировка – как да подредя седмицата?", "I missed a workout – how should I rearrange the week?"),
            store.t("Обясни ми двойната прогресия с моите тежести.", "Explain double progression using my weights."),
            store.t("Как вървя спрямо целта според check-in-ите?", "How am I doing against the goal based on my check-ins?"),
        ]
    }

    private func bubble(_ message: AssistantStore.Message) -> some View {
        let isUser = message.role == .user
        return HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                if message.text.isEmpty && assistant.isStreaming {
                    ProgressView().padding(.vertical, 4)
                } else {
                    Text(Self.markdown(message.text))
                        .font(.body)
                        .foregroundStyle(isUser ? Theme.Palette.onAccent : Theme.Palette.ink)
                        .textSelection(.enabled)
                }
                if let note = message.note {
                    Text(note).font(.caption).foregroundStyle(isUser ? Theme.Palette.onAccent.opacity(0.8) : Theme.Palette.inkSecondary)
                }
            }
            .padding(Theme.Spacing.m)
            .background(isUser ? tint : Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            if !isUser { Spacer(minLength: 24) }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.s) {
            TextField(store.t("Попитай нещо…", "Ask something…"), text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, 10)
                .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.Palette.hairline))
            Button {
                if assistant.isStreaming { assistant.stop() } else { send(draft) }
            } label: {
                Image(systemName: assistant.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(tint)
            }
            .disabled(!assistant.isStreaming && draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel(assistant.isStreaming ? store.t("Спри", "Stop") : store.t("Изпрати", "Send"))
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
        .background(.bar)
    }

    private func send(_ text: String) {
        assistant.send(text, stablePrompt: AssistantPrompt.stable(plan: plan, training: store.trainingPlan, menus: menus),
                       context: PlanSummary.todayContext(plan: plan, store: store, log: log, menus: menus))
        draft = ""
    }

    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

enum AssistantPrompt {
    /// Stable part of the system prompt: role plus the full plan. Kept byte-identical between messages so it caches.
    static func stable(plan: PersonalPlan?, training: PersonalPlan?, menus: WeekMenuStore) -> String {
        var out = """
        You are the assistant inside "Angelina's Nutrition", an iPhone app for following a coach-written eating plan and training program.

        Ground your answers in the plan below: suggest swaps from the plan's own meal options (with kcal and protein), work out portions and grocery amounts, explain exercises, weights and the progression rules, and read check-ins against the plan's adjustment tables. If something isn't covered by the plan, you can still help, keeping to its daily targets and rules.

        For pain, pelvic-floor or abdominal symptoms, medicines and supplements (especially while breastfeeding), say what the plan says and recommend the doctor or physiotherapist, as the plan itself does.

        Reply in the language the user writes in (the plan is written in Bulgarian). Answers are read on a phone: keep them short and practical, with brief lists where useful.
        """
        if let plan {
            out += "\n\n=== EATING PLAN ===\n"
            out += PlanSummary.nutrition(plan, week: plan.nutrition.week, language: .bg, includeSteps: true)
        }
        if let program = training ?? plan, !program.training.workouts.isEmpty {
            out += "\n\n=== TRAINING PROGRAM ===\n"
            out += PlanSummary.training(program, language: .bg)
        }
        return out
    }
}

/// Key entry: the user's own Anthropic API key, saved to the Keychain.
struct APIKeySetupView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(AssistantStore.self) private var assistant
    @State private var key = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Image(systemName: "key.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.Palette.berry)
                    .padding(.top, Theme.Spacing.xl)
                Text(store.t("Свържи своя Claude акаунт", "Connect your Claude account"))
                    .font(.displayTitle)
                    .foregroundStyle(Theme.Palette.ink)
                Text(store.t("Постави API ключ от console.anthropic.com → API Keys. Ключът се пази само в Keychain на този телефон и се изпраща единствено към Anthropic.",
                             "Paste an API key from console.anthropic.com → API Keys. It's stored only in this phone's Keychain and sent only to Anthropic."))
                    .font(.body)
                    .foregroundStyle(Theme.Palette.inkSecondary)
                SecureField("sk-ant-…", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .padding(Theme.Spacing.l)
                    .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).strokeBorder(Theme.Palette.hairline))
                Button(store.t("Запази ключа", "Save key")) {
                    assistant.saveKey(key)
                    key = ""
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!key.hasPrefix("sk-ant-"))
                .opacity(key.hasPrefix("sk-ant-") ? 1 : 0.5)
                Link(store.t("Отвори Claude Console", "Open Claude Console"),
                     destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(Theme.Spacing.l)
        }
    }
}

/// Adds the ✨ "Ask Claude" button to a screen's navigation bar.
struct AskClaudeToolbar: ViewModifier {
    @Environment(ProfileStore.self) private var store
    /// Debug builds accept `-openAssistant YES` to open the chat at launch, for simulator screenshots.
    @State private var isPresented = UserDefaults.standard.bool(forKey: "openAssistant") && _isDebugAssertConfiguration()

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { isPresented = true } label: {
                        Image(systemName: "sparkles")
                    }
                    .accessibilityLabel(store.t("Попитай Claude", "Ask Claude"))
                }
            }
            .sheet(isPresented: $isPresented) { AssistantView() }
    }
}

extension View {
    func askClaudeButton() -> some View { modifier(AskClaudeToolbar()) }
}
