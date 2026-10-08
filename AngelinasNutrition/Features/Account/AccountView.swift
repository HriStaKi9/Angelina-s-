import SwiftUI

/// Sign in / create an account (email + password via Supabase) and back up or restore the phone's data.
struct AccountView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(TrainingLog.self) private var log
    @Environment(WeekMenuStore.self) private var menus
    @Environment(FoodDiaryStore.self) private var diary
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var message: String?
    @State private var error: String?
    @State private var pendingBackup: [String: Any]?
    @State private var configured = SupabaseConfig.isConfigured

    var body: some View {
        NavigationStack {
            Form {
                if !configured {
                    SupabaseSetupSection { configured = SupabaseConfig.isConfigured }
                } else if let session = account.session {
                    signedIn(session)
                } else {
                    signInForm
                }
                if let message { Section { Text(message).foregroundStyle(Theme.Palette.sage) } }
                if let error { Section { Text(error).foregroundStyle(Theme.Palette.berry) } }
            }
            .disabled(account.isBusy)
            .overlay { if account.isBusy { ProgressView().controlSize(.large) } }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Your account has saved data", isPresented: Binding(get: { pendingBackup != nil }, set: { if !$0 { pendingBackup = nil } }),
                                titleVisibility: .visible) {
                Button("Restore it to this phone") {
                    if let backup = pendingBackup { restore(backup) }
                    pendingBackup = nil
                }
                Button("Keep this phone's data and upload it", role: .destructive) {
                    pendingBackup = nil
                    Task { await backUp() }
                }
            } message: {
                Text("Restoring replaces the plan choice, diary, workouts and check-ins on this phone.")
            }
        }
    }

    private var signInForm: some View {
        Group {
            Section {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password (8+ characters)", text: $password)
                    .textContentType(.password)
            } header: {
                Text("Sign in or create an account")
            } footer: {
                Text("Your diary, workouts, check-ins, week menu, imported plans and settings are backed up to your account, so you can restore them on a new phone. Each person signs in with their own email.")
            }
            Section {
                Button("Sign in") { run { try await account.signIn(email: email, password: password); await afterSignIn() } }
                    .disabled(!formValid)
                Button("Create account") {
                    run {
                        do {
                            try await account.signUp(email: email, password: password)
                            await afterSignIn()
                        } catch SupabaseClient.ClientError.confirmEmail {
                            message = "Account created. Open the confirmation email, tap the link, then come back and sign in."
                        }
                    }
                }
                .disabled(!formValid)
                Button("Forgot password") {
                    run {
                        try await account.resetPassword(email: email)
                        message = "If that email has an account, a reset link is on its way."
                    }
                }
                .disabled(!email.contains("@"))
            }
        }
    }

    private func signedIn(_ session: AuthSession) -> some View {
        Group {
            Section {
                Label(session.email, systemImage: "person.crop.circle.badge.checkmark")
                if let last = account.lastSynced {
                    LabeledContent("Last backup", value: last.formatted(.relative(presentation: .named)))
                }
            } footer: {
                Text("The app also backs up automatically when you leave it.")
            }
            Section {
                Button("Back up now", systemImage: "icloud.and.arrow.up") { run { await backUp() } }
                Button("Restore from account", systemImage: "icloud.and.arrow.down") {
                    run {
                        let (client, session) = try await account.validSession()
                        if let backup = try await client.fetchBackup(session) { pendingBackup = backup.data } else { message = "No backup in this account yet." }
                    }
                }
            }
            Section {
                Button("Sign out", role: .destructive) { run { await account.signOut() } }
            }
        }
    }

    private var formValid: Bool { email.contains("@") && password.count >= 8 }

    private func run(_ work: @escaping () async throws -> Void) {
        error = nil
        message = nil
        account.isBusy = true
        Task {
            defer { account.isBusy = false }
            do { try await work() } catch { self.error = error.localizedDescription }
        }
    }

    /// After signing in: offer to restore if the account already has data, otherwise upload this phone's data.
    private func afterSignIn() async {
        password = ""
        do {
            let (client, session) = try await account.validSession()
            if let backup = try await client.fetchBackup(session) {
                pendingBackup = backup.data
            } else {
                await backUp()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func backUp() async {
        do {
            try await AccountSync.backUp(account: account, profile: store, log: log, menus: menus, diary: diary)
            message = "Backed up."
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func restore(_ backup: [String: Any]) {
        AccountBackup.apply(backup, profile: store, log: log, menus: menus, diary: diary, library: .shared)
        account.lastSynced = .now
        message = "Restored from your account."
    }
}

enum AccountSync {
    static func backUp(account: AccountStore, profile: ProfileStore, log: TrainingLog, menus: WeekMenuStore, diary: FoodDiaryStore) async throws {
        let (client, session) = try await account.validSession()
        try await client.saveBackup(AccountBackup.make(profile: profile, log: log, menus: menus, diary: diary, library: .shared), session: session)
        account.lastSynced = .now
    }
}

/// One-time connection to the user's Supabase project, with the SQL to run there.
struct SupabaseSetupSection: View {
    let onSave: () -> Void
    @State private var url = SupabaseConfig.url
    @State private var key = SupabaseConfig.anonKey

    static let sql = """
    create table public.user_data (
      user_id uuid primary key references auth.users on delete cascade,
      data jsonb not null,
      updated_at timestamptz not null default now()
    );
    alter table public.user_data enable row level security;
    create policy "read own" on public.user_data for select using (auth.uid() = user_id);
    create policy "insert own" on public.user_data for insert with check (auth.uid() = user_id);
    create policy "update own" on public.user_data for update using (auth.uid() = user_id);
    """

    var body: some View {
        Section {
            TextField("Project URL (https://….supabase.co)", text: $url)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("anon public key", text: $key, axis: .vertical)
                .lineLimit(1...3)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.caption.monospaced())
            Button("Save") {
                SupabaseConfig.set(url: url, anonKey: key)
                onSave()
            }
            .disabled(URL(string: url)?.host == nil || key.count < 20)
        } header: {
            Text("Connect accounts")
        } footer: {
            Text("1. Create a free project at supabase.com.\n2. SQL Editor → run the script below (copy button).\n3. Project Settings → API → paste the Project URL and the anon public key here.")
        }
        Section("Database script") {
            Text(Self.sql)
                .font(.caption2.monospaced())
                .textSelection(.enabled)
            Button("Copy script", systemImage: "doc.on.doc") { UIPasteboard.general.string = Self.sql }
        }
    }
}
