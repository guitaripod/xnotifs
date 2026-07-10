import SwiftUI
import AppKit
import UserNotifications
import OSLog

@MainActor
final class NotificationsViewModel: ObservableObject {
    @Published var notifications: [XNotification] = []
    @Published var isLoading = false
    @Published var unreadCount: Int = 0
    @Published var errorMessage: String?

    private let settings = AppSettings.shared
    private var apiClient: ApiClient
    private var seenIDs = PersistedSeenIDs.load()
    private var cursor: String?
    private var hasMore = true
    private var pollTask: Task<Void, Never>?
    private var isLoadingMore = false
    private var previousNewestID: String?

    private var cache: NSCache<NSString, NSData> = {
        let c = NSCache<NSString, NSData>()
        c.countLimit = 256
        c.totalCostLimit = 50 * 1024 * 1024
        return c
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    init() {
        apiClient = ApiClient(baseURL: settings.resolvedServerURL)
        requestNotificationPermission()
    }

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
        await apiClient.updateBaseURL(settings.resolvedServerURL)
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
            PersistedSeenIDs.save(seenIDs)

            withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                notifications.append(contentsOf: new)
            }
        } catch {
            errorMessage = error.localizedDescription
            AppLog.error("loadMore: \(error.localizedDescription)")
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

    func markAllRead() {
        unreadCount = 0
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
            PersistedSeenIDs.save(seenIDs)

            unreadCount += new.count
            AppLog.info("fetched \(new.count) new notifications, \(unreadCount) unread")

            withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                notifications.insert(contentsOf: new, at: 0)
            }

            if notifications.count > settings.maxNotifications {
                notifications = Array(notifications.prefix(settings.maxNotifications))
            }

            let newestID = page.notifications.first?.id
            if let newestID, newestID != previousNewestID {
                previousNewestID = newestID
                deliverNotifications(new)
            }

            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            AppLog.error("fetch: \(error.localizedDescription)")
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func deliverNotifications(_ notifications: [XNotification]) {
        let center = UNUserNotificationCenter.current()
        for notification in notifications.prefix(3) {
            let content = UNMutableNotificationContent()
            content.title = notification.primaryActor?.name ?? "New notification"
            content.sound = .default

            switch notification.kind {
            case .like:
                content.body = "liked your post"
            case .retweet:
                content.body = "reposted your post"
            case .reply:
                content.body = notification.targetTweetSnippet ?? "replied to your post"
            case .quote:
                content.body = notification.targetTweetSnippet ?? "quoted your post"
            case .follow:
                content.body = "@\(notification.primaryActor?.handle ?? "") followed you"
            case .mention:
                content.body = notification.targetTweetSnippet ?? "mentioned you"
            }

            let request = UNNotificationRequest(
                identifier: notification.id,
                content: content,
                trigger: nil
            )
            center.add(request)
        }
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
        default:      return dateFormatter.string(from: date)
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
}

private enum PersistedSeenIDs {
    private static let key = "xnotifs.seenIDs"
    private static let maxPersisted = 2000

    static func load() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        let ids = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        return Set(ids.suffix(maxPersisted))
    }

    static func save(_ ids: Set<String>) {
        let trimmed = Array(ids.suffix(maxPersisted))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
