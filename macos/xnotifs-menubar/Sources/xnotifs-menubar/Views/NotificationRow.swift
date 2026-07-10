import SwiftUI

struct NotificationRow: View {
    let notification: XNotification
    let viewModel: NotificationsViewModel

    @EnvironmentObject private var settings: AppSettings
    @State private var avatarImage: NSImage?
    @State private var thumbnailImage: NSImage?
    @State private var isHovering = false

    var body: some View {
        Button {
            viewModel.openInBrowser(notification: notification)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                kindIndicator
                avatarView
                contentColumn
                Spacer(minLength: 0)
                if settings.showThumbnails, let media = notification.targetMedia?.first {
                    thumbnailView(for: media)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .background(
            Rectangle()
                .fill(.quaternary.opacity(isHovering ? 0.4 : 0))
        )
        .task(id: notification.id) { await loadAvatar() }
        .task(id: notification.id) {
            if let media = notification.targetMedia?.first {
                await loadThumbnail(for: media)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var kindIndicator: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(notification.kind.color)
            .frame(width: 3)
            .padding(.vertical, 2)
    }

    private var avatarView: some View {
        Group {
            if let image = avatarImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(notification.primaryActor?.name ?? "Unknown")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                if notification.primaryActor?.verified == true {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.blue)
                }

                kindBadge

                Spacer(minLength: 4)

                Text(NotificationsViewModel.relativeTime(from: notification.timestamp))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            if notification.kind.showsFollowHandle {
                Text("@\(notification.primaryActor?.handle ?? "")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if let snippet = notification.targetTweetSnippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 1)
            }

            if let likeCount = notification.targetTweetLikeCount, likeCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9))
                    Text(NotificationsViewModel.formatCount(likeCount))
                        .font(.system(size: 11))
                }
                .foregroundStyle(.tertiary)
                .padding(.top, 1)
            }
        }
    }

    private var kindBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: notification.kind.icon)
                .font(.system(size: 9, weight: .bold))
            if !notification.kind.label.isEmpty {
                Text(notification.kind.label)
                    .font(.system(size: 10, weight: .medium))
            }
        }
        .foregroundStyle(notification.kind.color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous)
                .fill(notification.kind.color.opacity(0.12))
        )
    }

    private func thumbnailView(for media: Media) -> some View {
        Group {
            if let image = thumbnailImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                    )
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        )
    }

    private var accessibilityText: String {
        let name = notification.primaryActor?.name ?? "Unknown"
        let kind = notification.kind.label
        return "\(name) \(kind)\(notification.targetTweetSnippet.map { ": \($0)" } ?? "")"
    }

    private func loadAvatar() async {
        guard let url = notification.primaryActor?.avatarUrl,
              let avatarURL = URL(string: url) else { return }
        if let data = await viewModel.imageData(for: avatarURL) {
            avatarImage = NSImage(data: data)
        }
    }

    private func loadThumbnail(for media: Media) async {
        guard let url = URL(string: media.url) else { return }
        if let data = await viewModel.imageData(for: url) {
            thumbnailImage = NSImage(data: data)
        }
    }
}

private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.995 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
