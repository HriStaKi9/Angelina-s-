import Foundation
import Security

/// Minimal streaming client for the Claude Messages API (`POST /v1/messages`).
/// There's no official Swift SDK, so this talks raw HTTP + Server-Sent Events.
struct ClaudeClient {
    static let model = "claude-opus-5-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    struct Turn: Codable, Hashable {
        enum Role: String, Codable { case user, assistant }
        let role: Role
        let text: String
    }

    enum Event {
        case text(String)
        /// The model that is actually answering (differs from `model` after a safety fallback).
        case model(String)
        case stop(reason: String?)
    }

    enum ClientError: LocalizedError {
        case missingKey
        case http(status: Int, message: String)
        case api(String)

        var errorDescription: String? {
            switch self {
            case .missingKey: "Add your Anthropic API key first."
            case .http(let status, let message): "HTTP \(status): \(message)"
            case .api(let message): message
            }
        }
    }

    let apiKey: String

    /// Streams a reply. `stablePrompt` is cached (the plan); `context` changes per request (today's data).
    func stream(stablePrompt: String, context: String, turns: [Turn]) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(stablePrompt: stablePrompt, context: context, turns: turns)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw ClientError.http(status: status, message: Self.errorMessage(from: body) ?? body)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let data = payload.data(using: .utf8),
                              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let event = try Self.parse(json) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeRequest(stablePrompt: String, context: String, turns: [Turn]) throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // Server-side fallback: if a safety classifier declines, the API retries on a recommended model.
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 16000,
            "stream": true,
            "fallbacks": "default",
            "thinking": ["type": "adaptive"],
            // Opus 5.5 defaults to medium; set it explicitly.
            "output_config": ["effort": "medium"],
            "system": [
                // The plan rarely changes, so it goes first and is cached across messages.
                ["type": "text", "text": stablePrompt, "cache_control": ["type": "ephemeral"]],
                ["type": "text", "text": context],
            ],
            "messages": turns.map { ["role": $0.role.rawValue, "content": $0.text] },
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func parse(_ json: [String: Any]) throws -> Event? {
        switch json["type"] as? String {
        case "message_start":
            return ((json["message"] as? [String: Any])?["model"] as? String).map(Event.model)
        case "content_block_delta":
            let delta = json["delta"] as? [String: Any]
            // Thinking deltas are hidden by default and not shown in the chat.
            guard delta?["type"] as? String == "text_delta", let text = delta?["text"] as? String else { return nil }
            return .text(text)
        case "message_delta":
            return .stop(reason: (json["delta"] as? [String: Any])?["stop_reason"] as? String)
        case "error":
            let message = ((json["error"] as? [String: Any])?["message"] as? String) ?? "Unknown error"
            throw ClientError.api(message)
        default:
            return nil
        }
    }

    private static func errorMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json["error"] as? [String: Any])?["message"] as? String
    }
}

/// Stores the user's own Anthropic API key in the iOS Keychain (never in UserDefaults or files).
enum APIKeyStore {
    private static let service = "com.hristomir.angelinasnutrition.anthropic"
    private static let account = "api-key"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        delete()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(key.utf8),
        ]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
