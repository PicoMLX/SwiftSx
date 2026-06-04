import Foundation
import HTTPTypes
import HTTPTypesFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - JinaRequest (private wire type)

/// The JSON body sent to the Jina AI search endpoint.
private struct JinaRequest: Encodable {
    let q: String
    /// BCP 47 language tag (e.g. `"en"`); omitted when empty.
    let hl: String?
    /// ISO 3166-1 alpha-2 country code (e.g. `"US"`); omitted when empty.
    let gl: String?
    /// Optional location string; reserved for future use.
    let location: String?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(q, forKey: .q)
        try c.encodeIfPresent(hl,       forKey: .hl)
        try c.encodeIfPresent(gl,       forKey: .gl)
        try c.encodeIfPresent(location, forKey: .location)
    }

    enum CodingKeys: String, CodingKey {
        case q, hl, gl, location
    }
}

// MARK: - JinaResponse (private wire type)

/// The JSON envelope returned by the Jina AI search endpoint.
private struct JinaResponse: Decodable {
    let code: Int?
    let status: Int?
    let data: [Item]?

    struct Item: Decodable {
        let title: String?
        let url: String?
        let description: String?
        let content: String?
    }
}

// MARK: - JinaBackend

/// A Jina AI Search backend.
///
/// Supports both authenticated (via `apiKey`) and keyless operation when
/// `allowKeyless` is `true`. The default endpoint is `https://s.jina.ai/`.
public struct JinaBackend: SearchBackend {

    // MARK: - Properties

    /// The Jina AI API key.
    public let apiKey: String
    /// When `true`, requests are sent without an `Authorization` header.
    public let allowKeyless: Bool
    /// The base URL of the Jina search endpoint (default: `"https://s.jina.ai"`).
    public let baseURL: String
    /// The transport layer (injectable for testing).
    let transport: HTTPTransport

    // MARK: - Init

    public init(
        apiKey: String = "",
        allowKeyless: Bool = true,
        baseURL: String = "https://s.jina.ai",
        transport: HTTPTransport = HTTPTransport()
    ) {
        self.apiKey       = apiKey
        self.allowKeyless = allowKeyless
        self.baseURL      = baseURL
        self.transport    = transport
    }

    // MARK: - SearchBackend

    public var name: String { "jina" }

    /// `true` when `apiKey` is non-empty, or when `allowKeyless` is `true`.
    public var isAvailable: Bool { !apiKey.isEmpty || allowKeyless }

    /// Perform a search against the Jina AI search endpoint.
    ///
    /// - Throws: `BackendError(.unavailable, …)` when `isAvailable` is `false`.
    /// - Throws: `BackendError` with an appropriate code on any HTTP or decode failure.
    public func search(_ options: SearchOptions) async throws -> [SearchResult] {
        guard isAvailable else {
            throw BackendError(
                backend: "jina",
                code: .unavailable,
                message: "jina is not configured — set JINA_API_KEY or enable engines_jina.allow_keyless"
            )
        }

        let (request, bodyData) = try makeRequest(options)

        let (data, response): (Data, HTTPResponse)
        do {
            (data, response) = try await transport.send(request, body: bodyData)
        } catch is CancellationError {
            throw CancellationError()
        } catch let sx as SxError {
            throw sx          // e.g. a sandbox refusal — propagate as-is (exit 3)
        } catch let be as BackendError {
            throw be
        } catch {
            throw BackendError(
                backend: "jina",
                code: .network,
                message: "jina request failed: \(error)"
            )
        }

        let status = response.status.code
        switch status {
        case 200...299:
            do {
                let decoded = try JSONDecoder().decode(JinaResponse.self, from: data)
                var mapped = (decoded.data ?? []).map { item -> SearchResult in
                    // Prefer `description`; fall back to `content` (truncated to 500 chars).
                    let resolvedContent: String
                    if let desc = item.description, !desc.isEmpty {
                        resolvedContent = desc
                    } else if let raw = item.content {
                        resolvedContent = raw.count > 500 ? String(raw.prefix(500)) : raw
                    } else {
                        resolvedContent = ""
                    }
                    return SearchResult(
                        title:   item.title ?? "",
                        url:     item.url   ?? "",
                        content: resolvedContent,
                        engine:  "jina",
                        engines: ["jina"]
                    )
                }
                // Cap to requested maximum.
                if options.numResults > 0, mapped.count > options.numResults {
                    mapped = Array(mapped.prefix(options.numResults))
                }
                return mapped
            } catch {
                throw BackendError(
                    backend: "jina",
                    code: .invalidResponse,
                    message: "jina returned a response that could not be parsed"
                )
            }
        case 401, 403:
            throw BackendError(
                backend: "jina",
                code: .auth,
                message: "jina rejected the request (HTTP \(status)) — check the Jina API key (JINA_API_KEY)"
            )
        case 429:
            throw BackendError(
                backend: "jina",
                code: .rateLimit,
                message: "jina is rate limiting (HTTP 429) — back off and retry"
            )
        default:
            throw BackendError(
                backend: "jina",
                code: .network,
                message: "jina returned HTTP \(status)"
            )
        }
    }

