import SwiftUI
import MetalKit
import CoreImage

// MARK: - ImageDetailView (Awwwards-Caliber Darkroom Workspace)

public struct ImageDetailView: View {
    @ObservedObject var viewModel: AppViewModel
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            // Main Stage: Vertical Stack of Big Image Stage + Classic Mac Bottom Filmstrip
            VStack(spacing: 0) {
                // Main Big Image Canvas Area
                ZStack {
                    // Studio Stage Canvas Backdrop (Crisp Light Studio Neutral)
                    LuminaTheme.Colors.darkroomCanvas
                        .edgesIgnoringSafeArea(.all)
                        .onTapGesture {
                            NSApp.keyWindow?.makeFirstResponder(nil)
                        }
                    
                    // Key Capture invisible zero-frame helper (does not tint or overlay canvas)
                    KeyCaptureView()
                        .frame(width: 0, height: 0)
                        .opacity(0)
                        .allowsHitTesting(false)
                    
                    if let selectedImage = viewModel.selectedImage {
                        let key = selectedImage.url.path
                        let currentCorrection = viewModel.lightCorrections[key]
                        let isAutoEnabled = viewModel.isAutoLightEnabled[key] ?? false
                        let isBeforeAfter = viewModel.isBeforeAfterComparisonActive
                        let isClipping = viewModel.isClippingWarningActive
                        
                        GeometryReader { geo in
                            ZStack {
                                // Hardware-accelerated Metal Canvas
                                MetalImageView(
                                    imageURL: selectedImage.url,
                                    isZoomed: viewModel.isZoomed,
                                    lightCorrection: currentCorrection,
                                    isBeforeAfter: isBeforeAfter,
                                    isClippingWarning: isClipping,
                                    splitPosition: viewModel.splitCurtainPosition,
                                    viewModel: viewModel
                                )
                                .edgesIgnoringSafeArea(.all)
                                .id("\(key)_\(viewModel.isZoomed)_\(isAutoEnabled)_\(currentCorrection?.exposure ?? 0)_\(currentCorrection?.temperature ?? 0)_\(isBeforeAfter)_\(isClipping)_\(viewModel.splitCurtainPosition)")
                                .gesture(
                                    TapGesture(count: 2).onEnded {
                                        viewModel.toggleZoom()
                                    }
                                )
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location):
                                        viewModel.loupeLocation = location
                                        viewModel.isHoveringImage = true
                                    case .ended:
                                        viewModel.isHoveringImage = false
                                    }
                                }
                                
                                // Interactive Draggable Split Divider Line & Handle
                                if isBeforeAfter && currentCorrection != nil && !currentCorrection!.isNeutral {
                                    splitCurtainOverlay(in: geo.size)
                                }
                                
                                // Precision 2.5x Loupe Magnifier 2.0
                                if viewModel.isLoupeEnabled && viewModel.isHoveringImage {
                                    MagnifierOverlay(
                                        imageURL: selectedImage.url,
                                        mouseLocation: viewModel.loupeLocation,
                                        viewSize: geo.size
                                    )
                                }
                            }
                        }
                        
                        // Top Floating Dynamic Island
                        topFloatingIsland(for: selectedImage, key: key)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .padding(.top, 14)
                            .padding(.horizontal, 20)
                        
                        // Left / Right Navigation Touchpoints
                        navigationArrowButtons
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Bottom Section: Mac Classic Bottom Photo Strip (Placed BELOW the big image, zero overlap!)
                if viewModel.isFilmstripVisible {
                    Divider()
                        .background(LuminaTheme.Colors.borderSubtle)
                    
                    FilmstripView(viewModel: viewModel)
                        .frame(height: 76)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Right Darkroom Inspector Sliding Panel
            if viewModel.isSidebarOpenInDetail, let selectedImage = viewModel.selectedImage {
                let key = selectedImage.url.path
                DetailsSidebarView(viewModel: viewModel, selectedImage: selectedImage, key: key)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .background(LuminaTheme.Colors.darkroomCanvas)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            viewModel.calculateHistogramForSelected()
        }
        .onChange(of: viewModel.selectedImageIndex) { _, _ in
            viewModel.calculateHistogramForSelected()
        }
    }
    
