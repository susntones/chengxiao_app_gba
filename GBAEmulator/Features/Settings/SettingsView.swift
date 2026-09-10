import SwiftUI

/// 设置页面
@available(iOS 17.0, *)
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsManager.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("显示") {
                    Picker("缩放模式", selection: $settings.scalingMode) {
                        ForEach(ScalingMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    Picker("画面滤镜", selection: $settings.screenFilter) {
                        ForEach(ScreenFilter.allCases) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }
                    Toggle("画面平滑", isOn: $settings.screenSmoothing)
                }

                Section("声音") {
                    Toggle("启用声音", isOn: $settings.audioEnabled)
                    HStack {
                        Text("音量")
                        Slider(value: $settings.audioVolume, in: 0...1)
                    }
                }

                Section("控制") {
                    HStack {
                        Text("按键透明度")
                        Slider(value: $settings.controlOpacity, in: 0.2...1.0)
                    }
                    HStack {
                        Text("按键大小")
                        Slider(value: $settings.controlScale, in: 0.7...1.5)
                    }
                    Picker("触感反馈", selection: $settings.hapticStrength) {
                        ForEach(HapticStrength.allCases) { strength in
                            Text(strength.displayName).tag(strength)
                        }
                    }
                }

                Section("模拟") {
                    Picker("快进速度", selection: $settings.fastForwardSpeed) {
                        ForEach(FastForwardSpeed.allCases) { speed in
                            Text(speed.displayName).tag(speed)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("支持 2～10 倍速；实际速度取决于设备性能。快进期间自动静音。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("退出时自动存档", isOn: $settings.autoSaveEnabled)
                }

                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("模拟核心")
                        Spacer()
                        Text("mGBA 0.10.3").foregroundColor(.secondary)
                    }
                    NavigationLink("开源许可") { LicensesView() }
                    NavigationLink("法律声明") { LegalNoticeView() }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

struct LicensesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("mGBA").font(.headline)
                Text("版权所有 © 2013–2024 Jeffrey Pfau").font(.caption)
                Text("""
                本源代码形式受 Mozilla 公共许可证 2.0 版约束。若本软件未随附该许可证，\
                可前往 http://mozilla.org/MPL/2.0/ 获取。
                """)
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding()
        }
        .navigationTitle("开源许可")
    }
}

struct LegalNoticeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("法律声明").font(.headline)
                Text("""
                本应用是供个人使用的 Game Boy Advance 模拟器。

                **游戏文件**：本应用不包含任何游戏 ROM。用户须自行提供合法取得的 ROM 文件。下载自己并未拥有的游戏 ROM 可能违反法律。

                **BIOS**：本应用使用 mGBA 内置的开源 BIOS 实现，不包含、也不要求使用任天堂专有 BIOS。

                **商标**：Game Boy Advance 是 Nintendo Co., Ltd. 的商标。本应用与任天堂无隶属、认可或合作关系。

                **免责声明**：本软件按“原样”提供，不作任何形式的保证。开发者不对本应用的任何不当使用负责。
                """)
                .font(.body)
            }
            .padding()
        }
        .navigationTitle("法律声明")
    }
}
