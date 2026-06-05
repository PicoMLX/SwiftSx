import Foundation
import Testing
@testable import SwiftSx

@Suite struct HistoryLockTests {

    @Test func acquireCreatesFileAndReturnsValidDescriptor() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sx-lock-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let fd = History.acquireExclusiveLock(tmp)
        #expect(fd >= 0)
        #expect(FileManager.default.fileExists(atPath: tmp.path)) // created via O_CREAT
        History.releaseLock(fd)
    }

    @Test func lockCanBeReacquiredAfterRelease() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sx-lock-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let first = History.acquireExclusiveLock(tmp)
        #expect(first >= 0)
        History.releaseLock(first)

        let second = History.acquireExclusiveLock(tmp)
        #expect(second >= 0)
        History.releaseLock(second)
    }

    @Test func releaseWithNegativeDescriptorIsNoOp() {
        // A failed acquire returns -1; releasing it must be safe (no crash).
        History.releaseLock(-1)
    }
}
