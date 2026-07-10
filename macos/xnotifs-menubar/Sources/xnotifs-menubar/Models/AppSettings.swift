import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("serverURL") var serverURL: String = "http://localhost:7777"
    @AppStorage("pollIntervalSecs") var pollIntervalSecs: Int = 15
    @AppStorage("showThumbnails") var showThumbnails: Bool = true
    @AppStorage("maxNotifications") var maxNotifications: Int = 200
    @AppStorage("fontScale") var fontScale: Double = 1.0

    static let shared = AppSettings()

    var resolvedServerURL: URL {
        if let env = ProcessInfo.processInfo.environment["XNOTIFS_SERVER"],
           let url = URL(string: env) {
            return url
        }
        return URL(string: serverURL) ?? URL(string: "http://localhost:7777")!
    }
}
