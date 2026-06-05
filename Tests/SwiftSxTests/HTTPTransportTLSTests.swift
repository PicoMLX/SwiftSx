import Foundation
import Testing
@testable import SwiftSx

@Suite struct HTTPTransportTLSTests {

    @Test func insecureTransportConstructsInBothModes() {
        // Construction must succeed on every platform: where insecure TLS isn't
        // supported (Linux) the flag is a no-op rather than a build/runtime error.
        // The actual certificate bypass can't be unit-tested without a bad-cert
        // server, so this guards the init paths and Sendable correctness.
        let insecure = HTTPTransport(timeout: 5, allowInsecureTLS: true)
        let secure = HTTPTransport(timeout: 5, allowInsecureTLS: false)
        _ = insecure
        _ = secure
    }
}
