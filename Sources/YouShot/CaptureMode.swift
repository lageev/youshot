import Foundation

enum CaptureMode: String, CaseIterable, Identifiable {
    case currentDisplay
    case allDisplays
    case region

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentDisplay: return "当前屏幕"
        case .allDisplays: return "所有屏幕"
        case .region: return "区域选取"
        }
    }
}
