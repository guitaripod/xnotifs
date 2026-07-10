import Foundation
import SwiftUI

struct Media: Codable, Identifiable {
    var id: String { url }
    let url: String
    let kind: MediaKind
    let videoUrl: String?
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
        case altText = "alt_text", posterUrl = "poster_url", videoUrl = "video_url"
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

    enum NotificationKind: String, Codable {
        case like = "Like"
        case retweet = "Retweet"
        case reply = "Reply"
        case quote = "Quote"
        case follow = "Follow"
        case mention = "Mention"

        var color: Color {
            switch self {
            case .like: .pink
            case .retweet: .green
            case .reply, .quote, .follow, .mention: .blue
            }
        }

        var icon: String {
            switch self {
            case .like: "heart.fill"
            case .retweet: "arrow.2.squarepath"
            case .reply: "arrowshape.turn.up.left.fill"
            case .quote: "quote.bubble.fill"
            case .follow: "person.fill.badge.plus"
            case .mention: "at"
            }
        }

        var label: String {
            switch self {
            case .like: "liked"
            case .retweet: "reposted"
            case .reply: "replied"
            case .quote: "quoted"
            case .mention: "mentioned"
            case .follow: ""
            }
        }

        var showsFollowHandle: Bool { self == .follow }
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
