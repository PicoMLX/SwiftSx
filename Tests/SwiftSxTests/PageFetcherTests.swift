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
}