    // MARK: - Top Floating Dynamic Island
    private func topFloatingIsland(for selectedImage: ImageItem, key: String) -> some View {
        HStack(spacing: 12) {
            // Close Button
            LuminaIconButton(
                icon: "xmark",
                title: "關閉詳細檢視",
                shortcut: "ESC",
                size: 34,
                iconSize: 12
            ) {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                    viewModel.isDetailActive = false
                }
            }
            
            // Filename & Index Pill
            HStack(spacing: 8) {
                Text(selectedImage.filename)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.textPrimary)
                    .lineLimit(1)
                
                if let curIdx = viewModel.selectedImageIndex {
                    Text("\(curIdx + 1) / \(viewModel.displayedImages.count)")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundColor(LuminaTheme.Colors.cyanAccent)
                        .padding(.vertical, 1.5)
                        .padding(.horizontal, 6)
                        .background(
                            Capsule().fill(LuminaTheme.Colors.cyanAccent.opacity(0.18))
                        )
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .luminaGlass(cornerRadius: LuminaTheme.Radius.pill)
            
            Spacer()
            
            // Darkroom Control Cluster
            HStack(spacing: 6) {
                let isAutoActive = viewModel.isAutoLightEnabled[key] ?? false
                
                // One-Click Auto Light Button
                LuminaPillButton(
                    icon: isAutoActive ? "wand.and.stars" : "wand.and.stars.inverse",
                    label: isAutoActive ? "已校光" : "一鍵校光",
                    isSelected: isAutoActive,
                    selectedColor: LuminaTheme.Colors.amberGold,
                    shortcut: "E"
                ) {
                    viewModel.toggleAutoLightForSelected()
                }
                
                // Auto White Balance Button
                LuminaPillButton(
                    icon: "thermometer.sun.fill",
                    label: "自動白平衡",
                    isSelected: false,
                    selectedColor: LuminaTheme.Colors.skyBlue,
                    shortcut: "W"
                ) {
                    viewModel.applyAutoWhiteBalanceForSelected()
                }
                
                // AI FaceSwap Button
                LuminaPillButton(
                    icon: "sparkles.rectangle.stack.fill",
                    label: "AI 換臉",
                    isSelected: viewModel.isFaceSwapSetupPresented || viewModel.isFaceSwapPreviewPresented,
                    selectedColor: LuminaTheme.Colors.electricIndigo,
                    shortcut: "S"
                ) {
                    viewModel.openFaceSwapSetup(for: selectedImage)
                }
                
                // Fast Convert to HEIC Button
                if selectedImage.url.pathExtension.lowercased() != "heic" && selectedImage.url.pathExtension.lowercased() != "heif" {
                    LuminaPillButton(
                        icon: "bolt.badge.automatic.fill",
                        label: "轉 HEIC",
                        isSelected: false,
                        selectedColor: LuminaTheme.Colors.cyanAccent,
                        shortcut: "H"
                    ) {
                        viewModel.convertSelectedImagesToHEIC()
                    }
                }
                
                // Before/After Split Curtain
                if isAutoActive {
                    LuminaPillButton(
                        icon: "square.split.2x1",
                        label: viewModel.isBeforeAfterComparisonActive ? "分割中" : "前後對比",
                        isSelected: viewModel.isBeforeAfterComparisonActive,
                        selectedColor: LuminaTheme.Colors.cyanAccent,
                        shortcut: "\\"
                    ) {
                        viewModel.isBeforeAfterComparisonActive.toggle()
                        viewModel.showToast(viewModel.isBeforeAfterComparisonActive ? "已開啟前後對比分割簾 (\\)" : "已關閉前後對比")
                    }
                }
                
                // Clipping Warning Alert Button
                LuminaIconButton(
                    icon: viewModel.isClippingWarningActive ? "triangle.fill" : "triangle",
                    title: "過曝/死黑剪裁警告",
                    shortcut: "J",
                    isActive: viewModel.isClippingWarningActive,
                    activeColor: LuminaTheme.Colors.neonCoral,
                    size: 34,
                    iconSize: 12
                ) {
                    viewModel.toggleClippingWarning()
                }
                
                // 2.5x Loupe Magnifier Button
                LuminaIconButton(
                    icon: "magnifyingglass.circle",
                    title: "2.5× 高解析放大鏡",
                    shortcut: "L",
                    isActive: viewModel.isLoupeEnabled,
                    activeColor: LuminaTheme.Colors.cyanAccent,
                    size: 34,
                    iconSize: 13
                ) {
                    viewModel.isLoupeEnabled.toggle()
                    viewModel.showToast(viewModel.isLoupeEnabled ? "已開啟放大鏡 (L)" : "已關閉放大鏡")
                }
                
                // 100% Zoom Toggle
                LuminaIconButton(
                    icon: viewModel.isZoomed ? "minus.magnifyingglass" : "plus.magnifyingglass",
                    title: "100% 像素對焦檢查",
                    shortcut: "Z",
                    isActive: viewModel.isZoomed,
                    activeColor: LuminaTheme.Colors.cyanAccent,
                    size: 34,
                    iconSize: 12
                ) {
                    viewModel.toggleZoom()
                }
                
                // Filmstrip Toggle
                LuminaIconButton(
                    icon: "film",
                    title: "底部縮圖膠卷",
                    shortcut: "B",
                    isActive: viewModel.isFilmstripVisible,
                    activeColor: LuminaTheme.Colors.cyanAccent,
                    size: 34,
                    iconSize: 12
                ) {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                        viewModel.isFilmstripVisible.toggle()
                    }
                }
                
                // Darkroom Inspector Sidebar Toggle
                LuminaIconButton(
                    icon: "sidebar.right",
                    title: "照片資訊與調光邊欄",
                    shortcut: "I",
                    isActive: viewModel.isSidebarOpenInDetail,
                    activeColor: LuminaTheme.Colors.cyanAccent,
                    size: 34,
                    iconSize: 12
                ) {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                        viewModel.isSidebarOpenInDetail.toggle()
                    }
                }
                
                // Fullscreen Toggle
                let isFullScreen = NSApp.keyWindow?.styleMask.contains(.fullScreen) == true
                LuminaIconButton(
                    icon: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    title: "macOS 原生全螢幕",
                    shortcut: "F",
                    isActive: isFullScreen,
                    activeColor: LuminaTheme.Colors.cyanAccent,
                    size: 34,
                    iconSize: 12
                ) {
                    viewModel.toggleFullScreen()
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .luminaGlass(cornerRadius: LuminaTheme.Radius.pill)
        }
    }
    
