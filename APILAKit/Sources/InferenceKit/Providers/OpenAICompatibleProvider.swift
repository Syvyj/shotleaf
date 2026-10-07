import Core
import Foundation
import Synchronization

/// Configuration for an OpenAI-compatible endpoint. The SAME provider serves
/// OpenAI, OpenRouter, LM Studio, Ollama, etc. — only this config differs.
public struct OpenAIConfiguration: Sendable, Equatable {
    /// Base URL including the API version path, e.g.
    /// `https://api.openai.com/v1` or `http://localhost:1234/v1`.
    public var baseURL: URL
    public var apiKey: String?
    /// Currently selected model. Required before streaming.
    public var model: String
    /// Optional runtime serving the model (Provider → Runtime → Model), e.g.
    /// "mlx", "llama.cpp", "anthropic". Documentation/routing hint.
    public var runtimeID: String?
    public var organization: String?
    public var extraHeaders: [String: String]
    public var requestTimeout: TimeInterval
    public var capabilities: ProviderCapabilities

    public init(
        baseURL: URL,
        apiKey: String? = nil,
        model: String,
        runtimeID: String? = nil,
        organization: String? = nil,
        extraHeaders: [String: String] = [:],
        requestTimeout: TimeInterval = 60,
        capabilities: ProviderCapabilities = ProviderCapabilities(
            supportsVision: false, supportsAudio: false, maxContextTokens: 128_000
        )
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.runtimeID = runtimeID
        self.organization = organization
        self.extraHeaders = extraHeaders
        self.requestTimeout = requestTimeout
        self.capabilities = capabilities
    }
}

/// A provider for ANY OpenAI-compatible Chat Completions API. Not tied to a
/// specific vendor. Reconfigurable at runtime (model/key/URL) via a `Mutex`,
/// so a single instance survives model switching.
public final class OpenAICompatibleProvider: InferenceProvider {
    public let id: String
    private let configBox: Mutex<OpenAIConfiguration>
    private let session: URLSession

    public init(
        id: String = "openai-compatible",
        configuration: OpenAIConfiguration,
        session: URLSession? = nil
    ) {
        self.id = id
        self.configBox = Mutex(configuration)
        self.session = session ?? OpenAICompatibleProvider.makeSession(timeout: configuration.requestTimeout)
    }

