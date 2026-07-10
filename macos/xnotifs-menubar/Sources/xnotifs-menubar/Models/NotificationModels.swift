import Foundation

struct Media: Codable, Identifiable {
    var id: String { url }
    let url: String
    let kind: MediaKind
    let width: Int?
    let height: Int?
    let altText: String?
    let durationSecs: Int?
    let posterUrl: String?

    enum MediaKind: String, Codable {
        case photo
        case video
        case animatedGif = "animated_gif"
        case linkCard = "link_card"
        case youTube = "youtube"
        case poll
    }

    enum CodingKeys: String, CodingKey {
        case url, kind, width, height, durationSecs = "duration_secs"
        case altText = "alt_text", posterUrl = "poster_url"
    }
}

struct NotificationActor: Codable, Identifiable {
    var id: String { restId }
    let handle: String
    let name: String
    let restId: String
    let verified: Bool
    let avatarUrl: String

    enum CodingKeys: String, CodingKey {
        case handle, name, verified
        case restId = "rest_id", avatarUrl = "avatar_url"
    }
}

struct XNotification: Codable, Identifiable {
    let id: String
    let kind: NotificationKind
    let actors: [NotificationActor]
    let targetTweetId: String?
    let targetTweetSnippet: String?
    let targetTweetLikeCount: Int?
    let targetMedia: [Media]?
    let othersCount: Int?
    let message: String?
    let timestamp: Date

    var primaryActor: NotificationActor? { actors.first }
    var hasMultipleActors: Bool { (othersCount ?? 0) > 0 }
    var actorDisplayCount: Int { actors.count + (othersCount ?? 0) }

    enum NotificationKind: String, Codable {
        case like
        case retweet
        case reply
        case quote
        case follow
        case mention
    }

    enum CodingKeys: String, CodingKey {
        case id, actors, message, timestamp
        case kind = "type"
        case targetTweetId = "target_tweet_id"
        case targetTweetSnippet = "target_tweet_snippet"
        case targetTweetLikeCount = "target_tweet_like_count"
        case targetMedia = "target_media"
        case othersCount = "others_count"
    }
}

struct NotificationsPage: Codable {
    let notifications: [XNotification]
    let cursor: String?
}
