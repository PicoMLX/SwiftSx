import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // HTTPURLResponse lives here on Linux
#endif
import HTTPTypes
import Testing
@testable import SwiftSx

// MARK: - Request building (pure)

@Suite struct PageFetcherRequestTests {

    let fetcher = PageFetcher()

    @Test func buildsGetWithBrowserHeaders() throws {
        let req = try fetcher.makeRequest("https://example.com/page")
        #expect(req.method == .get)
        #expect(req.url?.absoluteString == "https://example.com/page")
        #expect(req.headerFields[.userAgent] == PageFetcher.browserUserAgent)
        #expect(req.headerFields[.accept]?.contains("text/html") == true)
        #expect(req.headerFields[.acceptLanguage]?.contains("en") == true)
    }

    @Test func acceptsHttpAndHttps() throws {
        _ = try fetcher.makeRequest("http://example.com")
        _ = try fetcher.makeRequest("https://example.com/a/b?c=d")
    }

    @Test func rejectsInvalidURLs() {
        for bad in ["", "not a url", "ftp://example.com", "/relative/path", "example.com"] {
            #expect(throws: SxError.self) {
                try fetcher.makeRequest(bad)
            }
        }
    }

    @Test func rejectsEmptyHost() {
        // Foundation parses these with an empty host; an agent branches on exit 2.
        for bad in ["http://:80", "http://user@:80", "https://"] {
            #expect(throws: SxError.self) {
                try fetcher.makeRequest(bad)
            }
        }
    }

    @Test func redactedDropsUserinfoAndQuery() {
        #expect(PageFetcher.redacted("https://user:pass@example.com/path?token=secret")
                == "https://example.com/path")
        #expect(PageFetcher.redacted("https://example.com/a/b") == "https://example.com/a/b")
        // Host-less / unparseable input still drops anything after ? or #.
        #expect(PageFetcher.redacted("https://?token=secret") == "https://")
        #expect(PageFetcher.redacted("notaurl?token=secret") == "notaurl")
        // Host-less input with userinfo must not leak credentials either.
        #expect(PageFetcher.redacted("https://user:secret@") == "https://")
        #expect(PageFetcher.redacted("https://user:secret@:80") == "https://:80")
    }

    @Test func noNetworkURLErrorsAreClassified() {
        // Only whole-network-down codes count (exit 7 / propagated from a batch fetch);
        // per-host failures stay per-page and must NOT classify as no-network.
        #expect(PageFetcher.isNoNetwork(.notConnectedToInternet))
        #expect(PageFetcher.isNoNetwork(.networkConnectionLost))
        #expect(!PageFetcher.isNoNetwork(.timedOut))
        #expect(!PageFetcher.isNoNetwork(.cannotConnectToHost))
        #expect(!PageFetcher.isNoNetwork(.cannotFindHost))
        #expect(!PageFetcher.isNoNetwork(.badServerResponse))
    }
}

// MARK: - Fetch (mocked transport)

@Suite(.serialized) struct PageFetcherFetchTests {

    private func mockFetcher() -> PageFetcher {
        PageFetcher(transport: HTTPTransport(session: MockURLProtocol.session()))
    }

    @Test func returnsBodyOn200() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/html"]
            )!
            return (response, Data("<html><body>Hi</body></html>".utf8))
        }
        let body = try await mockFetcher().fetch("https://example.com")
        #expect(body == "<html><body>Hi</body></html>")
    }

    @Test func throwsGeneralOnNon2xx() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            return (response, Data())
        }
        do {
            _ = try await mockFetcher().fetch("https://example.com/missing")
            Issue.record("expected a non-2xx fetch to throw")
        } catch let error as SxError {
            #expect(error.exitCode == .general)
        }
    }

    @Test func requestsTheGivenURL() async throws {
        let captured = TestLockedBox<URL?>(nil)
        MockURLProtocol.handler = { request in
            captured.withLock { $0 = request.url }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            return (response, Data("ok".utf8))
        }
        _ = try await mockFetcher().fetch("https://example.com/path?q=1")
        #expect(captured.withLock { $0 }?.absoluteString == "https://example.com/path?q=1")
    }

    @Test func throwsOnNonTextContentType() async throws {
        // A 2xx that is clearly binary (e.g. a PDF) must not be decoded as HTML.
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/pdf"]
            )!
            return (response, Data([0x25, 0x50, 0x44, 0x46]))   // "%PDF"
        }
        do {
            _ = try await mockFetcher().fetch("https://example.com/file.pdf")
            Issue.record("expected a non-text content-type to throw")
        } catch let error as SxError {
            #expect(error.exitCode == .general)
        }
    }

    @Test func allowsTextContentTypeWithCharsetParameter() async throws {
        // text/html with a charset parameter is still textual and must be returned.
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/html; charset=utf-8"]
            )!
            return (response, Data("<html>ok</html>".utf8))
        }
        let body = try await mockFetcher().fetch("https://example.com")
        #expect(body == "<html>ok</html>")
    }

    @Test func allowsResponseWithNoContentType() async throws {
        // A missing Content-Type is allowed (the caller decides what to do).
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            return (response, Data("plain".utf8))
        }
        let body = try await mockFetcher().fetch("https://example.com")
        #expect(body == "plain")
    }
}