    private static func makeSession(timeout: TimeInterval) -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }

    // MARK: Runtime configuration

    public var capabilities: ProviderCapabilities { configBox.withLock { $0.capabilities } }
    public var selectedModel: String? { configBox.withLock { $0.model.isEmpty ? nil : $0.model } }
    public func configuration() -> OpenAIConfiguration { configBox.withLock { $0 } }
    public func reconfigure(_ transform: @Sendable (inout OpenAIConfiguration) -> Void) {
        configBox.withLock { transform(&$0) }
    }
    /// Select the active model (from `availableModels()`).
    public func selectModel(_ model: String) { reconfigure { $0.model = model } }

    // MARK: Models

    public func availableModels() async throws -> [ModelInfo] {
        let cfg = configuration()
        var request = URLRequest(url: cfg.baseURL.appendingPathComponent("models"))
        request.timeoutInterval = cfg.requestTimeout
        applyHeaders(to: &request, cfg: cfg)
        do {
            let (data, response) = try await session.data(for: request)
            try Self.validate(response: response, data: data)
            let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
            return decoded.data.map { ModelInfo(id: $0.id, ownedBy: $0.owned_by) }
        } catch let error as InferenceError {
            throw error
        } catch let error as URLError {
            throw Self.map(urlError: error)
        } catch let error as DecodingError {
            throw InferenceError.decoding(String(describing: error))
        } catch {
            throw InferenceError.network(error.localizedDescription)
        }
    }

    // MARK: Health

    public func healthCheck() async -> ProviderHealth {
        do {
            _ = try await availableModels()
            return .healthy
        } catch let error as InferenceError {
            return .unhealthy(reason: Self.describe(error))
        } catch {
            return .unhealthy(reason: error.localizedDescription)
        }
    }

    // MARK: Streaming

    public func stream(_ request: AIRequest) -> AsyncThrowingStream<TokenChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let cfg = self.configuration()
                    guard !cfg.model.isEmpty else { throw InferenceError.noModelSelected }

                    let urlRequest = try self.makeChatRequest(cfg: cfg, request: request, stream: true)
                    let (bytes, response) = try await self.session.bytes(for: urlRequest)
                    try await Self.validateStreaming(response: response, bytes: bytes)

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard let payload = Self.parseSSELine(line) else { continue }
                        if payload == "[DONE]" { break }
                        guard let chunk = Self.decodeChunk(payload) else { continue }
                        if !chunk.text.isEmpty || chunk.finishReason != nil {
                            continuation.yield(chunk)
                        }
                        if chunk.finishReason != nil { break }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: InferenceError.cancelled)
                } catch let error as InferenceError {
                    continuation.finish(throwing: error)
                } catch let error as URLError {
                    continuation.finish(throwing: Self.map(urlError: error))
                } catch {
                    continuation.finish(throwing: InferenceError.network(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Request building

    private func applyHeaders(to request: inout URLRequest, cfg: OpenAIConfiguration) {
        if let key = cfg.apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        if let org = cfg.organization {
            request.setValue(org, forHTTPHeaderField: "OpenAI-Organization")
        }
        for (name, value) in cfg.extraHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
    }

    private func makeChatRequest(cfg: OpenAIConfiguration, request: AIRequest, stream: Bool) throws -> URLRequest {
        var urlRequest = URLRequest(url: cfg.baseURL.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = cfg.requestTimeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyHeaders(to: &urlRequest, cfg: cfg)

        let body = ChatRequest(
            model: cfg.model,
            messages: Self.buildMessages(request, supportsVision: cfg.capabilities.supportsVision),
            stream: stream,
            temperature: request.options?.temperature,
            maxTokens: request.options?.maxTokens
        )
        do {
            urlRequest.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw InferenceError.decoding("encode request: \(error)")
        }
        return urlRequest
    }

    static func buildMessages(_ request: AIRequest, supportsVision: Bool) -> [ChatMessage] {
        var messages: [ChatMessage] = []
        if let system = request.system {
            messages.append(ChatMessage(role: "system", content: .text(system)))
        }

        let hasImage = request.parts.contains { if case .image = $0 { return true }; return false }
        if supportsVision, hasImage {
            var parts: [ContentPartDTO] = []
            for part in request.parts {
                switch part {
                case .text(let text):
                    parts.append(ContentPartDTO(type: "text", text: text, image_url: nil))
                case .image(let image):
                    parts.append(ContentPartDTO(type: "image_url", text: nil, image_url: .init(url: image.dataURL)))
                case .audio:
                    break // chat content can't carry raw audio; handled by audio-capable providers later
                }
            }
            messages.append(ChatMessage(role: "user", content: .parts(parts)))
        } else {
            let text = request.parts.compactMap { if case .text(let t) = $0 { return t }; return nil }
                .joined(separator: "\n\n")
            messages.append(ChatMessage(role: "user", content: .text(text)))
        }
        return messages
    }

    // MARK: Response parsing

    static func parseSSELine(_ line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let value = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    static func decodeChunk(_ json: String) -> TokenChunk? {
        guard let data = json.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(ChatStreamChunk.self, from: data),
              let choice = chunk.choices.first
        else { return nil }
        return TokenChunk(text: choice.delta.content ?? "", finishReason: choice.finish_reason)
    }

    // MARK: Error mapping

    static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw errorFrom(data: data, status: http.statusCode)
        }
    }

    static func validateStreaming(response: URLResponse, bytes: URLSession.AsyncBytes) async throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw errorFrom(data: data, status: http.statusCode)
        }
    }

    static func errorFrom(data: Data, status: Int) -> InferenceError {
        if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
            return .api(message: envelope.error.message, type: envelope.error.type, code: envelope.error.code)
        }
        return .http(status: status, body: String(data: data, encoding: .utf8))
    }

    static func map(urlError: URLError) -> InferenceError {
        switch urlError.code {
        case .timedOut: return .timedOut
        case .cancelled: return .cancelled
        default: return .network(urlError.localizedDescription)
        }
    }

    static func describe(_ error: InferenceError) -> String {
        switch error {
        case .invalidURL: return "Invalid URL"
        case .noModelSelected: return "No model selected"
        case .network(let m): return "Network: \(m)"
        case .timedOut: return "Timed out"
        case .cancelled: return "Cancelled"
        case .http(let status, let body): return "HTTP \(status): \(body ?? "")"
        case .api(let message, _, _): return "API: \(message)"
        case .decoding(let m): return "Decoding: \(m)"
        case .unhealthy(let m): return m
        }
    }
}

// MARK: - Wire DTOs (internal)

struct ModelsResponse: Decodable {
    let data: [ModelDTO]
}
struct ModelDTO: Decodable {
    let id: String
    let owned_by: String?
}

struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let temperature: Double?
    let maxTokens: Int?
    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature
        case maxTokens = "max_tokens"
    }
}

struct ChatMessage: Encodable {
    let role: String
    let content: MessageContent
}

/// Content is either a plain string or an array of typed parts (multimodal).
enum MessageContent: Encodable {
    case text(String)
    case parts([ContentPartDTO])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let string): try container.encode(string)
        case .parts(let parts): try container.encode(parts)
        }
    }
}

struct ContentPartDTO: Encodable {
    let type: String
    let text: String?
    let image_url: ImageURLDTO?
}
struct ImageURLDTO: Encodable {
    let url: String
}

struct ChatStreamChunk: Decodable {
    let choices: [Choice]
    struct Choice: Decodable {
        let delta: Delta
        let finish_reason: String?
    }
    struct Delta: Decodable {
        let content: String?
    }
}

struct APIErrorEnvelope: Decodable {
    let error: APIError
    struct APIError: Decodable {
        let message: String
        let type: String?
        let code: String?
    }
}
