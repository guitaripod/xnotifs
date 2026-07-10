import SwiftUI
import AppKit
import Combine

private let glassCornerRadius: CGFloat = 14

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: Any?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private let viewModel = NotificationsViewModel()
    private let settings = AppSettings.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()
        setupEventMonitor()
        viewModel.startPolling()
        updateStatusIcon()
        observeUnreadCount()
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.stopPolling()
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    @objc func openSettingsWindow(_ sender: Any?) {
        if settingsWindow == nil {
            let hostingView = NSHostingView(
                rootView: SettingsView(settings: settings) { [weak self] in
                    self?.settingsWindow?.close()
                }
            )
            let window = glassWindow(size: NSSize(width: 380, height: 380), hostingView: hostingView)
            window.title = "xnotifs Settings"
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func quitApp() {
        viewModel.stopPolling()
        NSApp.terminate(nil)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "bell.fill",
                accessibilityDescription: "xnotifs"
            )?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            )
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: .leftMouseUp)
        }

        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(
                title: "Settings...",
                action: #selector(openSettingsWindow),
                keyEquivalent: ","
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit xnotifs",
                action: #selector(quitApp),
                keyEquivalent: "q"
            )
        )
        statusItem.menu = menu
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 420, height: 620)
        popover.behavior = .transient
        popover.animates = true

        let contentView = NotificationListView(viewModel: viewModel)
            .environmentObject(settings)
            .frame(width: 420)

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 420, height: 620)
        hostingView.autoresizingMask = [.width, .height]

        let visualEffect = glassVisualEffectView(frame: hostingView.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.addSubview(hostingView)

        let viewController = NSViewController()
        viewController.view = visualEffect
        popover.contentViewController = viewController
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.closePopover()
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        if let window = popover.contentViewController?.view.window {
            window.level = .floating
            window.hasShadow = true
            window.isOpaque = false
            window.backgroundColor = .clear
        }
    }

    private func closePopover() {
        popover.performClose(nil)
    }

    private func observeUnreadCount() {
        viewModel.$unreadCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusIcon()
            }
            .store(in: &cancellables)
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let count = viewModel.unreadCount
        let color: NSColor = switch count {
        case ...0: .secondaryLabelColor
        case 1...9: .systemOrange
        default: .systemRed
        }
        button.contentTintColor = color
        button.attributedTitle = count > 0
            ? NSAttributedString(
                string: " \(count)",
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            )
            : NSAttributedString(string: "")
    }
}

private func glassVisualEffectView(frame: NSRect) -> NSVisualEffectView {
    let view = NSVisualEffectView(frame: frame)
    view.material = .hudWindow
    view.blendingMode = .behindWindow
    view.state = .active
    view.wantsLayer = true
    view.layer?.cornerRadius = glassCornerRadius
    view.layer?.masksToBounds = true
    return view
}

private func glassWindow(size: NSSize, hostingView: NSHostingView<some View>) -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.titled, .closable, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    window.level = .floating
    window.hasShadow = true
    window.isOpaque = false
    window.backgroundColor = .clear

    let visualEffect = glassVisualEffectView(frame: NSRect(origin: .zero, size: size))
    visualEffect.addSubview(hostingView)
    hostingView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
        hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
        hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
        hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
    ])

    window.contentView = visualEffect
    return window
}
