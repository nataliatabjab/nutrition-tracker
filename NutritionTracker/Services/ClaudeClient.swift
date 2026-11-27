import Foundation

/// Minimal client for the Claude Messages API (https://platform.claude.com/docs/en/api/messages).
/// Swift has no official Anthropic SDK, so this sends plain HTTP requests. Messages and content blocks are kept
/// as JSON dictionaries so that the assistant's content (including thinking blocks) goes back to the API unchanged.
enum ClaudeClient {
    static let model = "claude-opus-5-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    enum ClaudeError: LocalizedError {
        case missingKey
        case http(Int, String)
        case badResponse
        case refused
        case cutOff

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return "Add your Claude API key in Settings first."
            case .http(401, _):
                return "Claude didn't accept the API key. Check it in Settings."
            case .http(429, _):
                return "Claude is rate limiting requests right now. Try again in a minute."
            case .http(let code, let message):
                return message.isEmpty ? "Claude request failed (error \(code))." : "Claude request failed (error \(code)): \(message)"
            case .badResponse:
                return "Claude sent a response the app couldn't read."
            case .refused:
                return "Claude declined this request. Try rewording it."
            case .cutOff:
                return "Claude's answer was cut off. Try logging fewer meals at once."
            }
        }
    }

    /// Sends one Messages request and returns the decoded response body.
    static func send(apiKey: String, system: String, tools: [[String: Any]],
                     messages: [[String: Any]]) async throws -> [String: Any] {
        guard !apiKey.isEmpty else { throw ClaudeError.missingKey }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": system,
            "tools": tools,
            "messages": messages,
            "thinking": ["type": "adaptive"],
            "output_config": ["effort": "medium"],
            // Caches the system prompt, tools and earlier turns between the round trips of one logging session.
            "cache_control": ["type": "ephemeral"],
            // If a safety classifier ever declines, the API retries on a fallback model instead of stopping.
            "fallbacks": "default",
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var attempt = 0
        while true {
            attempt += 1
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if status == 200, let json {
                return json
            }
            // Overloaded, rate limited or a server error: wait a little and try again.
            if [429, 500, 502, 503, 504, 529].contains(status), attempt < 3 {
                try await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
                continue
            }
            let message = (json?["error"] as? [String: Any])?["message"] as? String ?? ""
            throw ClaudeError.http(status, message)
        }
    }

    static func imageBlock(jpeg: Data) -> [String: Any] {
        [
            "type": "image",
            "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()],
        ]
    }

    static func textBlock(_ text: String) -> [String: Any] {
        ["type": "text", "text": text]
    }

    static func toolResult(id: String, content: String, isError: Bool = false) -> [String: Any] {
        var block: [String: Any] = ["type": "tool_result", "tool_use_id": id, "content": content]
        if isError { block["is_error"] = true }
        return block
    }
}

/// Reads a JSON number whether it was decoded as an integer or a double.
func jsonNumber(_ value: Any?) -> Double? {
    (value as? NSNumber)?.doubleValue
}
