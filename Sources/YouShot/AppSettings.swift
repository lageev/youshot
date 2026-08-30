import Foundation

enum AppSettings {
    private static let blurSigmaKey = "settings.blurSigma"
    private static let blurFeatherKey = "settings.blurFeather"
    private static let windowSnapKey = "settings.windowSnap"
    private static let exportCornerKey = "settings.exportCornerRadius"
    private static let exportShadowBlurKey = "settings.exportShadowBlur"
    private static let exportShadowOpacityKey = "settings.exportShadowOpacity"
    private static let strokeColorKey = "settings.strokeColorIndex"
    private static let strokeCustomHexKey = "settings.strokeCustomHex"
    private static let strokeWidthKey = "settings.strokeWidth"
    private static let rectShapeKey = "settings.rectShape"
    private static let textBackdropKey = "settings.textBackdrop"
    private static let textBackdropColorKey = "settings.textBackdropColorIndex"
    private static let textBackdropCustomHexKey = "settings.textBackdropCustomHex"
    private static let penBrushKey = "settings.penBrush"
    private static let strokeOpacityKey = "settings.strokeOpacity"
    private static let highlightDimKey = "settings.highlightDim"
    private static let watermarkTextKey = "settings.watermarkText"
    private static let watermarkStyleKey = "settings.watermarkStyle"
    private static let watermarkColorKey = "settings.watermarkColorIndex"
    private static let watermarkCustomHexKey = "settings.watermarkCustomHex"
    private static let watermarkSizeKey = "settings.watermarkFontSize"
    private static let watermarkOpacityKey = "settings.watermarkOpacity"

    static var blurSigma: Double {
        get {
            let value = UserDefaults.standard.object(forKey: blurSigmaKey) as? Double
            return value ?? 18
        }
        set { UserDefaults.standard.set(newValue, forKey: blurSigmaKey) }
    }

    static var blurFeather: Double {
        get {
            let value = UserDefaults.standard.object(forKey: blurFeatherKey) as? Double
            return value ?? 40
        }
        set { UserDefaults.standard.set(newValue, forKey: blurFeatherKey) }
    }

    static var windowSnapEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: windowSnapKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: windowSnapKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: windowSnapKey) }
    }

    static var exportCornerRadius: Double {
        get {
            let value = UserDefaults.standard.object(forKey: exportCornerKey) as? Double
            return value ?? 12
        }
        set { UserDefaults.standard.set(newValue, forKey: exportCornerKey) }
    }

    static var exportShadowBlur: Double {
        get {
            let value = UserDefaults.standard.object(forKey: exportShadowBlurKey) as? Double
            return value ?? 18
        }
        set { UserDefaults.standard.set(newValue, forKey: exportShadowBlurKey) }
    }

    static var exportShadowOpacity: Double {
        get {
            let value = UserDefaults.standard.object(forKey: exportShadowOpacityKey) as? Double
            return value ?? 0.4
        }
        set { UserDefaults.standard.set(newValue, forKey: exportShadowOpacityKey) }
    }

    static var strokeColorIndex: Int {
        get { UserDefaults.standard.object(forKey: strokeColorKey) as? Int ?? 0 }
        set { UserDefaults.standard.set(newValue, forKey: strokeColorKey) }
    }

    static var strokeCustomHex: String {
        get { UserDefaults.standard.string(forKey: strokeCustomHexKey) ?? "FF3B30" }
        set { UserDefaults.standard.set(newValue, forKey: strokeCustomHexKey) }
    }

    /// 线条粗细，单位为点
    static var strokeWidth: Double {
        get {
            let value = UserDefaults.standard.object(forKey: strokeWidthKey) as? Double
            return value ?? 3
        }
        set { UserDefaults.standard.set(newValue, forKey: strokeWidthKey) }
    }

    static var penBrush: PenBrush {
        get {
            let raw = UserDefaults.standard.string(forKey: penBrushKey) ?? ""
            return PenBrush(rawValue: raw) ?? .hard
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: penBrushKey) }
    }

    static var strokeOpacity: Double {
        get {
            let value = UserDefaults.standard.object(forKey: strokeOpacityKey) as? Double
            return value ?? 1
        }
        set { UserDefaults.standard.set(newValue, forKey: strokeOpacityKey) }
    }

    static var rectShape: RectShape {
        get {
            let raw = UserDefaults.standard.string(forKey: rectShapeKey) ?? ""
            return RectShape(rawValue: raw) ?? .rounded
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: rectShapeKey) }
    }

    static var textBackdrop: TextBackdrop {
        get {
            let raw = UserDefaults.standard.string(forKey: textBackdropKey) ?? ""
            return TextBackdrop(rawValue: raw) ?? .none
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: textBackdropKey) }
    }

    static var textBackdropColorIndex: Int {
        get { UserDefaults.standard.object(forKey: textBackdropColorKey) as? Int ?? 6 }
        set { UserDefaults.standard.set(newValue, forKey: textBackdropColorKey) }
    }

    static var textBackdropCustomHex: String {
        get { UserDefaults.standard.string(forKey: textBackdropCustomHexKey) ?? "FFFFFF" }
        set { UserDefaults.standard.set(newValue, forKey: textBackdropCustomHexKey) }
    }

    static var highlightDim: Double {
        get {
            let value = UserDefaults.standard.object(forKey: highlightDimKey) as? Double
            return value ?? 0.55
        }
        set { UserDefaults.standard.set(newValue, forKey: highlightDimKey) }
    }

    static var watermarkText: String {
        get { UserDefaults.standard.string(forKey: watermarkTextKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: watermarkTextKey) }
    }

    static var watermarkStyle: WatermarkStyle {
        get {
            let raw = UserDefaults.standard.string(forKey: watermarkStyleKey) ?? ""
            return WatermarkStyle(rawValue: raw) ?? .tile
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: watermarkStyleKey) }
    }

    static var watermarkColorIndex: Int {
        get { UserDefaults.standard.object(forKey: watermarkColorKey) as? Int ?? 6 }
        set { UserDefaults.standard.set(newValue, forKey: watermarkColorKey) }
    }

    static var watermarkCustomHex: String {
        get { UserDefaults.standard.string(forKey: watermarkCustomHexKey) ?? "FFFFFF" }
        set { UserDefaults.standard.set(newValue, forKey: watermarkCustomHexKey) }
    }

    static var watermarkFontSize: Double {
        get {
            let value = UserDefaults.standard.object(forKey: watermarkSizeKey) as? Double
            return value ?? 16
        }
        set { UserDefaults.standard.set(newValue, forKey: watermarkSizeKey) }
    }

    static var watermarkOpacity: Double {
        get {
            let value = UserDefaults.standard.object(forKey: watermarkOpacityKey) as? Double
            return value ?? 0.3
        }
        set { UserDefaults.standard.set(newValue, forKey: watermarkOpacityKey) }
    }
}
