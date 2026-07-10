import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("serverURL") var serverURL: String = "http://localhost:7777"
    @AppStorage("pollIntervalSecs") var pollIntervalSecs: Int = 15
    @AppStorage("showThumbnails") var showThumbnails: Bool = true
    @AppStorage("maxNotifications") var maxNotifications: Int = 200

    static let shared = AppSettings()
    static let fallbackURL = URL(string: "http://localhost:7777")!

    var resolvedServerURL: URL {
        if let env = ProcessInfo.processInfo.environment["XNOTIFS_SERVER"],
           let url = URL(string: env) {
            return url
        }
        return URL(string: serverURL) ?? Self.fallbackURL
    }
}
