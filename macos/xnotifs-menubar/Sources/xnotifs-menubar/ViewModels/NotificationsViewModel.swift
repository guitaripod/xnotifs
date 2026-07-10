import SwiftUI
import AppKit

@MainActor
final class NotificationsViewModel: ObservableObject {
    @Published var notifications: [XNotification] = []
    @Published var isLoading = false
    @Published var unreadCount: Int = 0
    @Published var errorMessage: String?

    private let settings = AppSettings.shared
    private var apiClient = ApiClient(baseURL: AppSettings.shared.resolvedServerURL)
    private var seenIDs = Set<String>()
    private var cursor: String?
    private var hasMore = true
    private var pollTask: Task<Void, Never>?
    private var isLoadingMore = false

    private var cache: NSCache<NSString, NSData> = {
        let c = NSCache<NSString, NSData>()
        c.countLimit = 256
        c.totalCostLimit = 50 * 1024 * 1024
        return c
    }()

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.fetchLatest()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.settings.pollIntervalSecs))
                guard !Task.isCancelled else { break }
                await self.apiClient.updateBaseURL(self.settings.resolvedServerURL)
                await self.fetchLatest()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        cursor = nil
        hasMore = true
        seenIDs.removeAll()
        notifications.removeAll()
        await fetchLatest()
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await apiClient.fetchNotifications(cursor: cursor)
            cursor = page.cursor
            hasMore = page.cursor != nil

            let new = page.notifications.filter { seenIDs.insert($0.id).inserted }
            guard !new.isEmpty else { return }

            withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                notifications.append(contentsOf: new)
            }
        } catch {
            print("[xnotifs] loadMore error: \(error.localizedDescription)")
        }
    }

    func imageData(for url: URL) async -> Data? {
        let key = url.absoluteString as NSString
        if let cached = cache.object(forKey: key) {
            return cached as Data
        }
        do {
            let data = try await apiClient.fetchImageData(from: url)
            cache.setObject(data as NSData, forKey: key)
            return data
        } catch {
            return nil
        }
    }

    func openInBrowser(notification: XNotification) {
        let urlString: String
        if let tweetId = notification.targetTweetId {
            urlString = "https://x.com/i/web/status/\(tweetId)"
        } else if let handle = notification.primaryActor?.handle {
            urlString = "https://x.com/\(handle)"
        } else {
            return
        }
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    func openActorProfile(_ actor: NotificationActor) {
        guard let url = URL(string: "https://x.com/\(actor.handle)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func fetchLatest() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let page = try await apiClient.fetchNotifications(cursor: nil)
            cursor = page.cursor
            hasMore = page.cursor != nil

            let new = page.notifications.filter { seenIDs.insert($0.id).inserted }
            guard !new.isEmpty else { return }

            unreadCount = min(unreadCount + new.count, settings.maxNotifications)

            withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                notifications.insert(contentsOf: new, at: 0)
            }

            if notifications.count > settings.maxNotifications {
                notifications = Array(notifications.prefix(settings.maxNotifications))
            }

            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            print("[xnotifs] fetch error: \(error.localizedDescription)")
        }
    }

    func markAllRead() {
        unreadCount = 0
    }
}

extension NotificationsViewModel {
    static func relativeTime(from date: Date) -> String {
        let interval = -date.timeIntervalSinceNow
        switch interval {
        case ..<10:   return "just now"
        case ..<60:   return "\(Int(interval))s"
        case ..<3600: return "\(Int(interval / 60))m"
        case ..<86400: return "\(Int(interval / 3600))h"
        default:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }

    static func formatCount(_ count: Int) -> String {
        switch count {
        case ..<1000: return "\(count)"
        case ..<1000000:
            let k = Double(count) / 1000.0
            return String(format: "%.1fK", k)
        default:
            let m = Double(count) / 1000000.0
            return String(format: "%.1fM", m)
        }
    }

    static func actorNames(_ actors: [NotificationActor], othersCount: Int?) -> String {
        guard let primary = actors.first else { return "Someone" }
        if actors.count == 1 && (othersCount ?? 0) == 0 {
            return primary.name
        }
        let total = actors.count + (othersCount ?? 0)
        if total <= 2 {
            let names = actors.prefix(2).map(\.name).joined(separator: " and ")
            return names
        }
        let count = total - 1
        return "\(primary.name) and \(count) other\(count == 1 ? "" : "s")"
    }
}
