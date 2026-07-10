import Foundation
import OSLog

enum AppLog {
    private static let logger = Logger(subsystem: "ml.rawdog.xnotifs-menubar", category: "main")

    static func info(_ message: String) {
        logger.info("\(message)")
        print("[xnotifs] \(message)")
        fflush(stdout)
    }

    static func error(_ message: String) {
        logger.error("\(message)")
        print("[xnotifs] ERROR: \(message)")
        fflush(stdout)
    }
}
