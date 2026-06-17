import Foundation

/// Lightweight opt-in trace sink for low-level C64/1541 debugging.
///
/// Tracing is disabled by default so tests and normal emulator runs do not
/// spam `/tmp`. Set `C64_TRACE=iec,via,drive,gcr,kernal` or `C64_TRACE=all`
/// to enable categories, and optionally `C64_TRACE_FILE=/path/to/log`.
public enum C64Trace {
    public enum Category: String, CaseIterable {
        case iec
        case via
        case drive
        case gcr
        case kernal
    }

    private static let enabledCategories: Set<String> = {
        guard let value = ProcessInfo.processInfo.environment["C64_TRACE"] else {
            return []
        }
        return Set(value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty })
    }()

    private static let outputPath: String = {
        ProcessInfo.processInfo.environment["C64_TRACE_FILE"] ?? "/tmp/c64_debug.log"
    }()

    public static var isEnabled: Bool {
        !enabledCategories.isEmpty
    }

    public static func isEnabled(_ category: Category) -> Bool {
        enabledCategories.contains("all") || enabledCategories.contains(category.rawValue)
    }

    public static func log(_ category: Category, _ message: @autoclosure () -> String) {
        guard isEnabled(category) else { return }

        let line = message() + "\n"
        guard let data = line.data(using: .utf8) else { return }

        if let handle = FileHandle(forWritingAtPath: outputPath) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: outputPath, contents: data)
        }
    }

    public static func resetLog() {
        guard isEnabled else { return }
        FileManager.default.createFile(atPath: outputPath, contents: nil)
    }
}
