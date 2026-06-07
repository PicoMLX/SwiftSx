import Foundation
import HTTPTypes
import HTTPTypesFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - MCP JSON-RPC concrete wire types
//
// All request/response shapes are modelled with concrete Codable structs rather
// than a generic Any-JSON type.  This keeps the code dependency-free and lets
// the compiler verify the structure at build time.
//
// The MCP protocol uses JSON-RPC 2.0.  Only the shapes actually needed by the
// Exa MCP path are defined here — additional methods would add more parallel
// structs rather than reaching for a generic JSONValue wrapper.

// MARK: - Initialize request/response

/// Params for the `initialize` JSON-RPC method.
private struct MCPInitializeParams: Encodable {
    let protocolVersion: String
    let capabilities: [String: String]
    let clientInfo: ClientInfo

    struct ClientInfo: Encodable {
        let name: String
        let version: String
    }

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case capabilities
        case clientInfo
    }
}

// MARK: - tools/call request

/// Arguments forwarded inside a `tools/call` params object.
///
/// Exa's MCP tool accepts both `num_results` (snake_case) and `numResults`
/// (camelCase) — both are sent to maximise compatibility.
struct MCPToolCallArguments: Encodable {
    let query: String
    let numResults: Int

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(query,      forKey: .query)
        try c.encode(numResults, forKey: .numResults)
        try c.encode(numResults, forKey: .numResultsSnake)
    }

    enum CodingKeys: String, CodingKey {
        case query
        case numResults      = "numResults"
        case numResultsSnake = "num_results"
    }
}

/// Params for the `tools/call` JSON-RPC method.
struct MCPToolCallParams: Encodable {
    let name: String
    let arguments: MCPToolCallArguments

    enum CodingKeys: String, CodingKey {
        case name
        case arguments
    }
}

// MARK: - Generic JSON-RPC envelope

/// A generic JSON-RPC 2.0 request envelope.
private struct MCPRequest<P: Encodable>: Encodable {
    let jsonrpc: String = "2.0"
    let id: Int
    let method: String
    let params: P

    enum CodingKeys: String, CodingKey {
        case jsonrpc, id, method, params
    }
}

// MARK: - JSON-RPC response envelope

/// The error object embedded in a JSON-RPC failure response.
private struct MCPErrorObject: Decodable {
    let code: Int?
    let message: String?
}

/// Top-level JSON-RPC 2.0 response envelope.
///
/// The `result` field is decoded directly into the concrete type `R` that the
/// caller specifies, eliminating any intermediate JSONSerialization round-trip.
private struct MCPResponse<R: Decodable>: Decodable {
    let error: MCPErrorObject?
    let result: R?
}

// MARK: - MCPHTTPClient

/// A minimal JSON-RPC 2.0 over HTTP client used by ``ExaBackend``'s MCP mode.
///
/// Concrete request structs are used for all MCP shapes so no generic
/// `JSONValue` dependency is needed.
struct MCPHTTPClient: Sendable {

    // MARK: - Properties

    /// The MCP server endpoint URL string.
    let urlString: String
    /// The HTTP transport (injectable for testing).
    let transport: HTTPTransport

    // MARK: - Init

    init(urlString: String, transport: HTTPTransport) {
        self.urlString = urlString
        self.transport = transport
    }

    // MARK: - Internal helpers

    /// POST a JSON-RPC `initialize` call to the server.
    ///
    /// Errors are silently swallowed — the initialize handshake is best-effort.
    func initialize() async {
        let params = MCPInitializeParams(
            protocolVersion: "2024-11-05",
            capabilities: [:],
            clientInfo: MCPInitializeParams.ClientInfo(name: "sx", version: "2.2.0")
        )
        let envelope = MCPRequest(id: 1, method: "initialize", params: params)
        _ = try? await postJSON(envelope, responseType: EmptyResult.self)
    }

