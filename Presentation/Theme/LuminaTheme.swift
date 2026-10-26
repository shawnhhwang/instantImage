import SwiftUI
import AppKit

// MARK: - Lumina Design System (Bright Tech Style / 明亮科技風格)

public enum LuminaTheme {
    // MARK: - Colors
    public enum Colors {
        // Crisp, Luminous Light Tech Backgrounds
        public static let bgDeep = Color(red: 0.94, green: 0.95, blue: 0.97)           // #F0F2F7 - Clean Sidebar
        public static let bgCanvas = Color(red: 0.97, green: 0.98, blue: 0.99)         // #F8F9FC - Main Photo Canvas
        public static let bgSurface = Color.white                                       // #FFFFFF - Pure White Surface
        public static let bgSurfaceElevated = Color.white                               // #FFFFFF - Floating Card
        public static let bgGlass = Color.white.opacity(0.88)
        public static let bgGlassHover = Color(red: 0.93, green: 0.95, blue: 0.98)
        public static let bgGlassActive = Color(red: 0.88, green: 0.92, blue: 0.98)
        
        // Studio Stage Neutral (Surrounding open image without darkening it)
        public static let darkroomCanvas = Color(red: 0.92, green: 0.93, blue: 0.95)   // #EBEFF3 - Clean Studio Gray
        
        // High-Tech Luminous Accents
        public static let cyanAccent = Color(red: 0.0, green: 0.48, blue: 1.0)          // #007AFF - Electric Tech Blue
        public static let amberGold = Color(red: 0.96, green: 0.62, blue: 0.05)         // #F59E0B - Rating Gold
        public static let neonCoral = Color(red: 0.93, green: 0.22, blue: 0.32)         // #ED3851 - Tag Red / Alert
        public static let mintEmerald = Color(red: 0.04, green: 0.72, blue: 0.44)       // #0BB870 - Success / Active status
        public static let electricIndigo = Color(red: 0.39, green: 0.35, blue: 0.95)    // #6366F1 - Focus Violet
        public static let skyBlue = Color(red: 0.12, green: 0.65, blue: 0.95)           // #1FA6F3 - Cold tint
        
        // Hairline Tech Borders
        public static let borderSubtle = Color.black.opacity(0.06)
        public static let borderMedium = Color.black.opacity(0.12)
        public static let borderStrong = Color.black.opacity(0.20)
        public static let borderCyan = cyanAccent.opacity(0.40)
        
        // Razor-Sharp High Contrast Typography
        public static let textPrimary = Color(red: 0.07, green: 0.10, blue: 0.16)       // #121A29 - Deep Slate
        public static let textSecondary = Color(red: 0.30, green: 0.36, blue: 0.45)     // #4D5C73 - Cool Slate
        public static let textTertiary = Color(red: 0.55, green: 0.60, blue: 0.68)      // #8C99AD - Muted Chrome
        public static let textMuted = Color(red: 0.72, green: 0.76, blue: 0.82)         // #B8C2D1 - Light Slate
    }
    
    // MARK: - Gradients
    public enum Gradients {
        public static let brandCyanIndigo = LinearGradient(
            colors: [Colors.cyanAccent, Colors.electricIndigo],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        public static let glassHighlight = LinearGradient(
            colors: [Color.white, Color(red: 0.97, green: 0.98, blue: 0.99)],
            startPoint: .top,
            endPoint: .bottom
        )
        
        public static let goldRadiance = LinearGradient(
            colors: [Colors.amberGold, Color(red: 1.0, green: 0.50, blue: 0.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        public static let lightCardGradient = LinearGradient(
            colors: [Color.white, Color(red: 0.98, green: 0.985, blue: 0.995)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        public static let tempGradient = LinearGradient(
            colors: [Colors.skyBlue, Color.white, Colors.amberGold],
            startPoint: .leading,
            endPoint: .trailing
        )
        
        public static let tintGradient = LinearGradient(
            colors: [Colors.mintEmerald, Color.white, Color(red: 0.90, green: 0.20, blue: 0.70)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    // MARK: - Shadows
    public enum Shadows {
        public static let ambient = Color.black.opacity(0.06)
        public static let glowCyan = Colors.cyanAccent.opacity(0.20)
        public static let glowGold = Colors.amberGold.opacity(0.22)
        public static let glowCoral = Colors.neonCoral.opacity(0.22)
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
    
    // MARK: - Motion & Springs (Apple Design Award Motion Standards)
    public enum Animation {
        public static let springSnappy = SwiftUI.Animation.spring(response: 0.20, dampingFraction: 0.76)
        public static let springSmooth = SwiftUI.Animation.spring(response: 0.28, dampingFraction: 0.82)
        public static let springBouncy = SwiftUI.Animation.spring(response: 0.34, dampingFraction: 0.68)
        public static let easeOutFast = SwiftUI.Animation.easeOut(duration: 0.16)
    }
}

public extension SwiftUI.Animation {
    static var springSnappy: SwiftUI.Animation { LuminaTheme.Animation.springSnappy }
    static var springSmooth: SwiftUI.Animation { LuminaTheme.Animation.springSmooth }
    static var springBouncy: SwiftUI.Animation { LuminaTheme.Animation.springBouncy }
    static var easeOutFast: SwiftUI.Animation { LuminaTheme.Animation.easeOutFast }
}

// MARK: - View Modifiers for Bright Tech Glassmorphism

public struct LuminaGlassStyle: ViewModifier {
    var cornerRadius: CGFloat = LuminaTheme.Radius.md
    var isElevated: Bool = false
    var strokeColor: Color = LuminaTheme.Colors.borderSubtle
    var strokeWidth: CGFloat = 1.0
    
    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isElevated ? Color.white.opacity(0.96) : Color.white.opacity(0.88))
                    .background(
                        VisualEffectView(material: .sidebar, blendingMode: .withinWindow)
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(strokeColor, lineWidth: strokeWidth)
            )
            .shadow(color: LuminaTheme.Shadows.ambient, radius: isElevated ? 12 : 5, x: 0, y: isElevated ? 4 : 2)
    }
}

public struct LuminaGlowModifier: ViewModifier {
    var color: Color = LuminaTheme.Colors.cyanAccent
    var radius: CGFloat = 8
    var isActive: Bool = true
    
    public func body(content: Content) -> some View {
        if isActive {
            content
                .shadow(color: color.opacity(0.28), radius: radius, x: 0, y: 0)
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

// MARK: - Native Mac Keyboard Keycap (Apple Pro App Standard)
public struct LuminaKeycap: View {
    let key: String
    var isAccent: Bool = false
    
    public init(_ key: String, isAccent: Bool = false) {
        self.key = key
        self.isAccent = isAccent
    }
    
    public var body: some View {
        Text(key)
            .font(.system(size: 9.5, weight: .bold, design: .rounded))
            .foregroundColor(isAccent ? LuminaTheme.Colors.cyanAccent : LuminaTheme.Colors.textSecondary)
            .padding(.vertical, 2)
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.12), radius: 1, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(isAccent ? LuminaTheme.Colors.cyanAccent.opacity(0.4) : Color.black.opacity(0.12), lineWidth: 0.75)
            )
    }
}
