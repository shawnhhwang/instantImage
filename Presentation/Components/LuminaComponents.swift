import SwiftUI
import AppKit

// MARK: - Awwwards-Level Reusable Design Components

/// Precision Camera Viewfinder Corner Brackets for active card focus
public struct ViewfinderBracket: View {
    var color: Color = LuminaTheme.Colors.cyanAccent
    var size: CGFloat = 10
    var thickness: CGFloat = 2.0
    
    public init(color: Color = LuminaTheme.Colors.cyanAccent, size: CGFloat = 10, thickness: CGFloat = 2.0) {
        self.color = color
        self.size = size
        self.thickness = thickness
    }
    
    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            
            Path { path in
                // Top-Left bracket
                path.move(to: CGPoint(x: 0, y: size))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: size, y: 0))
                
                // Top-Right bracket
                path.move(to: CGPoint(x: w - size, y: 0))
                path.addLine(to: CGPoint(x: w, y: 0))
                path.addLine(to: CGPoint(x: w, y: size))
                
                // Bottom-Left bracket
                path.move(to: CGPoint(x: 0, y: h - size))
                path.addLine(to: CGPoint(x: 0, y: h))
                path.addLine(to: CGPoint(x: size, y: h))
                
                // Bottom-Right bracket
                path.move(to: CGPoint(x: w - size, y: h))
                path.addLine(to: CGPoint(x: w, y: h))
                path.addLine(to: CGPoint(x: w, y: h - size))
            }
            .stroke(color, lineWidth: thickness)
            .shadow(color: color.opacity(0.6), radius: 3, x: 0, y: 0)
        }
    }
}

/// Sleek Micro Badge (e.g., RAW, 24MP, ISO 100)
public struct LuminaBadge: View {
    let text: String
    var icon: String? = nil
    var color: Color = LuminaTheme.Colors.textSecondary
    var bgColor: Color = Color.black.opacity(0.55)
    var strokeColor: Color = Color.white.opacity(0.12)
    
    public init(_ text: String, icon: String? = nil, color: Color = LuminaTheme.Colors.textSecondary, bgColor: Color = Color.black.opacity(0.55), strokeColor: Color = Color.white.opacity(0.12)) {
        self.text = text
        self.icon = icon
        self.color = color
        self.bgColor = bgColor
        self.strokeColor = strokeColor
    }
    
    public var body: some View {
        HStack(spacing: 3) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
            }
            Text(text)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.3)
        }
        .foregroundColor(color)
        .padding(.vertical, 2.5)
        .padding(.horizontal, 5.5)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(bgColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(strokeColor, lineWidth: 0.75)
                )
        )
    }
}

/// Tactical Icon Button with hover glow and spring bounce
public struct LuminaIconButton: View {
    let icon: String
    var title: String? = nil
    var shortcut: String? = nil
    var isActive: Bool = false
    var activeColor: Color = LuminaTheme.Colors.cyanAccent
    var size: CGFloat = 32
    var iconSize: CGFloat = 13
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    
    public init(
        icon: String,
        title: String? = nil,
        shortcut: String? = nil,
        isActive: Bool = false,
        activeColor: Color = LuminaTheme.Colors.cyanAccent,
        size: CGFloat = 32,
        iconSize: CGFloat = 13,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.shortcut = shortcut
        self.isActive = isActive
        self.activeColor = activeColor
        self.size = size
        self.iconSize = iconSize
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isActive ? activeColor.opacity(0.2) : (isHovered ? LuminaTheme.Colors.bgGlassHover : Color.black.opacity(0.45)))
                    .overlay(
                        Circle()
                            .stroke(isActive ? activeColor.opacity(0.7) : (isHovered ? Color.white.opacity(0.2) : Color.white.opacity(0.08)), lineWidth: 1)
                    )
                    .shadow(color: isActive ? activeColor.opacity(0.35) : Color.black.opacity(0.2), radius: isActive ? 6 : 2, x: 0, y: 1)
                
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundColor(isActive ? activeColor : (isHovered ? .white : LuminaTheme.Colors.textSecondary))
            }
            .frame(width: size, height: size)
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isActive)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { isHovered = $0 }
        .help(helpText)
    }
    
    private var helpText: String {
        var res = title ?? ""
        if let sc = shortcut {
            res += " (\(sc))"
        }
        return res
    }
}

