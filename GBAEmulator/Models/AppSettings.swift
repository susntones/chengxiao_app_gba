import SwiftUI

// MARK: - Scaling Mode
enum ScalingMode: String, CaseIterable, Identifiable {
    case fit = "fit"
    case fill = "fill"
    case integer = "integer"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fit: return "适应屏幕（留黑边）"
        case .fill: return "填满屏幕"
        case .integer: return "整数倍缩放"
        }
    }
}

// MARK: - Screen Filter
enum ScreenFilter: String, CaseIterable, Identifiable {
    case nearest = "nearest"
    case bilinear = "bilinear"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nearest: return "清晰（最近邻）"
        case .bilinear: return "平滑（双线性）"
        }
    }
}

// MARK: - Haptic Strength
enum HapticStrength: String, CaseIterable, Identifiable {
    case off = "off"
    case light = "light"
    case medium = "medium"
    case heavy = "heavy"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "关闭"
        case .light: return "轻"
        case .medium: return "中"
        case .heavy: return "强"
        }
    }
}

// MARK: - Fast Forward Speed
enum FastForwardSpeed: Double, CaseIterable, Identifiable {
    case x2 = 2.0
    case x3 = 3.0
    case x4 = 4.0
    case x5 = 5.0
    case x6 = 6.0
    case x7 = 7.0
    case x8 = 8.0
    case x9 = 9.0
    case x10 = 10.0

    var id: Double { rawValue }
    var displayName: String { "\(Int(rawValue)) 倍" }
}

// MARK: - App Settings Keys
struct AppSettingsKeys {
    // Display
    static let scalingMode = "scalingMode"
    static let screenFilter = "screenFilter"
    static let screenSmoothing = "screenSmoothing"

    // Audio
    static let audioEnabled = "audioEnabled"
    static let audioVolume = "audioVolume"

    // Controls
    static let controlOpacity = "controlOpacity"
    static let controlScale = "controlScale"
    static let hapticStrength = "hapticStrength"
    static let showControlsWithController = "showControlsWithController"

    // Emulation
    static let fastForwardSpeed = "fastForwardSpeed"
    static let autoSaveEnabled = "autoSaveEnabled"
    static let autoSaveInterval = "autoSaveInterval"

    // Library
    static let libraryViewMode = "libraryViewMode"
    static let librarySortOrder = "librarySortOrder"
}

// MARK: - Settings Manager
@available(iOS 17.0, *)
@Observable
final class SettingsManager {
    static let shared = SettingsManager()

    // Display
    var scalingMode: ScalingMode {
        get { ScalingMode(rawValue: UserDefaults.standard.string(forKey: AppSettingsKeys.scalingMode) ?? "fit") ?? .fit }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: AppSettingsKeys.scalingMode) }
    }

    var screenFilter: ScreenFilter {
        get { ScreenFilter(rawValue: UserDefaults.standard.string(forKey: AppSettingsKeys.screenFilter) ?? "nearest") ?? .nearest }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: AppSettingsKeys.screenFilter) }
    }

    var screenSmoothing: Bool {
        get { UserDefaults.standard.bool(forKey: AppSettingsKeys.screenSmoothing) }
        set { UserDefaults.standard.set(newValue, forKey: AppSettingsKeys.screenSmoothing) }
    }

    // Audio
    var audioEnabled: Bool {
        get { UserDefaults.standard.object(forKey: AppSettingsKeys.audioEnabled) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: AppSettingsKeys.audioEnabled) }
    }

    var audioVolume: Float {
        get { UserDefaults.standard.object(forKey: AppSettingsKeys.audioVolume) as? Float ?? 1.0 }
        set { UserDefaults.standard.set(newValue, forKey: AppSettingsKeys.audioVolume) }
    }

    // Controls
    var controlOpacity: Double {
        get { UserDefaults.standard.object(forKey: AppSettingsKeys.controlOpacity) as? Double ?? 0.7 }
        set { UserDefaults.standard.set(newValue, forKey: AppSettingsKeys.controlOpacity) }
    }

    var controlScale: Double {
        get { UserDefaults.standard.object(forKey: AppSettingsKeys.controlScale) as? Double ?? 1.0 }
        set { UserDefaults.standard.set(newValue, forKey: AppSettingsKeys.controlScale) }
    }

    var hapticStrength: HapticStrength {
        get { HapticStrength(rawValue: UserDefaults.standard.string(forKey: AppSettingsKeys.hapticStrength) ?? "medium") ?? .medium }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: AppSettingsKeys.hapticStrength) }
    }

    // Emulation
    var fastForwardSpeed: FastForwardSpeed {
        get { FastForwardSpeed(rawValue: UserDefaults.standard.object(forKey: AppSettingsKeys.fastForwardSpeed) as? Double ?? 2.0) ?? .x2 }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: AppSettingsKeys.fastForwardSpeed) }
    }

    var autoSaveEnabled: Bool {
        get { UserDefaults.standard.object(forKey: AppSettingsKeys.autoSaveEnabled) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: AppSettingsKeys.autoSaveEnabled) }
    }

    var autoSaveInterval: Int {
        get { UserDefaults.standard.object(forKey: AppSettingsKeys.autoSaveInterval) as? Int ?? 300 }
        set { UserDefaults.standard.set(newValue, forKey: AppSettingsKeys.autoSaveInterval) }
    }

    private init() {}
}