    /// POST a `tools/call` JSON-RPC request and decode the `result` into `R`.
    ///
    /// - Parameters:
    ///   - toolName: The MCP tool name to invoke.
    ///   - arguments: The tool arguments to forward.
    ///   - responseType: The concrete `Decodable` type to decode the `result` into.
    /// - Returns: The decoded `result` value.
    /// - Throws: `BackendError` on network failure, non-2xx status, or a
    ///   JSON-RPC `error` object in the response.
    func callTool<R: Decodable>(name toolName: String, arguments: MCPToolCallArguments, responseType: R.Type) async throws -> R {
        let params = MCPToolCallParams(name: toolName, arguments: arguments)
        let envelope = MCPRequest(id: 2, method: "tools/call", params: params)
        return try await postJSON(envelope, responseType: responseType)
    }

    // MARK: - Private

    /// Placeholder used by `initialize()` when the response body is irrelevant.
    private struct EmptyResult: Decodable {}

    /// Encode `request` as JSON, POST it to `urlString`, decode the JSON-RPC
    /// `result` field directly into `R`, and return it.
    ///
    /// - Throws: `BackendError(.network, …)` for transport errors, bad URLs, or
    ///   a JSON-RPC `error` object in the response.
    /// - Throws: `BackendError(.invalidResponse, …)` if the envelope cannot be
    ///   parsed or the `result` field is absent.
    private func postJSON<P: Encodable, R: Decodable>(_ request: MCPRequest<P>, responseType: R.Type) async throws -> R {
        guard let url = URL(string: urlString) else {
            throw BackendError(
                backend: "exa-mcp",
                code: .network,
                message: "exa MCP request failed: invalid MCP URL '\(urlString)'"
            )
        }

        let bodyData: Data
        do {
            bodyData = try JSONEncoder().encode(request)
        } catch {
            throw BackendError(
                backend: "exa-mcp",
                code: .network,
                message: "exa MCP request failed: could not encode request: \(error)"
            )
        }

        var httpRequest = HTTPRequest(method: .post, url: url)
        httpRequest.headerFields[.contentType] = "application/json"
        httpRequest.headerFields[.accept] = "application/json"

        let (data, response): (Data, HTTPResponse)
        do {
            (data, response) = try await transport.send(httpRequest, body: bodyData)
        } catch is CancellationError {
            throw CancellationError()
        } catch let sx as SxError {
            throw sx
        } catch let be as BackendError {
            throw be
        } catch {
            throw BackendError(
                backend: "exa-mcp",
                code: .network,
                message: "exa MCP request failed: \(error)"
            )
        }

        let status = response.status.code
        switch status {
        case 200...299:
            break   // fall through to decode the envelope below
        case 401, 403:
            // Auth failure — distinct from a generic network error so the agent
            // gets an accurate message (still fail-closed / exit 7).
            throw BackendError(
                backend: "exa-mcp",
                code: .auth,
                message: "exa MCP server rejected the request (HTTP \(status)) — check the MCP URL or its credentials (engines_exa.mcp_url)"
            )
        case 429:
            // Rate limited — a transient (exit 1) condition, not fail-closed.
            throw BackendError(
                backend: "exa-mcp",
                code: .rateLimit,
                message: "exa MCP server is rate limiting (HTTP 429) — back off and retry"
            )
        default:
            throw BackendError(
                backend: "exa-mcp",
                code: .network,
                message: "exa MCP server returned HTTP \(status)"
            )
        }

        // Decode the envelope; this also checks for a JSON-RPC error object.
        guard let envelope = try? JSONDecoder().decode(MCPResponse<R>.self, from: data) else {
            throw BackendError(
                backend: "exa-mcp",
                code: .invalidResponse,
                message: "exa MCP returned a response that could not be parsed"
            )
        }

        if let rpcError = envelope.error {
            let msg = rpcError.message ?? "unknown MCP error"
            throw BackendError(
                backend: "exa-mcp",
                code: .network,
                message: "exa MCP returned a JSON-RPC error: \(msg)"
            )
        }

        guard let result = envelope.result else {
            throw BackendError(
                backend: "exa-mcp",
                code: .invalidResponse,
                message: "exa MCP returned a response without a 'result' field"
            )
        }

        return result
    }
}
