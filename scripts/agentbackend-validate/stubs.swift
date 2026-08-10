import Foundation

/// Stub for the iOS CrashReporter so AppLogger compiles/links on macOS.
final class CrashReporter: NSObject {
    static let shared = CrashReporter()
    func appendLog(_ line: String) {}
}
