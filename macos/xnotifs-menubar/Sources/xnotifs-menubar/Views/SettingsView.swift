import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var serverURLText: String
    @State private var isValidURL = true

    init(settings: AppSettings) {
        self.settings = settings
        _serverURLText = State(initialValue: settings.serverURL)
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    serverSection
                    appearanceSection
                    pollingSection
                }
                .padding(20)
            }
        }
        .frame(width: 360, height: 340)
        .glassPanelBackground()
    }

    private var titleBar: some View {
        HStack {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Settings")
                .font(.system(size: 13, weight: .bold))

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.glassHeaderButton)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Server", icon: "network")

            TextField("http://localhost:7777", text: $serverURLText)
                .textFieldStyle(.glassField)
                .onChange(of: serverURLText) { _, newValue in
                    isValidURL = URL(string: newValue) != nil
                    if isValidURL {
                        settings.serverURL = newValue
                    }
                }
                .overlay(alignment: .trailing) {
                    if !serverURLText.isEmpty && !isValidURL {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .padding(.trailing, 10)
                    }
                }

            Text("Also settable via XNOTIFS_SERVER env var")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Appearance", icon: "paintpalette")

            Toggle(isOn: $settings.showThumbnails) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show thumbnails")
                        .font(.system(size: 12, weight: .medium))
                    Text("Display media previews in notifications")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.switch)
            .tint(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text("Font scale")
                    .font(.system(size: 12, weight: .medium))

                Picker("", selection: $settings.fontScale) {
                    Text("Small").tag(0.85)
                    Text("Default").tag(1.0)
                    Text("Large").tag(1.15)
                    Text("Extra").tag(1.3)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var pollingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Polling", icon: "clock.arrow.2.circlepath")

            HStack {
                Text("Check every")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                HStack(spacing: 4) {
                    Text("\(settings.pollIntervalSecs)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                    Text("s")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Stepper("", value: $settings.pollIntervalSecs, in: 5...300, step: 5)
                    .labelsHidden()
            }
        }
    }

    private func sectionLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text.uppercased())
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(.secondary)
        .kerning(0.5)
    }
}
