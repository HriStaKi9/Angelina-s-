import Foundation

/// The AI services the in-app assistant can use. Each is connected with the user's own API key:
/// none of them lets other apps sign in with a consumer subscription (Claude Pro, ChatGPT Plus, Gemini Advanced).
enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case claude, openai, gemini

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: "Claude"
        case .openai: "ChatGPT"
        case .gemini: "Gemini"
        }
    }

    var company: String {
        switch self {
        case .claude: "Anthropic"
        case .openai: "OpenAI"
        case .gemini: "Google"
        }
    }

    var systemImage: String {
        switch self {
        case .claude: "sparkles"
        case .openai: "bubble.left.and.text.bubble.right.fill"
        case .gemini: "diamond.fill"
        }
    }

    /// Where to sign in and create an API key.
    var keysURL: URL {
        switch self {
        case .claude: URL(string: "https://console.anthropic.com/settings/keys")!
        case .openai: URL(string: "https://platform.openai.com/api-keys")!
        case .gemini: URL(string: "https://aistudio.google.com/app/apikey")!
        }
    }

    var consoleName: String {
        switch self {
        case .claude: "Claude Console"
        case .openai: "OpenAI Platform"
        case .gemini: "Google AI Studio"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .claude: "sk-ant-…"
        case .openai: "sk-…"
        case .gemini: "AIza…"
        }
    }

    func looksLikeKey(_ key: String) -> Bool {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .claude: return k.hasPrefix("sk-ant-")
        case .openai: return k.hasPrefix("sk-") && !k.hasPrefix("sk-ant-")
        case .gemini: return k.count >= 30
        }
    }
}

/// Keys live in the Keychain, one item per provider (Claude keeps its original item).
enum ProviderKeys {
    static func load(_ provider: AIProvider) -> String? {
        provider == .claude ? APIKeyStore.load() : item(provider).load()
    }

    static func save(_ key: String, for provider: AIProvider) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider == .claude { APIKeyStore.save(trimmed) } else { item(provider).save(trimmed) }
    }

    static func delete(_ provider: AIProvider) {
        if provider == .claude { APIKeyStore.delete() } else { item(provider).delete() }
    }

    private static func item(_ provider: AIProvider) -> KeychainItem<String> {
        KeychainItem(service: "com.hristomir.angelinasnutrition.ai.\(provider.rawValue)", account: "api-key")
    }
}

// MARK: - Models

