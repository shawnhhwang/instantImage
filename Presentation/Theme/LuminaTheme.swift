import SwiftUI
import AppKit

// MARK: - Lumina Design System (Awwwards-Caliber Aesthetic Tokens)

public enum LuminaTheme {
    // MARK: - Colors
    public enum Colors {
        // Deep Obsidian Backgrounds
        public static let bgDeep = Color(red: 0.04, green: 0.045, blue: 0.06)          // #0A0B0F
        public static let bgCanvas = Color(red: 0.065, green: 0.07, blue: 0.09)        // #111217
        public static let bgSurface = Color(red: 0.095, green: 0.10, blue: 0.13)       // #181A21
        public static let bgSurfaceElevated = Color(red: 0.12, green: 0.13, blue: 0.17) // #1F212B
        public static let bgGlass = Color.white.opacity(0.04)
        public static let bgGlassHover = Color.white.opacity(0.08)
        public static let bgGlassActive = Color.white.opacity(0.14)
        
        // Brand & Functional Accents
        public static let cyanAccent = Color(red: 0.0, green: 0.90, blue: 1.0)          // #00E5FF - Lumina Neon Cyan
        public static let amberGold = Color(red: 1.0, green: 0.72, blue: 0.12)          // #FFB81E - Rating Gold
        public static let neonCoral = Color(red: 1.0, green: 0.22, blue: 0.38)          // #FF3861 - Tag Red / Alert
        public static let mintEmerald = Color(red: 0.0, green: 0.90, blue: 0.46)        // #00E676 - Success / Auto Sync
        public static let electricIndigo = Color(red: 0.40, green: 0.42, blue: 1.0)     // #666BFF - Focus highlight
        public static let skyBlue = Color(red: 0.22, green: 0.74, blue: 1.0)            // #38BDFF - Cold tint
        
        // Specular & Border Strokes
        public static let borderSubtle = Color.white.opacity(0.07)
        public static let borderMedium = Color.white.opacity(0.14)
        public static let borderStrong = Color.white.opacity(0.24)
        public static let borderCyan = cyanAccent.opacity(0.6)
        
        // Typography Colors
        public static let textPrimary = Color.white.opacity(0.96)
        public static let textSecondary = Color.white.opacity(0.65)
        public static let textTertiary = Color.white.opacity(0.40)
        public static let textMuted = Color.white.opacity(0.25)
    }
    
    // MARK: - Gradients
    public enum Gradients {
        public static let brandCyanIndigo = LinearGradient(
            colors: [Colors.cyanAccent, Colors.electricIndigo],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        public static let glassHighlight = LinearGradient(
            colors: [Color.white.opacity(0.18), Color.white.opacity(0.02)],
            startPoint: .top,
            endPoint: .bottom
        )
        
        public static let goldRadiance = LinearGradient(
            colors: [Colors.amberGold, Color(red: 1.0, green: 0.45, blue: 0.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        public static let darkCardGradient = LinearGradient(
            colors: [Colors.bgSurfaceElevated, Colors.bgSurface],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        public static let tempGradient = LinearGradient(
            colors: [Colors.skyBlue, Color.white.opacity(0.8), Colors.amberGold],
            startPoint: .leading,
            endPoint: .trailing
        )
        
        public static let tintGradient = LinearGradient(
            colors: [Colors.mintEmerald, Color.white.opacity(0.8), Color(red: 0.95, green: 0.2, blue: 0.8)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    // MARK: - Shadows
    public enum Shadows {
        public static let ambient = Color.black.opacity(0.35)
        public static let glowCyan = Colors.cyanAccent.opacity(0.25)
        public static let glowGold = Colors.amberGold.opacity(0.25)
        public static let glowCoral = Colors.neonCoral.opacity(0.25)
    }
    
    // MARK: - Radius
    public enum Radius {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 6
        public static let md: CGFloat = 10
        public static let lg: CGFloat = 14
        public static let xl: CGFloat = 20
        public static let pill: CGFloat = 999
    }
}

// MARK: - View Modifiers for Glassmorphism & Micro-Interactions

public struct LuminaGlassStyle: ViewModifier {
    var cornerRadius: CGFloat = LuminaTheme.Radius.md
    var isElevated: Bool = false
    var strokeColor: Color = LuminaTheme.Colors.borderSubtle
    var strokeWidth: CGFloat = 1.0
    
    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isElevated ? LuminaTheme.Colors.bgSurfaceElevated.opacity(0.75) : LuminaTheme.Colors.bgSurface.opacity(0.65))
                    .background(
                        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(strokeColor, lineWidth: strokeWidth)
            )
            .shadow(color: LuminaTheme.Shadows.ambient, radius: isElevated ? 14 : 6, x: 0, y: isElevated ? 6 : 2)
    }
}

public struct LuminaGlowModifier: ViewModifier {
    var color: Color = LuminaTheme.Colors.cyanAccent
    var radius: CGFloat = 8
    var isActive: Bool = true
    
    public func body(content: Content) -> some View {
        if isActive {
            content
                .shadow(color: color.opacity(0.45), radius: radius, x: 0, y: 0)
        } else {
            content
        }
    }
}

public extension View {
    func luminaGlass(cornerRadius: CGFloat = LuminaTheme.Radius.md, isElevated: Bool = false, strokeColor: Color = LuminaTheme.Colors.borderSubtle, strokeWidth: CGFloat = 1.0) -> some View {
        self.modifier(LuminaGlassStyle(cornerRadius: cornerRadius, isElevated: isElevated, strokeColor: strokeColor, strokeWidth: strokeWidth))
    }
    
    func luminaGlow(color: Color = LuminaTheme.Colors.cyanAccent, radius: CGFloat = 8, isActive: Bool = true) -> some View {
        self.modifier(LuminaGlowModifier(color: color, radius: radius, isActive: isActive))
    }
}
