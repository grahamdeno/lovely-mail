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
            "system": request.system + toolReminder(SessionPlaybook.toolName),
            "messages": [["role": "user", "content": request.user]],
            "tools": [["name": SessionPlaybook.toolName, "description": SessionPlaybook.toolDescription,
                       "input_schema": SessionPlaybook.schema]],
            // "auto", not a forced tool: newer Claude models (Opus 5.5 and later) reject forced tool_choice with a 400.
            // The system prompt asks for the tool, and parse() also reads the JSON if a model answers in text.
            "tool_choice": ["type": "auto"],
        ]
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return r
    }

    static func toolReminder(_ tool: String) -> String {
        "\n\nAlways answer by calling the \(tool) tool exactly once. Do not answer in plain text."
    }

    /// The tool's input: from the tool_use block, or a JSON object a model wrote as text instead.
    static func toolInput(_ content: [[String: Any]]) -> [String: Any]? {
        if let tool = content.first(where: { ($0["type"] as? String) == "tool_use" }), let input = tool["input"] as? [String: Any] {
            return input
        }
        let text = content.compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let object = try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: Any] else { return nil }
        return object
    }

    static func parse(_ data: Data) throws -> EngineAnswer {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let input = toolInput(content) else { throw EngineError.badAnswer }
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

// MARK: Web forms (Sprint 7, section 9)

/// Engines that can propose values for a web form. Cloud only: Apple's on-device model is too small for this.
protocol FormFiller: Sendable {
    var kind: EngineKind { get }
    func fillForm(system: String, user: String) async throws -> (FormFillPlan, EngineAnswer)
}

extension AnthropicEngine: FormFiller {
    func fillForm(system: String, user: String) async throws -> (FormFillPlan, EngineAnswer) {
        guard let key else { throw EngineError.noKey(.claude) }
        var r = URLRequest(url: Self.endpoint)
        r.httpMethod = "POST"; r.timeoutInterval = 60
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.setValue(key, forHTTPHeaderField: "x-api-key")
        r.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": model, "max_tokens": 1_500, "system": system + Self.toolReminder(FormFillPrompt.toolName),
            "messages": [["role": "user", "content": user]],
            "tools": [["name": FormFillPrompt.toolName, "description": "Values for fields on this page.", "input_schema": FormFillPrompt.schema]],
            "tool_choice": ["type": "auto"],
        ]
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await transport(r)
        try CloudHTTP.check(data, response)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let input = Self.toolInput(content) else { throw EngineError.badAnswer }
        let plan = try CloudHTTP.formPlan(from: input)
        let usage = json["usage"] as? [String: Any]
        return (plan, EngineAnswer(command: SessionCommand(action: "handoff"), engine: .claude,
                                   inputTokens: usage?["input_tokens"] as? Int ?? 0, outputTokens: usage?["output_tokens"] as? Int ?? 0))
    }
}

extension XAIEngine: FormFiller {
    func fillForm(system: String, user: String) async throws -> (FormFillPlan, EngineAnswer) {
        guard let key else { throw EngineError.noKey(.grok) }
        var r = URLRequest(url: Self.endpoint)
        r.httpMethod = "POST"; r.timeoutInterval = 60
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.setValue("Bearer " + key, forHTTPHeaderField: "authorization")
        let body: [String: Any] = [
            "model": model, "temperature": 0.1,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            "tools": [["type": "function", "function": ["name": FormFillPrompt.toolName, "description": "Values for fields on this page.",
                                                       "parameters": FormFillPrompt.schema]]],
            "tool_choice": ["type": "function", "function": ["name": FormFillPrompt.toolName]],
        ]
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await transport(r)
        try CloudHTTP.check(data, response)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = (json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any] else { throw EngineError.badAnswer }
        let arguments = ((message["tool_calls"] as? [[String: Any]])?.first?["function"] as? [String: Any])?["arguments"] as? String
            ?? message["content"] as? String ?? ""
        guard let argData = arguments.data(using: .utf8),
              let input = try? JSONSerialization.jsonObject(with: argData) as? [String: Any] else { throw EngineError.badAnswer }
        let plan = try CloudHTTP.formPlan(from: input)
        let usage = json["usage"] as? [String: Any]
        return (plan, EngineAnswer(command: SessionCommand(action: "handoff"), engine: .grok,
                                   inputTokens: usage?["prompt_tokens"] as? Int ?? 0, outputTokens: usage?["completion_tokens"] as? Int ?? 0))
    }
}

extension CloudHTTP {
    static func formPlan(from input: [String: Any]) throws -> FormFillPlan {
        let data = try JSONSerialization.data(withJSONObject: input)
        guard let plan = try? JSONDecoder().decode(FormFillPlan.self, from: data) else { throw EngineError.badAnswer }
        return plan
    }
}

// MARK: Calendar photos (Nov 9)

/// Reads a photo of a calendar with Claude's vision, when the owner has a Claude key. He said his work calendar holds
/// nothing sensitive and the on-device reading made him fix every event. Only the photo, today's date and his time zone
/// are sent; never mail.
enum CalendarPhotoReader {
    struct Event: Equatable, Sendable {
        var title: String
        var day: String
        var start: String
        var end: String
        var allDay: Bool
        var unsure = false
    }

    static let toolName = "calendar_events"