    // MARK: - Interactive Split Curtain Overlay
    private func splitCurtainOverlay(in size: CGSize) -> some View {
        let posX = size.width * viewModel.splitCurtainPosition
        
        return ZStack {
            // Neon Cyan vertical divider line
            Rectangle()
                .fill(LuminaTheme.Colors.cyanAccent)
                .frame(width: 2, height: size.height)
                .luminaGlow(color: LuminaTheme.Colors.cyanAccent, radius: 5)
                .position(x: posX, y: size.height / 2)
            
            // Tactile Draggable Handle Pill
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundColor(LuminaTheme.Colors.cyanAccent)
                Text("原圖  |  校光")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(LuminaTheme.Colors.textPrimary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundColor(LuminaTheme.Colors.cyanAccent)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.96))
                    .overlay(Capsule().stroke(LuminaTheme.Colors.cyanAccent, lineWidth: 1.5))
                    .shadow(color: LuminaTheme.Shadows.ambient, radius: 8, x: 0, y: 2)
            )
            .luminaGlow(color: LuminaTheme.Colors.cyanAccent, radius: 6)
            .position(x: posX, y: size.height / 2)
            .gesture(
                DragGesture()
                    .onChanged { val in
                        let newRatio = max(0.05, min(0.95, val.location.x / size.width))
                        viewModel.splitCurtainPosition = newRatio
                    }
            )
        }
    }
    
    // MARK: - Navigation Arrow Buttons
    private var navigationArrowButtons: some View {
        HStack {
            let isFirst = viewModel.selectedImageIndex == 0
            NavigationArrowButton(systemName: "chevron.left", action: {
                viewModel.selectPreviousImage()
            }, isDisabled: isFirst)
            
            Spacer()
            
            let isLast = viewModel.selectedImageIndex == viewModel.displayedImages.count - 1
            NavigationArrowButton(systemName: "chevron.right", action: {
                viewModel.selectNextImage()
            }, isDisabled: isLast)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - DetailsSidebarView (Awwwards Darkroom Inspector Panel)

public struct DetailsSidebarView: View {
    @ObservedObject var viewModel: AppViewModel
    let selectedImage: ImageItem
    let key: String
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
    
    private var fileSizeString: String {
        let sizeMB = Double(selectedImage.sizeBytes) / (1024.0 * 1024.0)
        return String(format: "%.2f MB", sizeMB)
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Inspector Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.2.square")
                        .foregroundColor(LuminaTheme.Colors.cyanAccent)
                    Text("暗房檢視器")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(LuminaTheme.Colors.textPrimary)
                }
                Spacer()
                Button(action: {
                    withAnimation { viewModel.isSidebarOpenInDetail = false }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(LuminaTheme.Colors.textTertiary)
                        .padding(4)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 2)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    // 1. Real-Time Luminance & RGB Histogram
                    HistogramView(bins: viewModel.activeHistogram)
                    
                    Divider().background(LuminaTheme.Colors.borderSubtle)
                    
                    // 2. Lightroom Tone & Color Adjustments
                    toneCorrectionSection
                    
                    Divider().background(LuminaTheme.Colors.borderSubtle)
                    
                    // 3. FaceFusion AI FaceSwap Section
                    faceSwapSidebarSection
                    
                    Divider().background(LuminaTheme.Colors.borderSubtle)
                    
                    // 4. Camera & Sensor Passport Card
                    cameraPassportSection
                    
                    Divider().background(LuminaTheme.Colors.borderSubtle)
                    
                    // 4. File Attributes
                    fileInfoSection
                    
                    Divider().background(LuminaTheme.Colors.borderSubtle)
                    
                    // 5. Culling Evaluation Rating & Tag Deck
                    cullingDeckSection
                }
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(
            LuminaTheme.Colors.bgSurface.opacity(0.95)
                .background(VisualEffectView(material: .sidebar, blendingMode: .withinWindow))
        )
        .overlay(
            VStack {
                HStack {
                    Rectangle().fill(LuminaTheme.Colors.borderSubtle).frame(width: 1)
                    Spacer()
                }
            }
        )
        .onAppear {
            viewModel.calculateHistogramForSelected()
        }
        .onChange(of: key) { _, _ in
            viewModel.calculateHistogramForSelected()
        }
    }
    
    // MARK: - FaceSwap Sidebar Section
    private var faceSwapSidebarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 11))
                        .foregroundColor(LuminaTheme.Colors.electricIndigo)
                    Text("AI 換臉工作台")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .tracking(0.6)
                        .foregroundColor(LuminaTheme.Colors.textTertiary)
                }
                Spacer()
                LuminaBadge("FaceFusion", color: LuminaTheme.Colors.electricIndigo)
            }
            
            // Current Source Face Preview
            HStack(spacing: 10) {
                if let source = viewModel.selectedSourceFace, let nsImg = NSImage(contentsOf: source.url) {
                    Image(nsImage: nsImg)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(LuminaTheme.Colors.electricIndigo.opacity(0.4), lineWidth: 1))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.name)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(LuminaTheme.Colors.textPrimary)
                            .lineLimit(1)
                        Text("融合: \(Int(viewModel.faceEnhancerBlend))%")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(LuminaTheme.Colors.textTertiary)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.04))
                        .frame(width: 36, height: 36)
                        .overlay(Image(systemName: "person.crop.circle").foregroundColor(.gray))
                    
                    Text("未選取來源人臉")
                        .font(.system(size: 10))
                        .foregroundColor(LuminaTheme.Colors.textTertiary)
                }
                
                Spacer()
                
                Button(action: {
                    viewModel.openFaceSwapSetup(for: selectedImage)
                }) {
                    Text("更換臉孔")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(LuminaTheme.Colors.cyanAccent)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 7)
                        .background(Capsule().fill(LuminaTheme.Colors.cyanAccent.opacity(0.12)))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.025))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.05), lineWidth: 1))
            )
            
            // Submit FaceSwap Button
            Button(action: {
                if viewModel.selectedSourceFace == nil {
                    viewModel.openFaceSwapSetup(for: selectedImage)
                } else {
                    viewModel.faceSwapTargetImage = selectedImage
                    viewModel.startFaceSwap()
                }
            }) {
                HStack(spacing: 6) {
                    if viewModel.isFaceSwapProcessing {
                        ProgressView().scaleEffect(0.6).colorInvert()
                        Text("API 運算中...")
                    } else {
                        Image(systemName: "sparkles")
                        Text("送出 API 換臉 (S)")
                    }
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(viewModel.isFaceSwapProcessing ? Color.gray : LuminaTheme.Colors.electricIndigo)
                )
                .shadow(color: LuminaTheme.Colors.electricIndigo.opacity(0.25), radius: 5, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(viewModel.isFaceSwapProcessing)
        }
    }
    
    // MARK: - Tone Correction Section
    private var toneCorrectionSection: some View {
        let isAutoActive = viewModel.isAutoLightEnabled[key] ?? false
        let currentParams = viewModel.lightCorrections[key] ?? .neutral
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("光線調校 (LIGHTROOM)")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(0.6)
                    .foregroundColor(LuminaTheme.Colors.textTertiary)
                
                Spacer()
                
                Button(action: {
                    viewModel.toggleAutoLightForSelected()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: isAutoActive ? "wand.and.stars" : "wand.and.stars.inverse")
                        Text(isAutoActive ? "校光中" : "一鍵自動 (E)")
                    }
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isAutoActive ? .black : LuminaTheme.Colors.amberGold)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 7)
                    .background(
                        Capsule().fill(isAutoActive ? LuminaTheme.Colors.amberGold : LuminaTheme.Colors.amberGold.opacity(0.14))
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Exposure Slider
            LuminaPrecisionSlider(
                label: "曝光度 (EV)",
                valueDisplay: String(format: "%+.2f EV", currentParams.exposure),
                value: Binding(
                    get: { currentParams.exposure },
                    set: { newVal in
                        var updated = currentParams
                        updated.exposure = newVal
                        viewModel.updateLightCorrection(for: selectedImage, params: updated)
                    }
                ),
                range: -2.0...2.0,
                defaultValue: 0.0
            )
            
            // Contrast Slider
            LuminaPrecisionSlider(
                label: "對比度",
                valueDisplay: String(format: "%.2f", currentParams.contrast),
                value: Binding(
                    get: { currentParams.contrast },
                    set: { newVal in
                        var updated = currentParams
                        updated.contrast = newVal
                        viewModel.updateLightCorrection(for: selectedImage, params: updated)
                    }
                ),
                range: 0.5...1.5,
                defaultValue: 1.0
            )
            
            // Highlights Slider
            LuminaPrecisionSlider(
                label: "亮部抑制",
                valueDisplay: String(format: "%+.2f", currentParams.highlights),
                value: Binding(
                    get: { currentParams.highlights },
                    set: { newVal in
                        var updated = currentParams
                        updated.highlights = newVal
                        viewModel.updateLightCorrection(for: selectedImage, params: updated)
                    }
                ),
                range: -1.0...1.0,
                defaultValue: 0.0
            )
            
            // Shadows Slider
            LuminaPrecisionSlider(
                label: "陰影提亮",
                valueDisplay: String(format: "%+.2f", currentParams.shadows),
                value: Binding(
                    get: { currentParams.shadows },
                    set: { newVal in
                        var updated = currentParams
                        updated.shadows = newVal
                        viewModel.updateLightCorrection(for: selectedImage, params: updated)
                    }
                ),
                range: -1.0...1.0,
                defaultValue: 0.0
            )
            
            // White Balance Controls
            HStack {
                Text("色彩與白平衡")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(0.6)
                    .foregroundColor(LuminaTheme.Colors.textTertiary)
                
                Spacer()
                
                Button(action: {
                    viewModel.applyAutoWhiteBalanceForSelected()
                }) {
                    Text("自動白平衡 (W)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(LuminaTheme.Colors.skyBlue)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .background(Capsule().fill(LuminaTheme.Colors.skyBlue.opacity(0.15)))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.top, 4)
            
            // Temperature Slider with Amber-to-Blue Gradient
            LuminaPrecisionSlider(
                label: "色溫 (K)",
                valueDisplay: "\(Int(currentParams.temperature)) K",
                value: Binding(
                    get: { currentParams.temperature },
                    set: { newVal in
                        var updated = currentParams
                        updated.temperature = newVal
                        viewModel.updateLightCorrection(for: selectedImage, params: updated)
                    }
                ),
                range: -2000.0...2000.0,
                defaultValue: 0.0,
                trackGradient: LuminaTheme.Gradients.tempGradient
            )
            
            // Tint Slider with Mint-to-Magenta Gradient
            LuminaPrecisionSlider(
                label: "色調",
                valueDisplay: "\(Int(currentParams.tint))",
                value: Binding(
                    get: { currentParams.tint },
                    set: { newVal in
                        var updated = currentParams
                        updated.tint = newVal
                        viewModel.updateLightCorrection(for: selectedImage, params: updated)
                    }
                ),
                range: -100.0...100.0,
                defaultValue: 0.0,
                trackGradient: LuminaTheme.Gradients.tintGradient
            )
            
            // Batch Sync & Reset Controls
            HStack(spacing: 8) {
                Button(action: {
                    viewModel.copyLightCorrectionForSelected()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("複製 (⌘C)")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.textPrimary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.04)).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.08), lineWidth: 0.75)))
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    viewModel.pasteLightCorrectionToSelected()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("貼上 (⌘V)")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(viewModel.copiedLightCorrection != nil ? LuminaTheme.Colors.cyanAccent : LuminaTheme.Colors.textMuted)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.04)).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.08), lineWidth: 0.75)))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(viewModel.copiedLightCorrection == nil)
                
                Spacer()
                
                if !currentParams.isNeutral {
                    Button(action: {
                        viewModel.resetLightCorrectionForSelected()
                    }) {
                        Text("重設")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(LuminaTheme.Colors.textTertiary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.top, 4)
        }
    }
    
    // MARK: - Camera Passport Section
    private var cameraPassportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("相機與鏡頭參數 (EXIF)")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(0.6)
                .foregroundColor(LuminaTheme.Colors.textTertiary)
            
            if let exif = viewModel.exifMetadata[key] {
                if let make = exif.cameraMake, let model = exif.cameraModel {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 12))
                            .foregroundColor(LuminaTheme.Colors.cyanAccent)
                        Text("\(make) \(model)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(LuminaTheme.Colors.textPrimary)
                    }
                    .padding(.bottom, 2)
                }
                
                // Sensor Chips Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    if let aperture = exif.aperture {
                        sensorChip(icon: "f.circle", label: "光圈", value: String(format: "f/%.1f", aperture))
                    }
                    if let ss = exif.shutterSpeed {
                        let ssText = ss >= 1.0 ? String(format: "%.1fs", ss) : String(format: "1/%.0fs", 1.0 / ss)
                        sensorChip(icon: "timer", label: "快門", value: ssText)
                    }
                    if let iso = exif.iso {
                        sensorChip(icon: "dial.low.fill", label: "感光度", value: "ISO \(iso)")
                    }
                    if let w = exif.width, let h = exif.height {
                        let mp = Double(w * h) / 1_000_000.0
                        sensorChip(icon: "viewfinder", label: "解析度", value: String(format: "%.1f MP", mp))
                    }
                }
            } else {
                Text("載入 EXIF 中...")
                    .font(.system(size: 10))
                    .foregroundColor(LuminaTheme.Colors.textTertiary)
            }
        }
    }
    
    private func sensorChip(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(LuminaTheme.Colors.cyanAccent)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(LuminaTheme.Colors.textTertiary)
                Text(value)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(LuminaTheme.Colors.textPrimary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.06), lineWidth: 0.75))
        )
    }
    
    // MARK: - File Info Section
    private var fileInfoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("檔案屬性")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(0.6)
                .foregroundColor(LuminaTheme.Colors.textTertiary)
            
            SidebarRow(label: "檔名", value: selectedImage.filename)
            SidebarRow(label: "大小", value: fileSizeString)
            SidebarRow(label: "路徑", value: selectedImage.url.path, isTruncated: true)
        }
    }
    
    // MARK: - Culling Deck Section
    private var cullingDeckSection: some View {
        let metadata = viewModel.exifMetadata[key] ?? ImageMetadata(id: key, url: selectedImage.url, filename: selectedImage.filename)
        
        return VStack(alignment: .leading, spacing: 10) {
            Text("挑片評估 (ACDSEE CULLING)")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(0.6)
                .foregroundColor(LuminaTheme.Colors.textTertiary)
            
            // Rating Row
            HStack {
                Text("星級評等 (1-5)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(LuminaTheme.Colors.textSecondary)
                Spacer()
                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= metadata.rating ? "star.fill" : "star")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(star <= metadata.rating ? LuminaTheme.Colors.amberGold : Color.black.opacity(0.18))
                            .luminaGlow(color: LuminaTheme.Colors.amberGold, radius: 4, isActive: star <= metadata.rating)
                            .onTapGesture {
                                viewModel.updateRatingForSelected(to: metadata.rating == star ? 0 : star)
                            }
                    }
                }
            }
            
            // Tagging Row
            HStack {
                Text("保留標記 (T)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(LuminaTheme.Colors.textSecondary)
                Spacer()
                Button(action: {
                    viewModel.toggleTaggedForSelected()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: metadata.isTagged ? "flag.fill" : "flag")
                        Text(metadata.isTagged ? "已標記" : "未標記")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(metadata.isTagged ? .white : LuminaTheme.Colors.textSecondary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(
                        Capsule().fill(metadata.isTagged ? LuminaTheme.Colors.neonCoral : Color.black.opacity(0.05))
                    )
                    .luminaGlow(color: LuminaTheme.Colors.neonCoral, radius: 6, isActive: metadata.isTagged)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

// MARK: - Reusable Sidebar Row
struct SidebarRow: View {
    let label: String
    let value: String
    var isTruncated: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(LuminaTheme.Colors.textTertiary)
                .frame(width: 45, alignment: .leading)
            
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(LuminaTheme.Colors.textSecondary)
                .lineLimit(isTruncated ? 1 : nil)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

// MARK: - Real-time Luminance Histogram View
struct HistogramView: View {
    let bins: [Float]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("即時曝光直方圖")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(0.6)
                    .foregroundColor(LuminaTheme.Colors.textTertiary)
                Spacer()
                Text("256 BINS")
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundColor(LuminaTheme.Colors.cyanAccent)
            }
            
            ZStack {
                // Background Box
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 0.94, green: 0.95, blue: 0.97))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 0.75)
                    )
                    .frame(height: 75)
                
                // Grid ticks
                HStack {
                    Spacer()
                    Rectangle().fill(Color.black.opacity(0.05)).frame(width: 1)
                    Spacer()
                    Rectangle().fill(Color.black.opacity(0.05)).frame(width: 1)
                    Spacer()
                    Rectangle().fill(Color.black.opacity(0.05)).frame(width: 1)
                    Spacer()
                }
                .frame(height: 75)
                
                if bins.isEmpty {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    GeometryReader { geo in
                        let width = geo.size.width
                        let height = geo.size.height
                        let step = width / CGFloat(max(1, bins.count - 1))
                        
                        let points: [CGPoint] = bins.indices.map { i in
                            CGPoint(x: CGFloat(i) * step, y: height - (CGFloat(bins[i]) * height * 0.90))
                        }
                        
                        // Area Fill Gradient
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: height))
                            for pt in points {
                                path.addLine(to: pt)
                            }
                            path.addLine(to: CGPoint(x: width, y: height))
                            path.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                colors: [LuminaTheme.Colors.cyanAccent.opacity(0.28), LuminaTheme.Colors.cyanAccent.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        
                        // Outline Stroke
                        Path { path in
                            if let first = points.first {
                                path.move(to: first)
                                for pt in points.dropFirst() {
                                    path.addLine(to: pt)
                                }
                            }
                        }
                        .stroke(LuminaTheme.Colors.cyanAccent, lineWidth: 1.2)
                    }
                    .frame(height: 75)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

// MARK: - Navigation Arrow Button
struct NavigationArrowButton: View {
    let systemName: String
    let action: () -> Void
    let isDisabled: Bool
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(isDisabled ? Color.black.opacity(0.12) : (isHovered ? LuminaTheme.Colors.cyanAccent : LuminaTheme.Colors.textPrimary))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(isDisabled ? Color.clear : (isHovered ? Color.white : Color.white.opacity(0.92)))
                        .overlay(
                            Circle().stroke(isHovered ? LuminaTheme.Colors.cyanAccent.opacity(0.6) : Color.black.opacity(0.08), lineWidth: 1)
                        )
                )
                .shadow(color: LuminaTheme.Shadows.ambient, radius: isHovered ? 8 : 4, x: 0, y: 2)
                .scaleEffect(isHovered ? 1.06 : 1.0)
                .luminaGlow(color: LuminaTheme.Colors.cyanAccent, radius: 6, isActive: isHovered && !isDisabled)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
    }
}

