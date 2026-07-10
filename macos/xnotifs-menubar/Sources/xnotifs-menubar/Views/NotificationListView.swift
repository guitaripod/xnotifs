import SwiftUI

struct NotificationListView: View {
    @ObservedObject var viewModel: NotificationsViewModel

    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .overlay(alignment: .bottom) { Divider().opacity(0.3) }

            if viewModel.notifications.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .frame(minHeight: 100, maxHeight: 620)
        .glassPanelBackground()
    }

    private var headerBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("Notifications")
                    .font(.system(size: 13, weight: .bold))
                unreadBadge
            }
            Spacer()
            if viewModel.unreadCount > 0 {
                headerButton("checkmark") { viewModel.markAllRead() }
            }
            headerButton("arrow.clockwise") {
                Task { await viewModel.refresh() }
            }
            .symbolEffect(.rotate, value: viewModel.isLoading)
            headerButton("gearshape") {
                openSettings()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var unreadBadge: some View {
        if viewModel.unreadCount > 0 {
            Text("\(viewModel.unreadCount)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(unreadBadgeColor)
                )
        }
    }

    private var unreadBadgeColor: Color {
        switch viewModel.unreadCount {
        case ...0: .blue
        case 1...9: .orange
        default: .red
        }
    }

    private func headerButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.glassHeaderButton)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bell.slash")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No notifications yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            if viewModel.isLoading {
                ProgressView().controlSize(.small).padding(.top, 4)
            }
            Spacer()
        }
        .frame(height: 120)
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.notifications) { notification in
                    NotificationRow(notification: notification, viewModel: viewModel)
                        .overlay(alignment: .bottom) {
                            if notification.id != viewModel.notifications.last?.id {
                                Divider().opacity(0.2).padding(.leading, 56)
                            }
                        }
                    if notification.id == viewModel.notifications.last?.id {
                        Color.clear.frame(height: 1).task {
                            await viewModel.loadMore()
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .mask(
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.clear, .black],
                    startPoint: .top,
                    endPoint: .bottom
                ).frame(height: 4)
                Rectangle().fill(.black)
            }
        )
    }

    private func openSettings() {
        NSApp.sendAction(
            Selector(("openSettingsWindow:")),
            to: NSApp.delegate as AnyObject?,
            from: nil
        )
    }
}