/// Awwwards-Caliber Pill Segment / Button for Filters & View Switchers
public struct LuminaPillButton: View {
    var icon: String? = nil
    let label: String
    var count: Int? = nil
    var isSelected: Bool = false
    var selectedColor: Color = LuminaTheme.Colors.cyanAccent
    var shortcut: String? = nil
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    
    public init(
        icon: String? = nil,
        label: String,
        count: Int? = nil,
        isSelected: Bool = false,
        selectedColor: Color = LuminaTheme.Colors.cyanAccent,
        shortcut: String? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.label = label
        self.count = count
        self.isSelected = isSelected
        self.selectedColor = selectedColor
        self.shortcut = shortcut
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .bold))
                }
                
                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                
                if let count = count {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.vertical, 1)
                        .padding(.horizontal, 4.5)
                        .background(
                            Capsule()
                                .fill(isSelected ? selectedColor.opacity(0.25) : Color.white.opacity(0.08))
                        )
                }
            }
            .foregroundColor(isSelected ? selectedColor : (isHovered ? LuminaTheme.Colors.textPrimary : LuminaTheme.Colors.textSecondary))
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(
                Capsule()
                    .fill(isSelected ? selectedColor.opacity(0.14) : (isHovered ? LuminaTheme.Colors.bgGlassHover : LuminaTheme.Colors.bgGlass))
                    .overlay(
                        Capsule()
                            .stroke(isSelected ? selectedColor.opacity(0.5) : (isHovered ? Color.white.opacity(0.16) : Color.white.opacity(0.06)), lineWidth: 1)
                    )
            )
            .luminaGlow(color: selectedColor, radius: 6, isActive: isSelected)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.75), value: isHovered)
            .animation(.spring(response: 0.18, dampingFraction: 0.75), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { isHovered = $0 }
        .help(shortcut != nil ? "\(label) (\(shortcut!))" : label)
    }
}

/// Interactive 5-Star Rating Control with luminous particle effects
public struct LuminaRatingBar: View {
    @Binding var rating: Int
    var maxRating: Int = 5
    var starSize: CGFloat = 11
    var spacing: CGFloat = 3
    var allowClear: Bool = true
    var onRatingChanged: ((Int) -> Void)? = nil
    
    @State private var hoverStar: Int? = nil
    
    public init(
        rating: Binding<Int>,
        maxRating: Int = 5,
        starSize: CGFloat = 11,
        spacing: CGFloat = 3,
        allowClear: Bool = true,
        onRatingChanged: ((Int) -> Void)? = nil
    ) {
        self._rating = rating
        self.maxRating = maxRating
        self.starSize = starSize
        self.spacing = spacing
        self.allowClear = allowClear
        self.onRatingChanged = onRatingChanged
    }
    
    public var body: some View {
        HStack(spacing: spacing) {
            ForEach(1...maxRating, id: \.self) { star in
                let isFilled = (hoverStar ?? rating) >= star
                
                Image(systemName: isFilled ? "star.fill" : "star")
                    .font(.system(size: starSize, weight: .bold))
                    .foregroundColor(isFilled ? LuminaTheme.Colors.amberGold : Color.white.opacity(0.18))
                    .luminaGlow(color: LuminaTheme.Colors.amberGold, radius: 4, isActive: isFilled)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if allowClear && rating == star {
                            rating = 0
                        } else {
                            rating = star
                        }
                        onRatingChanged?(rating)
                    }
                    .onHover { hovering in
                        hoverStar = hovering ? star : nil
                    }
                    .scaleEffect(hoverStar == star ? 1.25 : 1.0)
                    .animation(.spring(response: 0.15, dampingFraction: 0.6), value: hoverStar)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.45))
                .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.75))
        )
    }
}

