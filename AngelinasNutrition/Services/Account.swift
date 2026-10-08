import Foundation
import Observation
import Security

/// Where accounts live: the user's own Supabase project. The anon key is public by design;
/// row-level security on `user_data` keeps each person's data private.
enum SupabaseConfig {
    /// Set these once the project exists (Supabase → Project Settings → API), or enter them in the app.
    static let builtInURL = ""
    static let builtInAnonKey = ""

    static var url: String { UserDefaults.standard.string(forKey: "supabase.url").flatMap { $0.isEmpty ? nil : $0 } ?? builtInURL }
    static var anonKey: String { UserDefaults.standard.string(forKey: "supabase.anonKey").flatMap { $0.isEmpty ? nil : $0 } ?? builtInAnonKey }
    static var isConfigured: Bool { URL(string: url)?.host != nil && !anonKey.isEmpty }

    static func set(url: String, anonKey: String) {
        UserDefaults.standard.set(url.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")), forKey: "supabase.url")
        UserDefaults.standard.set(anonKey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "supabase.anonKey")
    }
}

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let userID: String
    let email: String
}

/// Generic-password Keychain item holding a Codable value.
struct KeychainItem<Value: Codable> {
    let service: String
    let account: String

    func load() -> Value? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    func save(_ value: Value) {
        delete()
        guard let data = try? JSONEncoder().encode(value) else { return }
        let attributes: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                         kSecAttrAccount as String: account,
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                         kSecValueData as String: data]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func delete() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}

/// Minimal Supabase client over REST: Auth (GoTrue) for accounts, PostgREST for the backup row.
struct SupabaseClient {
    enum ClientError: LocalizedError {
        case notConfigured
        case server(status: Int, message: String)
        case confirmEmail

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Accounts aren't set up yet."
            case .server(_, let message): message
            case .confirmEmail: "Check your email and tap the confirmation link, then sign in."
            }
        }
    }

    let baseURL: String
    let anonKey: String

    static var current: SupabaseClient? {
        SupabaseConfig.isConfigured ? SupabaseClient(baseURL: SupabaseConfig.url, anonKey: SupabaseConfig.anonKey) : nil
    }

    // MARK: Auth

    func signUp(email: String, password: String) async throws -> AuthSession? {
        let json = try await send("auth/v1/signup", body: ["email": email, "password": password])
        // With "Confirm email" on (Supabase's default) there's no session until the link is tapped.
        return Self.session(from: json)
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        let json = try await send("auth/v1/token?grant_type=password", body: ["email": email, "password": password])
        guard let session = Self.session(from: json) else { throw ClientError.server(status: 0, message: "No session returned.") }
        return session
    }

    func refresh(_ session: AuthSession) async throws -> AuthSession {
        let json = try await send("auth/v1/token?grant_type=refresh_token", body: ["refresh_token": session.refreshToken])
        guard let fresh = Self.session(from: json) else { throw ClientError.server(status: 0, message: "Couldn't refresh the session.") }
        return fresh
    }

    func sendPasswordReset(email: String) async throws {
        _ = try await send("auth/v1/recover", body: ["email": email])
    }

    func signOut(_ session: AuthSession) async {
        _ = try? await send("auth/v1/logout", body: [:], token: session.accessToken)
    }

    // MARK: Backup row

    func fetchBackup(_ session: AuthSession) async throws -> (data: [String: Any], updatedAt: String)? {
        var request = try makeRequest("rest/v1/user_data?select=data,updated_at&user_id=eq.\(session.userID)", token: session.accessToken)
        request.httpMethod = "GET"
        let result = try await perform(request)
        guard let row = (result as? [[String: Any]])?.first, let data = row["data"] as? [String: Any] else { return nil }
        return (data, row["updated_at"] as? String ?? "")
    }

    func saveBackup(_ data: [String: Any], session: AuthSession) async throws {
        var request = try makeRequest("rest/v1/user_data?on_conflict=user_id", token: session.accessToken)
        request.httpMethod = "POST"
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "user_id": session.userID,
            "data": data,
            "updated_at": ISO8601DateFormatter().string(from: .now),
        ])
        _ = try await perform(request)
    }

    // MARK: Plumbing

    private func send(_ path: String, body: [String: Any], token: String? = nil) async throws -> [String: Any] {
        var request = try makeRequest(path, token: token)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return (try await perform(request) as? [String: Any]) ?? [:]
    }

    private func makeRequest(_ path: String, token: String?) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/\(path)") else { throw ClientError.notConfigured }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token ?? anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Any? {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = data.isEmpty ? nil : try? JSONSerialization.jsonObject(with: data)
        guard (200..<300).contains(status) else {
            let body = json as? [String: Any]
            let message = (body?["msg"] ?? body?["message"] ?? body?["error_description"] ?? body?["error"]) as? String
            throw ClientError.server(status: status, message: message ?? "Server error \(status)")
        }
        return json
    }

    static func session(from json: [String: Any]) -> AuthSession? {
        guard let access = json["access_token"] as? String, let refresh = json["refresh_token"] as? String,
              let user = json["user"] as? [String: Any], let id = user["id"] as? String else { return nil }
        let expiresIn = (json["expires_in"] as? Double) ?? (json["expires_in"] as? Int).map(Double.init) ?? 3600
        return AuthSession(accessToken: access, refreshToken: refresh, expiresAt: .now.addingTimeInterval(expiresIn - 60),
                           userID: id, email: user["email"] as? String ?? "")
    }
}

