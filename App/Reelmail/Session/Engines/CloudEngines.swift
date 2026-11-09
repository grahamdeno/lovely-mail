import Foundation

// The only file that calls cloud language models (scripts/privacy_guard.py checks it). Used only when the owner turns a
// cloud engine on in Settings and adds a key. What is sent: the playbook, the email's own words (quotes, signatures and
// footers removed, codes and account numbers redacted) and what he said. Health mail is never sent (EngineRouter).
// Both engines must answer by calling the one `session_action` tool, so the answer always fits SessionCommand.

/// Claude through Anthropic's Messages API.
struct AnthropicEngine: SessionEngine {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2023-06-01"

    var model: String
    var key: String?
    var transport: EngineTransport
    var kind: EngineKind { .claude }

    func interpret(_ request: EngineRequest) async throws -> EngineAnswer {
        guard let key else { throw EngineError.noKey(.claude) }
        let (data, response) = try await transport(try Self.urlRequest(request, model: model, key: key))
        try CloudHTTP.check(data, response)
        return try Self.parse(data)
    }

    static func urlRequest(_ request: EngineRequest, model: String, key: String) throws -> URLRequest {
        var r = URLRequest(url: endpoint)
        r.httpMethod = "POST"
        r.timeoutInterval = 45
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.setValue(key, forHTTPHeaderField: "x-api-key")
        r.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1_200,
            "system": request.system,
            "messages": [["role": "user", "content": request.user]],
            "tools": [["name": SessionPlaybook.toolName, "description": SessionPlaybook.toolDescription,
                       "input_schema": SessionPlaybook.schema]],
            "tool_choice": ["type": "tool", "name": SessionPlaybook.toolName],
        ]
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return r
    }

    static func parse(_ data: Data) throws -> EngineAnswer {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let tool = content.first(where: { ($0["type"] as? String) == "tool_use" }),
              let input = tool["input"] as? [String: Any] else { throw EngineError.badAnswer }
        let command = try CloudHTTP.command(from: input)
        let usage = json["usage"] as? [String: Any]
        return EngineAnswer(command: command, engine: .claude,
                            inputTokens: usage?["input_tokens"] as? Int ?? 0, outputTokens: usage?["output_tokens"] as? Int ?? 0)
    }
}

/// Grok through xAI's OpenAI-compatible Chat Completions API.
struct XAIEngine: SessionEngine {
    static let endpoint = URL(string: "https://api.x.ai/v1/chat/completions")!

    var model: String
    var key: String?
    var transport: EngineTransport
    var kind: EngineKind { .grok }

    func interpret(_ request: EngineRequest) async throws -> EngineAnswer {
        guard let key else { throw EngineError.noKey(.grok) }
        let (data, response) = try await transport(try Self.urlRequest(request, model: model, key: key))
        try CloudHTTP.check(data, response)
        return try Self.parse(data)
    }

    static func urlRequest(_ request: EngineRequest, model: String, key: String) throws -> URLRequest {
        var r = URLRequest(url: endpoint)
        r.httpMethod = "POST"
        r.timeoutInterval = 45
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.setValue("Bearer " + key, forHTTPHeaderField: "authorization")
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "messages": [["role": "system", "content": request.system], ["role": "user", "content": request.user]],
            "tools": [["type": "function", "function": ["name": SessionPlaybook.toolName, "description": SessionPlaybook.toolDescription,
                                                       "parameters": SessionPlaybook.schema]]],
            "tool_choice": ["type": "function", "function": ["name": SessionPlaybook.toolName]],
        ]
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return r
    }

    static func parse(_ data: Data) throws -> EngineAnswer {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else { throw EngineError.badAnswer }
        let arguments: String
        if let calls = message["tool_calls"] as? [[String: Any]],
           let function = calls.first?["function"] as? [String: Any],
           let args = function["arguments"] as? String {
            arguments = args
        } else if let content = message["content"] as? String {
            arguments = content   // some models answer with the JSON as text
        } else { throw EngineError.badAnswer }
        guard let argData = arguments.data(using: .utf8),
              let input = try? JSONSerialization.jsonObject(with: argData) as? [String: Any] else { throw EngineError.badAnswer }
        let command = try CloudHTTP.command(from: input)
        let usage = json["usage"] as? [String: Any]
        return EngineAnswer(command: command, engine: .grok,
                            inputTokens: usage?["prompt_tokens"] as? Int ?? 0, outputTokens: usage?["completion_tokens"] as? Int ?? 0)
    }
}

enum CloudHTTP {
    /// Non-2xx answers become a short readable error. The key is never echoed.
    static func check(_ data: Data, _ response: URLResponse) throws {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard !(200..<300).contains(code) else { return }
        var message = ""
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let e = json["error"] as? [String: Any] { message = e["message"] as? String ?? "" }
            else if let e = json["error"] as? String { message = e }
        }
        switch code {
        case 401, 403: message = "Check the key in Settings."
        case 429: message = "Too many requests. Try again in a moment."
        default: break
        }
        throw EngineError.http(code, String(message.prefix(160)))
    }

    static func command(from input: [String: Any]) throws -> SessionCommand {
        let data = try JSONSerialization.data(withJSONObject: input)
        guard let c = try? JSONDecoder().decode(SessionCommand.self, from: data) else { throw EngineError.badAnswer }
        return c
    }
}
