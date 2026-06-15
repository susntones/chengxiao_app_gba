import SwiftUI

/// Settings screen
@available(iOS 17.0, *)
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsManager.shared

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Display Section
                Section("Display") {
                    Picker("Scaling Mode", selection: $settings.scalingMode) {
                        ForEach(ScalingMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    Picker("Screen Filter", selection: $settings.screenFilter) {
                        ForEach(ScreenFilter.allCases) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }

                    Toggle("Screen Smoothing", isOn: $settings.screenSmoothing)
                }

                // MARK: - Audio Section
                Section("Audio") {
                    Toggle("Audio Enabled", isOn: $settings.audioEnabled)

                    HStack {
                        Text("Volume")
                        Slider(value: $settings.audioVolume, in: 0...1)
                    }
                }

                // MARK: - Controls Section
                Section("Controls") {
                    HStack {
                        Text("Button Opacity")
                        Slider(value: $settings.controlOpacity, in: 0.2...1.0)
                    }

                    HStack {
                        Text("Button Scale")
                        Slider(value: $settings.controlScale, in: 0.7...1.5)
                    }

                    Picker("Haptic Feedback", selection: $settings.hapticStrength) {
                        ForEach(HapticStrength.allCases) { strength in
                            Text(strength.displayName).tag(strength)
                        }
                    }
                }

                // MARK: - Emulation Section
                Section("Emulation") {
                    Picker("Fast Forward Speed", selection: $settings.fastForwardSpeed) {
                        ForEach(FastForwardSpeed.allCases) { speed in
                            Text(speed.displayName).tag(speed)
                        }
                    }

                    Toggle("Auto-Save on Exit", isOn: $settings.autoSaveEnabled)
                }

                // MARK: - About Section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Emulation Core")
                        Spacer()
                        Text("mGBA 0.10.3")
                            .foregroundColor(.secondary)
                    }

                    NavigationLink("Licenses") {
                        LicensesView()
                    }

                    NavigationLink("Legal Notice") {
                        LegalNoticeView()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Licenses View

struct LicensesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    Text("mGBA")
                        .font(.headline)
                    Text("Copyright (c) 2013-2024 Jeffrey Pfau")
                        .font(.caption)
                    Text("""
                    This Source Code Form is subject to the terms of the Mozilla Public \
                    License, v. 2.0. If a copy of the MPL was not distributed with this \
                    file, You can obtain one at http://mozilla.org/MPL/2.0/.
                    """)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Licenses")
    }
}

// MARK: - Legal Notice View

struct LegalNoticeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Legal Notice")
                    .font(.headline)

                Text("""
                This application is a Game Boy Advance emulator for personal use.

                **ROM Files**: This app does not include any game ROM files. Users are \
                responsible for providing their own legally obtained ROM files. It is \
                illegal to download ROM files for games you do not own.

                **BIOS**: This app uses mGBA's built-in open-source BIOS implementation. \
                No proprietary Nintendo BIOS is included or required.

                **Trademarks**: Game Boy Advance is a trademark of Nintendo Co., Ltd. \
                This app is not affiliated with, endorsed by, or connected to Nintendo \
                in any way.

                **Disclaimer**: This software is provided "as is" without warranty of \
                any kind. The developers are not responsible for any misuse of this application.
                """)
                .font(.body)
            }
            .padding()
        }
        .navigationTitle("Legal Notice")
    }
}