/// Signed-in state plus backup/restore of everything on the phone.
@Observable
final class AccountStore {
    private static let keychain = KeychainItem<AuthSession>(service: "com.hristomir.angelinasnutrition.account", account: "session")

    private(set) var session: AuthSession? = AccountStore.keychain.load()
    var lastSynced: Date? = UserDefaults.standard.object(forKey: "account.lastSynced") as? Date {
        didSet { UserDefaults.standard.set(lastSynced, forKey: "account.lastSynced") }
    }
    var isBusy = false

    var isSignedIn: Bool { session != nil }

    func signUp(email: String, password: String) async throws {
        guard let client = SupabaseClient.current else { throw SupabaseClient.ClientError.notConfigured }
        guard let session = try await client.signUp(email: email, password: password) else {
            throw SupabaseClient.ClientError.confirmEmail
        }
        setSession(session)
    }

    func signIn(email: String, password: String) async throws {
        guard let client = SupabaseClient.current else { throw SupabaseClient.ClientError.notConfigured }
        setSession(try await client.signIn(email: email, password: password))
    }

    func resetPassword(email: String) async throws {
        guard let client = SupabaseClient.current else { throw SupabaseClient.ClientError.notConfigured }
        try await client.sendPasswordReset(email: email)
    }

    func signOut() async {
        if let session, let client = SupabaseClient.current { await client.signOut(session) }
        setSession(nil)
        lastSynced = nil
    }

    /// A session with a fresh access token (refreshing it if it's about to expire).
    func validSession() async throws -> (SupabaseClient, AuthSession) {
        guard let client = SupabaseClient.current, var session else { throw SupabaseClient.ClientError.notConfigured }
        if session.expiresAt < .now {
            session = try await client.refresh(session)
            setSession(session)
        }
        return (client, session)
    }

    private func setSession(_ session: AuthSession?) {
        self.session = session
        if let session { Self.keychain.save(session) } else { Self.keychain.delete() }
    }
}

/// Builds and applies the account backup: profile, imported plans, workouts, check-ins, week menus, diary.
enum AccountBackup {
    static let version = 1

    static func make(profile: ProfileStore, log: TrainingLog, menus: WeekMenuStore, diary: FoodDiaryStore, library: PlanLibrary) -> [String: Any] {
        func object(_ data: Data) -> Any { (try? JSONSerialization.jsonObject(with: data)) ?? [:] }
        let encoder = JSONEncoder()
        return [
            "version": version,
            "savedAt": ISO8601DateFormatter().string(from: .now),
            "profile": object((try? encoder.encode(profile.profile)) ?? Data()),
            "onboarded": profile.hasCompletedOnboarding,
            "plans": object((try? encoder.encode(library.imported)) ?? Data()),
            "training": object(log.exportData()),
            "menus": object(menus.exportData()),
            "diary": object(diary.exportData()),
        ]
    }

    static func apply(_ backup: [String: Any], profile: ProfileStore, log: TrainingLog, menus: WeekMenuStore, diary: FoodDiaryStore, library: PlanLibrary) {
        func data(_ key: String) -> Data? {
            backup[key].flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        }
        if let plans = data("plans").flatMap({ try? JSONDecoder().decode([PersonalPlan].self, from: $0) }) {
            library.replaceImported(with: plans)
        }
        if let saved = data("profile").flatMap({ try? JSONDecoder().decode(UserProfile.self, from: $0) }) {
            profile.profile = saved
        }
        if let onboarded = backup["onboarded"] as? Bool { profile.hasCompletedOnboarding = onboarded }
        if let d = data("training") { log.restore(from: d) }
        if let d = data("menus") { menus.restore(from: d) }
        if let d = data("diary") { diary.restore(from: d) }
    }
}