// MARK: - KeyableMTKView for Metal Acceleration

final class KeyableMTKView: MTKView {
    weak var viewModel: AppViewModel?
    private var scrollAccumulatorX: CGFloat = 0.0
    
    override var acceptsFirstResponder: Bool { true }
    
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
    
    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began || event.phase == .mayBegin {
            scrollAccumulatorX = 0
        }
        
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            scrollAccumulatorX += event.scrollingDeltaX
            let threshold: CGFloat = 80.0
            
            if scrollAccumulatorX > threshold {
                Task { @MainActor [weak viewModel] in
                    viewModel?.selectPreviousImage()
                }
                scrollAccumulatorX = 0
            } else if scrollAccumulatorX < -threshold {
                Task { @MainActor [weak viewModel] in
                    viewModel?.selectNextImage()
                }
                scrollAccumulatorX = 0
            }
        }
        
        if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
            scrollAccumulatorX = 0
        }
        
        super.scrollWheel(with: event)
    }
}

// MARK: - MetalImageView Component

public struct MetalImageView: NSViewRepresentable {
    let imageURL: URL
    let isZoomed: Bool
    var lightCorrection: LightCorrectionParams? = nil
    var isBeforeAfter: Bool = false
    var isClippingWarning: Bool = false
    var splitPosition: CGFloat = 0.5
    @ObservedObject var viewModel: AppViewModel
    