enum ProviderModels {
    /// Lists the chat models the key can use; a successful call also proves the key works.
    static func list(_ provider: AIProvider, key: String) async throws -> [String] {
        switch provider {
        case .claude:
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=100")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let json = try await fetch(request)
            return (json["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        case .openai:
            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let json = try await fetch(request)
            let skip = ["audio", "realtime", "transcribe", "tts", "image", "embedding", "search", "instruct", "moderation", "whisper", "dall-e", "davinci", "babbage", "codex"]
            return (json["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
                .filter { id in (id.hasPrefix("gpt-") || id.hasPrefix("o") || id.hasPrefix("chatgpt")) && !skip.contains { id.contains($0) } }
                .sorted(by: preferred)
        case .gemini:
            var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200")!)
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            let json = try await fetch(request)
            let skip = ["embedding", "image", "tts", "aqa", "live", "audio", "vision"]
            return (json["models"] as? [[String: Any]] ?? []).compactMap { model -> String? in
                guard let name = model["name"] as? String,
                      (model["supportedGenerationMethods"] as? [String])?.contains("generateContent") == true else { return nil }
                return name.replacingOccurrences(of: "models/", with: "")
            }
            .filter { id in id.contains("gemini") && !skip.contains { id.contains($0) } }
            .sorted(by: preferred)
        }
    }

    /// Best default: the newest full model (not mini/nano/lite/preview/dated snapshot).
    static func defaultModel(_ provider: AIProvider, from models: [String]) -> String? {
        if provider == .claude { return models.contains(ClaudeClient.model) ? ClaudeClient.model : models.first }
        return models.first { isMainline($0) } ?? models.first
    }

    private static func isMainline(_ id: String) -> Bool {
        let lower = id.lowercased()
        let minor = ["mini", "nano", "lite", "preview", "exp", "-8b", "turbo", "-0"]
        let dated = lower.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil
        return !minor.contains { lower.contains($0) } && !dated
    }

    /// Higher version numbers first, then mainline models before variants.
    private static func preferred(_ a: String, _ b: String) -> Bool {
        let va = version(a), vb = version(b)
        if va != vb { return va > vb }
        if isMainline(a) != isMainline(b) { return isMainline(a) }
        if a.contains("pro") != b.contains("pro") { return a.contains("pro") }
        return a < b
    }

    private static func version(_ id: String) -> Double {
        guard let range = id.range(of: #"\d+(\.\d+)?"#, options: .regularExpression) else { return 0 }
        return Double(id[range]) ?? 0
    }

    private static func fetch(_ request: URLRequest) async throws -> [String: Any] {
        var request = request
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status == 200 else {
            let error = json["error"] as? [String: Any]
            let message = error?["message"] as? String ?? (status == 401 || status == 403 ? "The key was rejected." : "HTTP \(status)")
            throw ClaudeClient.ClientError.http(status: status, message: message)
        }
        return json
    }
}

// MARK: - Chat backends

/// Streams a chat reply from the selected provider, reusing the Claude client's event type.
enum ChatBackend {
    static func stream(provider: AIProvider, model: String, key: String, stablePrompt: String, context: String,
                       turns: [ClaudeClient.Turn]) -> AsyncThrowingStream<ClaudeClient.Event, Error> {
        switch provider {
        case .claude:
            return ClaudeClient(apiKey: key).stream(stablePrompt: stablePrompt, context: context, turns: turns)
        case .openai:
            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let messages: [[String: Any]] = [["role": "system", "content": stablePrompt + "\n\n" + context]]
                + turns.map { ["role": $0.role.rawValue, "content": $0.text] }
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "stream": true, "messages": messages])
            return sse(request) { json in
                guard let choice = (json["choices"] as? [[String: Any]])?.first else { return [] }
                var events: [ClaudeClient.Event] = []
                if let text = (choice["delta"] as? [String: Any])?["content"] as? String, !text.isEmpty { events.append(.text(text)) }
                if let finish = choice["finish_reason"] as? String {
                    events.append(.stop(reason: finish == "length" ? "max_tokens" : finish == "content_filter" ? "refusal" : "end_turn"))
                }
                return events
            }
        case .gemini:
            let encoded = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
            var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encoded):streamGenerateContent?alt=sse")!)
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            let body: [String: Any] = [
                "systemInstruction": ["parts": [["text": stablePrompt], ["text": context]]],
                "contents": turns.map { ["role": $0.role == .user ? "user" : "model", "parts": [["text": $0.text]]] },
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            return sse(request) { json in
                guard let candidate = (json["candidates"] as? [[String: Any]])?.first else { return [] }
                var events: [ClaudeClient.Event] = []
                let parts = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
                // Skip "thought" parts some models stream before the answer.
                let text = parts.filter { ($0["thought"] as? Bool) != true }.compactMap { $0["text"] as? String }.joined()
                if !text.isEmpty { events.append(.text(text)) }
                if let finish = candidate["finishReason"] as? String {
                    events.append(.stop(reason: finish == "MAX_TOKENS" ? "max_tokens" : ["SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST"].contains(finish) ? "refusal" : "end_turn"))
                }
                return events
            }
        }
    }

    /// POSTs a request and turns its Server-Sent Events into chat events.
    private static func sse(_ base: URLRequest, parse: @escaping ([String: Any]) -> [ClaudeClient.Event]) -> AsyncThrowingStream<ClaudeClient.Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = base
                    request.httpMethod = "POST"
                    request.timeoutInterval = 300
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        var text = ""
                        for try await line in bytes.lines { text += line }
                        let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
                        let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? text
                        throw ClaudeClient.ClientError.http(status: status, message: message)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { continue }
                        if let error = json["error"] as? [String: Any] {
                            throw ClaudeClient.ClientError.api(error["message"] as? String ?? "Unknown error")
                        }
                        for event in parse(json) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