    static var schema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "events": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "title": ["type": "string", "description": "The event title exactly as shown."],
                            "day": ["type": "string", "description": "YYYY-MM-DD."],
                            "start": ["type": "string", "description": "HH:mm, 24-hour. Empty for all-day."],
                            "end": ["type": "string", "description": "HH:mm, 24-hour. Empty if not visible."],
                            "all_day": ["type": "boolean"],
                            "unsure": ["type": "boolean", "description": "True when the title is cut off, the end runs past the picture, or the time is a guess."],
                        ],
                        "required": ["title", "day", "start", "end", "all_day", "unsure"],
                    ],
                ],
            ],
            "required": ["events"],
        ]
    }

    static func prompt(today: String, timeZone: String) -> String {
        """
        This is a photo, screenshot or PDF of a work calendar (Outlook, Teams or similar), possibly a photo of a computer screen. \
        List every event you can see, once each. Today is \(today); the time zone is \(timeZone). In a week view, match each \
        event to its day column using the header dates, and read start and end times from the hour lines and the event's \
        own text; events are usually on the hour, half hour or quarter hour. Keep titles as written, without the meeting \
        app name, organizer or room lines under them (for "ATLAS Sync / Microsoft Teams Meeting / Raya, Thomas" the title \
        is "ATLAS Sync"); if a title is cut off, keep what is visible and mark it unsure. Skip events marked Canceled or \
        declined. Skip all-day or multi-day out-of-office banners about other people (names with OOO or OoO). If an event \
        runs past the bottom of the picture, give its start, your best end, and mark it unsure. Never invent an event. \
        Answer by calling the \(toolName) tool once.
        """
    }

    /// A photo (JPEG) or a PDF of a calendar.
    enum Source {
        case jpeg(Data)
        case pdf(Data)
        var block: [String: Any] {
            switch self {
            case .jpeg(let d): return ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": d.base64EncodedString()]]
            case .pdf(let d): return ["type": "document", "source": ["type": "base64", "media_type": "application/pdf", "data": d.base64EncodedString()]]
            }
        }
    }

    static func read(jpeg: Data, today: String, timeZone: String, model: String, key: String,
                     transport: EngineTransport = { try await URLSession.shared.data(for: $0) }) async throws -> [Event] {
        try await read(.jpeg(jpeg), today: today, timeZone: timeZone, model: model, key: key, transport: transport)
    }

    static func read(_ source: Source, today: String, timeZone: String, model: String, key: String,
                     transport: EngineTransport = { try await URLSession.shared.data(for: $0) }) async throws -> [Event] {
        var r = URLRequest(url: AnthropicEngine.endpoint)
        r.httpMethod = "POST"
        r.timeoutInterval = 60
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.setValue(key, forHTTPHeaderField: "x-api-key")
        r.setValue(AnthropicEngine.apiVersion, forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4_000,
            "messages": [["role": "user", "content": [
                source.block,
                ["type": "text", "text": prompt(today: today, timeZone: timeZone)],
            ]]],
            "tools": [["name": toolName, "description": "Every event visible in the calendar picture.", "input_schema": schema]],
            "tool_choice": ["type": "auto"],
        ]
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await transport(r)
        try CloudHTTP.check(data, response)
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> [Event] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let input = AnthropicEngine.toolInput(content),
              let events = input["events"] as? [[String: Any]] else { throw EngineError.badAnswer }
        return events.compactMap { e in
            guard let title = e["title"] as? String, let day = e["day"] as? String else { return nil }
            return Event(title: title, day: day, start: e["start"] as? String ?? "", end: e["end"] as? String ?? "",
                         allDay: e["all_day"] as? Bool ?? false, unsure: e["unsure"] as? Bool ?? false)
        }
    }
}


// MARK: Ask Lovely (Nov 9)

/// Turns a question about his mail ("What did Gunner's school send this week?") into a Gmail search. Only the question,
/// today's date and his own addresses go to Claude; the search runs read-only on the phone and its results stay there.
enum MailQuestionReader {
    static let toolName = "gmail_search"

    static func prompt(today: String) -> String {
        """
        The owner asks a question about his Gmail. Turn it into one Gmail search query using Gmail operators (from:, to:, \
        subject:, newer_than:, older_than:, after:, before:, is:unread, has:attachment, in:inbox, OR, quotes). Today is \
        \(today). Prefer recent mail (newer_than:30d) unless he names a time. Put a one-sentence note for him in "say" \
        about what you are looking for. Answer by calling the \(toolName) tool once.
        """
    }

    static func query(_ question: String, today: String, model: String, key: String,
                      transport: EngineTransport = { try await URLSession.shared.data(for: $0) }) async throws -> (query: String, say: String) {
        var r = URLRequest(url: AnthropicEngine.endpoint)
        r.httpMethod = "POST"
        r.timeoutInterval = 30
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.setValue(key, forHTTPHeaderField: "x-api-key")
        r.setValue(AnthropicEngine.apiVersion, forHTTPHeaderField: "anthropic-version")
        let schema: [String: Any] = ["type": "object", "properties": [
            "query": ["type": "string", "description": "The Gmail search query."],
            "say": ["type": "string", "description": "One short sentence for the owner."],
        ], "required": ["query", "say"]]
        let body: [String: Any] = [
            "model": model, "max_tokens": 300,
            "system": prompt(today: today),
            "messages": [["role": "user", "content": String(question.prefix(500))]],
            "tools": [["name": toolName, "description": "One Gmail search for his question.", "input_schema": schema]],
            "tool_choice": ["type": "auto"],
        ]
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await transport(r)
        try CloudHTTP.check(data, response)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]], let input = AnthropicEngine.toolInput(content),
              let q = input["query"] as? String, !q.trimmingCharacters(in: .whitespaces).isEmpty else { throw EngineError.badAnswer }
        return (String(q.prefix(200)), input["say"] as? String ?? "")
    }
}
