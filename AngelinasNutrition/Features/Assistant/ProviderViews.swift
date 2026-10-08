import SafariServices
import SwiftUI

/// "Which AI do you want to use?" – Claude, ChatGPT or Gemini.
struct ProviderPickerView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(AssistantStore.self) private var assistant
    @State private var connecting: AIProvider?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text(store.t("Избери своя AI", "Choose your AI"))
                    .font(.displayTitle)
                    .foregroundStyle(Theme.Palette.ink)
                    .padding(.top, Theme.Spacing.l)
                Text(store.t("Свържи акаунта си при доставчика и го ползвай директно в приложението. Плащаш само за това, което използваш, по своята сметка.",
                             "Connect your account with the provider and use it right here. You only pay for what you use, on your own account."))
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.inkSecondary)
                ForEach(AIProvider.allCases) { provider in
                    providerCard(provider)
                }
                Callout(title: store.t("Защо API ключ, а не абонамент?", "Why an API key, not my subscription?"),
                        items: [store.t("Claude Pro, ChatGPT Plus и Gemini Advanced не позволяват вход от други приложения. Всеки доставчик дава API ключ от конзолата си – свързваш го веднъж и той остава само на този телефон.",
                                        "Claude Pro, ChatGPT Plus and Gemini Advanced don't allow sign-in from other apps. Each provider gives you an API key from its console – connect it once and it stays only on this phone.")],
                        isWarning: false)
            }
            .padding(Theme.Spacing.l)
        }
        .sheet(item: $connecting) { provider in
            NavigationStack { ProviderConnectView(provider: provider) { connecting = nil } }
        }
    }

    private func providerCard(_ provider: AIProvider) -> some View {
        let isConnected = assistant.isConnected(provider)
        let isActive = assistant.provider == provider
        return Button {
            if isConnected { assistant.use(provider) } else { connecting = provider }
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: provider.systemImage)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(color(provider).gradient, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.title).font(.cardTitle).foregroundStyle(Theme.Palette.ink)
                    Text(isConnected ? "\(provider.company) · \(assistant.model(for: provider))" : provider.company)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isActive {
                    Tag(text: store.t("Активен", "In use"), tint: Theme.Palette.sage)
                } else if isConnected {
                    Tag(text: store.t("Свързан", "Connected"), tint: Theme.Palette.inkSecondary)
                } else {
                    Text(store.t("Свържи", "Connect")).font(.subheadline.weight(.semibold)).foregroundStyle(color(provider))
                }
            }
            .padding(Theme.Spacing.l)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .strokeBorder(isActive ? Theme.Palette.sage : Theme.Palette.hairline, lineWidth: isActive ? 2 : 1))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isConnected {
                Button(store.t("Смени модела / ключа", "Change model / key"), systemImage: "slider.horizontal.3") { connecting = provider }
                Button(store.t("Изключи", "Disconnect"), systemImage: "xmark.circle", role: .destructive) { assistant.disconnect(provider) }
            }
        }
    }

    func color(_ provider: AIProvider) -> Color {
        switch provider {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .openai: Color(red: 0.06, green: 0.64, blue: 0.5)
        case .gemini: Color(red: 0.26, green: 0.52, blue: 0.96)
        }
    }
}

/// Connect one provider: sign in to its console in the app to create a key, or paste one; then pick a model.
struct ProviderConnectView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(AssistantStore.self) private var assistant
    let provider: AIProvider
    var onDone: () -> Void = {}

    @State private var key = ""
    @State private var showConsole = false
    @State private var models: [String] = []
    @State private var model = ""
    @State private var checking = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Button { showConsole = true } label: {
                    Label(store.t("Влез в \(provider.consoleName) и създай ключ", "Sign in to \(provider.consoleName) and create a key"),
                          systemImage: "person.badge.key.fill")
                }
                Text(store.t("Отваря се тук в приложението. Влез с акаунта си, натисни „Create key“, копирай го и се върни.",
                             "Opens right here in the app. Sign in with your account, tap “Create key”, copy it and come back."))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            } header: {
                Text(store.t("Вариант 1 · Вход в акаунта", "Option 1 · Sign in to your account"))
            }
            Section {
                HStack {
                    SecureField(provider.keyPlaceholder, text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    Button(store.t("Постави", "Paste")) { key = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
                        .buttonStyle(.bordered)
                }
                Button(checking ? store.t("Проверявам…", "Checking…") : store.t("Провери ключа", "Check the key")) { Task { await check() } }
                    .disabled(!provider.looksLikeKey(key) || checking)
            } header: {
                Text(store.t("Вариант 2 · Постави ключ", "Option 2 · Paste a key"))
            } footer: {
                Text(store.t("Ключът се пази само в Keychain на този телефон и се изпраща единствено към \(provider.company).",
                             "The key is kept only in this phone's Keychain and sent only to \(provider.company)."))
            }
            if !models.isEmpty {
                Section(store.t("Модел", "Model")) {
                    Picker(store.t("Модел", "Model"), selection: $model) {
                        ForEach(models, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.navigationLink)
                    Button(store.t("Използвай \(provider.title)", "Use \(provider.title)")) {
                        assistant.connect(provider, key: key, model: model)
                        onDone()
                    }
                    .font(.headline)
                }
            }
            if let error { Section { Text(error).foregroundStyle(Theme.Palette.berry) } }
        }
        .navigationTitle(provider.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(store.t("Отказ", "Cancel")) { onDone() } } }
        .sheet(isPresented: $showConsole, onDismiss: pasteIfKey) { SafariView(url: provider.keysURL).ignoresSafeArea() }
        .onAppear {
            if let saved = ProviderKeys.load(provider) { key = saved; Task { await check() } }
        }
    }

    /// Coming back from the console: if a key was copied, fill it in.
    private func pasteIfKey() {
        if let copied = UIPasteboard.general.string, provider.looksLikeKey(copied), key.isEmpty {
            key = copied.trimmingCharacters(in: .whitespacesAndNewlines)
            Task { await check() }
        }
    }

    private func check() async {
        checking = true
        error = nil
        defer { checking = false }
        do {
            let list = try await ProviderModels.list(provider, key: key.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !list.isEmpty else {
                error = store.t("Ключът работи, но няма достъпни модели за чат.", "The key works, but no chat models are available.")
                return
            }
            // Claude: keep the recommended model first.
            models = provider == .claude && list.contains(ClaudeClient.model) ? [ClaudeClient.model] + list.filter { $0 != ClaudeClient.model } : list
            let saved = assistant.model(for: provider)
            model = models.contains(saved) ? saved : (ProviderModels.defaultModel(provider, from: models) ?? models[0])
        } catch {
            models = []
            self.error = error.localizedDescription
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