    public func makeNSView(context: Context) -> MTKView {
        let mtkView = KeyableMTKView()
        mtkView.viewModel = viewModel
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0.92, green: 0.93, blue: 0.95, alpha: 1.0)
        mtkView.framebufferOnly = false
        mtkView.enableSetNeedsDisplay = true
        mtkView.delegate = context.coordinator
        
        context.coordinator.mtkView = mtkView
        context.coordinator.lightCorrection = lightCorrection
        context.coordinator.isBeforeAfter = isBeforeAfter
        context.coordinator.isClippingWarning = isClippingWarning
        context.coordinator.splitPosition = splitPosition
        context.coordinator.loadImage(from: imageURL, isZoomed: isZoomed)
        
        return mtkView
    }
    
    public func updateNSView(_ nsView: MTKView, context: Context) {
        if let keyableView = nsView as? KeyableMTKView {
            keyableView.viewModel = viewModel
        }
        context.coordinator.mtkView = nsView
        let correctionChanged = context.coordinator.lightCorrection != lightCorrection
        let beforeAfterChanged = context.coordinator.isBeforeAfter != isBeforeAfter
        let clippingChanged = context.coordinator.isClippingWarning != isClippingWarning
        let splitChanged = abs(context.coordinator.splitPosition - splitPosition) > 0.001
        
        context.coordinator.lightCorrection = lightCorrection
        context.coordinator.isBeforeAfter = isBeforeAfter
        context.coordinator.isClippingWarning = isClippingWarning
        context.coordinator.splitPosition = splitPosition
        
        if correctionChanged || beforeAfterChanged || clippingChanged || splitChanged {
            nsView.setNeedsDisplay(nsView.bounds)
        }
        
        context.coordinator.loadImage(from: imageURL, isZoomed: isZoomed)
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    public class Coordinator: NSObject, MTKViewDelegate {
        private let context: CIContext
        private let commandQueue: MTLCommandQueue?
        private var ciImage: CIImage?
        private var loadedURL: URL?
        private var loadTask: Task<Void, Never>?
        weak var mtkView: MTKView?
        
        var isZoomed: Bool = false
        var lightCorrection: LightCorrectionParams?
        var isBeforeAfter: Bool = false
        var isClippingWarning: Bool = false
        var splitPosition: CGFloat = 0.5
        
        override init() {
            let device = MTLCreateSystemDefaultDevice()!
            let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
            self.context = CIContext(mtlDevice: device, options: [
                .workingColorSpace: sRGB,
                .outputColorSpace: sRGB
            ])
            self.commandQueue = device.makeCommandQueue()
            super.init()
        }
        
        func loadImage(from url: URL, isZoomed: Bool) {
            if loadedURL == url && self.isZoomed == isZoomed && ciImage != nil {
                return
            }
            
            let isNewURL = loadedURL != url
            loadedURL = url
            self.isZoomed = isZoomed
            
            loadTask?.cancel()
            
            if isNewURL {
                self.ciImage = nil
                self.mtkView?.setNeedsDisplay(self.mtkView?.bounds ?? .zero)
            }
            
            loadTask = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                
                let image = SecurityScopedBookmarkManager.shared.performAccessingSecurityScopedResource(at: url) { () -> CIImage? in
                    let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
                    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else { return nil }
                    
                    if !isZoomed {
                        let maxPixelSize = 2560
                        let thumbnailOptions: [CFString: Any] = [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceShouldCacheImmediately: true
                        ]
                        if let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbnailOptions as CFDictionary) {
                            return CIImage(cgImage: cgImage)
                        }
                    }
                    
                    return CIImage(contentsOf: url)
                }
                
                if Task.isCancelled { return }
                
                Task { @MainActor in
                    self.ciImage = image
                    self.mtkView?.setNeedsDisplay(self.mtkView?.bounds ?? .zero)
                }
            }
        }
        
        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            view.setNeedsDisplay(view.bounds)
        }
        
        public func draw(in view: MTKView) {
            guard let ciImage = ciImage,
                  let currentDrawable = view.currentDrawable,
                  let commandQueue = commandQueue,
                  let commandBuffer = commandQueue.makeCommandBuffer() else {
                return
            }
            
            let drawableSize = view.drawableSize
            let imageSize = ciImage.extent.size
            
            let scaleX = drawableSize.width / imageSize.width
            let scaleY = drawableSize.height / imageSize.height
            let scale = isZoomed ? max(scaleX, scaleY) : min(scaleX, scaleY)
            
            let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            
            let offsetX = (drawableSize.width - scaledImage.extent.width) / 2
            let offsetY = (drawableSize.height - scaledImage.extent.height) / 2
            let centeredOriginal = scaledImage.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
            
            var processedImage = centeredOriginal
            if let params = lightCorrection, !params.isNeutral {
                if abs(params.exposure) > 0.001 {
                    processedImage = processedImage.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: params.exposure])
                }
                if abs(params.temperature) > 1.0 || abs(params.tint) > 1.0 {
                    let neutralVector = CIVector(x: 6500, y: 0)
                    let targetVector = CIVector(x: CGFloat(6500 + params.temperature), y: CGFloat(params.tint))
                    processedImage = processedImage.applyingFilter("CITemperatureAndTint", parameters: [
                        "inputNeutral": neutralVector,
                        "inputTargetNeutral": targetVector
                    ])
                }
                if abs(params.contrast - 1.0) > 0.001 {
                    processedImage = processedImage.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: params.contrast])
                }
                if abs(params.highlights) > 0.001 || abs(params.shadows) > 0.001 {
                    let hlAmount = max(0.0, 1.0 + Double(params.highlights))
                    let shAmount = max(0.0, Double(params.shadows))
                    processedImage = processedImage.applyingFilter("CIHighlightShadowAdjust", parameters: [
                        "inputHighlightAmount": hlAmount,
                        "inputShadowAmount": shAmount
                    ])
                }
            }
            
            if isClippingWarning {
                let redOverlay = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 0.9)).cropped(to: processedImage.extent)
                let blueOverlay = CIImage(color: CIColor(red: 0, green: 0.35, blue: 1, alpha: 0.9)).cropped(to: processedImage.extent)
                
                let hiMask = processedImage
                    .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.98])
                    .applyingFilter("CIColorClamp", parameters: [
                        "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                        "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
                    ])
                    .applyingFilter("CIColorMatrix", parameters: [
                        "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                        "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                        "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                        "inputAVector": CIVector(x: 50, y: 50, z: 50, w: 0)
                    ])
                
                let shInvert = processedImage.applyingFilter("CIColorInvert")
                let shMask = shInvert
                    .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.98])
                    .applyingFilter("CIColorClamp", parameters: [
                        "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                        "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
                    ])
                    .applyingFilter("CIColorMatrix", parameters: [
                        "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                        "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                        "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                        "inputAVector": CIVector(x: 50, y: 50, z: 50, w: 0)
                    ])
                
                let withRed = redOverlay.applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: processedImage,
                    kCIInputMaskImageKey: hiMask
                ])
                processedImage = blueOverlay.applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: withRed,
                    kCIInputMaskImageKey: shMask
                ])
            }
            
            let finalImageToRender: CIImage
            if isBeforeAfter, let params = lightCorrection, !params.isNeutral {
                let splitX = drawableSize.width * max(0.05, min(0.95, splitPosition))
                let leftCropRect = CGRect(x: 0, y: 0, width: splitX, height: drawableSize.height)
                let rightCropRect = CGRect(x: splitX, y: 0, width: drawableSize.width - splitX, height: drawableSize.height)
                
                let originalHalf = centeredOriginal.cropped(to: leftCropRect)
                let processedHalf = processedImage.cropped(to: rightCropRect)
                finalImageToRender = originalHalf.composited(over: processedHalf)
            } else {
                finalImageToRender = processedImage
            }
            
            let destination = CIRenderDestination(
                width: Int(drawableSize.width),
                height: Int(drawableSize.height),
                pixelFormat: view.colorPixelFormat,
                commandBuffer: commandBuffer,
                mtlTextureProvider: { currentDrawable.texture }
            )
            destination.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
            
            do {
                _ = try context.startTask(toRender: finalImageToRender, to: destination)
                commandBuffer.present(currentDrawable)
                commandBuffer.commit()
            } catch {
                LoggerManager.shared.log("Metal rendering failed: \(error.localizedDescription)", level: .error)
            }
        }
    }
}