/// High-Precision Gradient Tone Slider for Lightroom Darkroom Controls
public struct LuminaPrecisionSlider: View {
    let label: String
    let valueDisplay: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let defaultValue: Float
    var trackGradient: LinearGradient? = nil
    var onReset: (() -> Void)? = nil
    
    @State private var isHovered: Bool = false
    
    public init(
        label: String,
        valueDisplay: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        defaultValue: Float = 0.0,
        trackGradient: LinearGradient? = nil,
        onReset: (() -> Void)? = nil
    ) {
        self.label = label
        self.valueDisplay = valueDisplay
        self._value = value
        self.range = range
        self.defaultValue = defaultValue
        self.trackGradient = trackGradient
        self.onReset = onReset
    }
    
    public var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(LuminaTheme.Colors.textSecondary)
                
                Spacer()
                
                // Clickable numeric badge to reset to zero
                Button(action: {
                    value = defaultValue
                    onReset?()
                }) {
                    Text(valueDisplay)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(abs(value - defaultValue) > 0.001 ? LuminaTheme.Colors.cyanAccent : LuminaTheme.Colors.textPrimary)
                        .padding(.vertical, 1)
                        .padding(.horizontal, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .fill(Color.black.opacity(0.4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                        .stroke(abs(value - defaultValue) > 0.001 ? LuminaTheme.Colors.cyanAccent.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 0.75)
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .help("點擊重設為預設值")
            }
            
            // Custom Track Slider
            ZStack(alignment: .leading) {
                // Background Track
                GeometryReader { geo in
                    let w = geo.size.width
                    let h: CGFloat = 5
                    let progress = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
                    let zeroRatio = CGFloat((defaultValue - range.lowerBound) / (range.upperBound - range.lowerBound))
                    let zeroX = w * zeroRatio
                    let currentX = w * min(1.0, max(0.0, progress))
                    
                    ZStack(alignment: .leading) {
                        // Base track bar
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(trackGradient ?? LinearGradient(colors: [Color.white.opacity(0.12)], startPoint: .leading, endPoint: .trailing))
                            .frame(height: h)
                        
                        // Active colored delta bar from default tick
                        let barLeft = min(zeroX, currentX)
                        let barWidth = max(2, abs(currentX - zeroX))
                        
                        if trackGradient == nil {
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(LuminaTheme.Colors.cyanAccent)
                                .frame(width: barWidth, height: h)
                                .offset(x: barLeft)
                        }
                        
                        // Default zero tick indicator
                        Rectangle()
                            .fill(Color.white.opacity(0.6))
                            .frame(width: 1.5, height: 7)
                            .offset(x: zeroX - 0.75)
                    }
                    .frame(height: geo.size.height)
                }
                .frame(height: 12)
                
                // Native mini slider overlay with transparent track to retain native dragging mechanics
                Slider(value: $value, in: range)
                    .controlSize(.mini)
                    .opacity(0.85)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Glassmorphic Search Bar with shortcut indicator
public struct LuminaSearchField: View {
    @Binding var text: String
    var placeholder: String = "搜尋檔名、相機、鏡頭..."
    
    @FocusState private var isFocused: Bool
    
    public init(text: Binding<String>, placeholder: String = "搜尋檔名、相機、鏡頭...") {
        self._text = text
        self.placeholder = placeholder
    }
    
    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isFocused ? LuminaTheme.Colors.cyanAccent : LuminaTheme.Colors.textTertiary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 11))
                .foregroundColor(LuminaTheme.Colors.textPrimary)
                .focused($isFocused)
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(LuminaTheme.Colors.textTertiary)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Text("⌘F")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(LuminaTheme.Colors.textMuted)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.06)))
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 9)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.black.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isFocused ? LuminaTheme.Colors.cyanAccent.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
