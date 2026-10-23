import Foundation
import AppKit
import SwiftUI

/// High-contrast annotation color preset model supporting hex serialization
/// and conversion to NSColor and SwiftUI Color.
public struct ColorPreset: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var hex: String // Always normalized uppercase "#RRGGBB"

    /// Designated initializer with automatic hex normalization.
    public init(id: UUID = UUID(), name: String, hex: String) {
        self.id = id
        self.name = name
        self.hex = ColorPreset.normalize(hex: hex)
    }

    // MARK: - 8 Standard High-Contrast Defaults

    public static let defaults: [ColorPreset] = [
        ColorPreset(name: "Red", hex: "#FF3B30"),
        ColorPreset(name: "Orange", hex: "#FF9500"),
        ColorPreset(name: "Yellow", hex: "#FFCC00"),
        ColorPreset(name: "Green", hex: "#34C759"),
        ColorPreset(name: "Blue", hex: "#007AFF"),
        ColorPreset(name: "Indigo", hex: "#5856D6"),
        ColorPreset(name: "Purple", hex: "#AF52DE"),
        ColorPreset(name: "Black", hex: "#000000")
    ]

    // MARK: - Hex Validation & Normalization

    /// Checks if a string is a valid hex color code (#RGB, RGB, #RRGGBB, RRGGBB).
    public static func isValid(hex: String) -> Bool {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") {
            clean.removeFirst()
        }
        guard clean.count == 3 || clean.count == 6 else {
            return false
        }
        return clean.allSatisfy { $0.isHexDigit }
    }

    /// Normalizes any valid hex format to standard uppercase "#RRGGBB".
    /// If invalid, falls back to defaultHex (default: "#FF3B30").
    public static func normalize(hex: String, defaultHex: String = "#FF3B30") -> String {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if clean.hasPrefix("#") {
            clean.removeFirst()
        }

        // Expand 3-character hex (#RGB -> #RRGGBB)
        if clean.count == 3 && clean.allSatisfy({ $0.isHexDigit }) {
            let chars = Array(clean)
            let r = String(repeating: chars[0], count: 2)
            let g = String(repeating: chars[1], count: 2)
            let b = String(repeating: chars[2], count: 2)
            return "#\(r)\(g)\(b)"
        }

        // Standard 6-character hex
        if clean.count == 6 && clean.allSatisfy({ $0.isHexDigit }) {
            return "#\(clean)"
        }

        // Fallback for invalid input
        return defaultHex.uppercased().hasPrefix("#") ? defaultHex.uppercased() : "#\(defaultHex.uppercased())"
    }

    /// Parses normalized hex string into normalized RGB double components (0.0 ... 1.0).
    /// Returns nil if hex string is invalid.
    public static func parseRGB(hex: String) -> (r: Double, g: Double, b: Double)? {
        guard isValid(hex: hex) else {
            return nil
        }
        let normalized = normalize(hex: hex)
        var clean = normalized
        if clean.hasPrefix("#") {
            clean.removeFirst()
        }
        guard clean.count == 6, let value = UInt64(clean, radix: 16) else {
            return nil
        }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return (r, g, b)
    }

    // MARK: - AppKit and SwiftUI Color Conversions

    /// Converts normalized hex string to AppKit NSColor in sRGB color space.
    public func toNSColor() -> NSColor {
        guard let rgb = ColorPreset.parseRGB(hex: hex) else {
            return NSColor(srgbRed: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)
        }
        return NSColor(srgbRed: CGFloat(rgb.r), green: CGFloat(rgb.g), blue: CGFloat(rgb.b), alpha: 1.0)
    }

    /// Converts normalized hex string to SwiftUI Color in sRGB color space.
    public func toColor() -> SwiftUI.Color {
        guard let rgb = ColorPreset.parseRGB(hex: hex) else {
            return SwiftUI.Color(.sRGB, red: 1.0, green: 0.23, blue: 0.19, opacity: 1.0)
        }
        return SwiftUI.Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 1.0)
    }
}