    // MARK: - Request construction (internal for testability)

    /// Build the `HTTPRequest` and JSON body `Data` for the given options.
    ///
    /// This is factored out of `search(_:)` so tests can assert URL, method,
    /// headers, and body without touching the network.
    ///
    /// - Throws: `BackendError(.network, …)` when the endpoint URL cannot be
    ///   built or the body cannot be encoded.
    func makeRequest(_ options: SearchOptions) throws -> (HTTPRequest, Data) {
        // Normalise the base URL: trim a trailing slash before using it directly.
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL

        guard let url = URL(string: base) else {
            throw BackendError(
                backend: "jina",
                code: .network,
                message: "jina request failed: could not build endpoint URL from '\(base)'"
            )
        }

        // Build the request body.
        // hl is included only when language is non-empty.
        let hl: String? = options.language.isEmpty ? nil : options.language

        let requestBody = JinaRequest(
            q:        options.query,
            hl:       hl,
            gl:       nil,      // country filtering not yet exposed via SearchOptions
            location: nil
        )

        let bodyData: Data
        do {
            bodyData = try JSONEncoder().encode(requestBody)
        } catch {
            throw BackendError(
                backend: "jina",
                code: .network,
                message: "jina request failed: could not encode request body: \(error)"
            )
        }

        var request = HTTPRequest(method: .post, url: url)
        request.headerFields[.accept] = "application/json"
        request.headerFields[.contentType] = "application/json"

        // Authorization: Bearer only when apiKey is present.
        if !apiKey.isEmpty {
            request.headerFields[.authorization] = "Bearer \(apiKey)"
        }

        // X-Site: restrict to a site when options.site is non-empty.
        // Prefix with "https://" when the value has no scheme.
        if !options.site.isEmpty {
            let siteValue: String
            if options.site.lowercased().hasPrefix("http://") ||
               options.site.lowercased().hasPrefix("https://") {
                siteValue = options.site
            } else {
                siteValue = "https://\(options.site)"
            }
            request.headerFields[.xSite] = siteValue
        }

        return (request, bodyData)
    }
}

// MARK: - HTTPField.Name extensions for Jina

private extension HTTPField.Name {
    /// The `X-Site` header used by the Jina AI search endpoint for domain restriction.
    static let xSite = HTTPField.Name("X-Site")!
}

// MARK: - Factory (builds a JinaBackend from Config)

extension JinaBackend {
    /// Build a ``JinaBackend`` from a loaded `Config`.
    ///
    /// - Parameters:
    ///   - config: The loaded and normalised configuration.
    ///   - transport: The HTTP transport to inject (default: shared session with
    ///     configured timeout).
    /// - Returns: A ``JinaBackend`` configured from `config.enginesJina`.
    public static func makeJina(
        from config: Config,
        transport: HTTPTransport? = nil
    ) -> JinaBackend {
        JinaBackend(
            apiKey:       config.enginesJina.apiKey,
            allowKeyless: config.enginesJina.allowKeyless,
            baseURL:      config.enginesJina.baseURL,
            transport:    transport ?? HTTPTransport(timeout: config.timeout)
        )
    }
}