// MARK: - MagnifierOverlay 2.0 (Precision Optical Loupe)

struct MagnifierOverlay: View {
    let imageURL: URL
    let mouseLocation: CGPoint
    let viewSize: CGSize
    
    @State private var nsImage: NSImage? = nil
    
    var body: some View {
        if let nsImage = nsImage {
            let zoomFactor: CGFloat = 2.5
            let loupeSize: CGFloat = 190
            
            let offsetX = (viewSize.width / 2.0 - mouseLocation.x) * zoomFactor
            let offsetY = (viewSize.height / 2.0 - mouseLocation.y) * zoomFactor
            
            ZStack {
                // 1. Cropped & Scaled Content
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: viewSize.width, height: viewSize.height)
                    .scaleEffect(zoomFactor)
                    .offset(x: offsetX, y: offsetY)
                    .frame(width: loupeSize, height: loupeSize)
                    .clipShape(Circle())
                
                // 2. Camera Reticle Crosshairs
                Path { path in
                    let c = loupeSize / 2
                    path.move(to: CGPoint(x: c - 15, y: c))
                    path.addLine(to: CGPoint(x: c - 4, y: c))
                    path.move(to: CGPoint(x: c + 4, y: c))
                    path.addLine(to: CGPoint(x: c + 15, y: c))
                    
                    path.move(to: CGPoint(x: c, y: c - 15))
                    path.addLine(to: CGPoint(x: c, y: c - 4))
                    path.move(to: CGPoint(x: c, y: c + 4))
                    path.addLine(to: CGPoint(x: c, y: c + 15))
                }
                .stroke(LuminaTheme.Colors.cyanAccent, lineWidth: 1.5)
                
                // 3. Precision Bezel Ring with metallic highlight
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [LuminaTheme.Colors.cyanAccent, Color.white.opacity(0.8), LuminaTheme.Colors.electricIndigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2.5
                    )
                    .frame(width: loupeSize, height: loupeSize)
                    .luminaGlow(color: LuminaTheme.Colors.cyanAccent, radius: 8)
                
                // 4. Zoom Badge tag at bottom
                VStack {
                    Spacer()
                    Text("2.5× ULTRA RES")
                        .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                        .foregroundColor(LuminaTheme.Colors.cyanAccent)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .background(
                            Capsule().fill(Color.white.opacity(0.95))
                                .overlay(Capsule().stroke(LuminaTheme.Colors.cyanAccent.opacity(0.5), lineWidth: 1))
                                .shadow(color: LuminaTheme.Shadows.ambient, radius: 4, x: 0, y: 1)
                        )
                        .offset(y: 12)
                }
                .frame(width: loupeSize, height: loupeSize)
            }
            .position(x: mouseLocation.x, y: mouseLocation.y)
            .onAppear { loadImage() }
            .onChange(of: imageURL) { _, _ in loadImage() }
        }
    }
    
    private func loadImage() {
        Task.detached(priority: .userInitiated) {
            let img = SecurityScopedBookmarkManager.shared.performAccessingSecurityScopedResource(at: imageURL) { () -> NSImage? in
                if let data = try? Data(contentsOf: imageURL) {
                    return NSImage(data: data)
                }
                return nil
            }
            await MainActor.run { self.nsImage = img }
        }
    }
}
