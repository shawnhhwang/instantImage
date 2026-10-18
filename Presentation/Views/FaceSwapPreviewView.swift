import SwiftUI
import AppKit

public struct FaceSwapPreviewView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var splitCurtainPosition: CGFloat = 0.5
    @State private var isSaveMenuOpen: Bool = false
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        guard let result = viewModel.currentFaceSwapResult else {
            return AnyView(EmptyView())
        }
        
        return AnyView(
            ZStack {
                // Background darkroom canvas
                LuminaTheme.Colors.darkroomCanvas
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Top Navigation & Comparison Toolbar
                    topToolbar(result: result)
                    
                    Divider().background(LuminaTheme.Colors.borderSubtle)
                    
                    // Main Stage Comparison Area
                    GeometryReader { geo in
                        if viewModel.faceSwapPreviewMode == .splitCurtain {
                            splitCurtainStage(result: result, size: geo.size)
                        } else {
                            sideBySideStage(result: result, size: geo.size)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    Divider().background(LuminaTheme.Colors.borderSubtle)
                    
                    // Bottom Decision Deck (Save / Discard)
                    bottomDecisionDeck(result: result)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        )
    }
    
    // MARK: - Top Toolbar
    private func topToolbar(result: FaceSwapResult) -> some View {
        HStack(spacing: 14) {
            // Close / Discard button
            LuminaIconButton(
                icon: "xmark",
                title: "關閉並放棄",
                shortcut: "ESC",
                size: 34,
                iconSize: 12
            ) {
                viewModel.discardFaceSwapResult()
            }
            
            // Title Pill & Source Face Info
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundColor(LuminaTheme.Colors.electricIndigo)
                
                Text("AI 換臉成果比對")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.textPrimary)
                
                if let sourceURL = result.sourceFaceURL {
                    HStack(spacing: 5) {
                        if let nsImg = NSImage(contentsOf: sourceURL) {
                            Image(nsImage: nsImg)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 18, height: 18)
                                .clipShape(Circle())
                        }
                        Text("來源: \(sourceURL.deletingPathExtension().lastPathComponent)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(LuminaTheme.Colors.textSecondary)
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(Capsule().fill(Color.black.opacity(0.04)))
                }
                
                LuminaBadge("100% HEIC", color: LuminaTheme.Colors.mintEmerald)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 12)
            .luminaGlass(cornerRadius: LuminaTheme.Radius.pill)
            
            Spacer()
            
            // Comparison Mode Switcher
            HStack(spacing: 4) {
                ForEach(FaceSwapPreviewMode.allCases) { mode in
                    LuminaPillButton(
                        label: mode.rawValue,
                        isSelected: viewModel.faceSwapPreviewMode == mode,
                        selectedColor: LuminaTheme.Colors.electricIndigo
                    ) {
                        viewModel.faceSwapPreviewMode = mode
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            Color.white.opacity(0.95)
                .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))
        )
    }
    
    // MARK: - Split Curtain Stage
    private func splitCurtainStage(result: FaceSwapResult, size: CGSize) -> some View {
        let posX = size.width * splitCurtainPosition
        
        return ZStack {
            // Right Side: Swapped Output Image (Full background)
            if let swappedImg = NSImage(contentsOf: result.previewOutputURL) {
                Image(nsImage: swappedImg)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)
            }
            
            // Left Side: Original Image cropped to split position
            if let origImg = NSImage(contentsOf: result.targetURL) {
                Image(nsImage: origImg)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)
                    .clipShape(
                        Rectangle().size(width: posX, height: size.height)
                    )
            }
            
            // Neon vertical divider line
            Rectangle()
                .fill(LuminaTheme.Colors.electricIndigo)
                .frame(width: 2.5, height: size.height)
                .luminaGlow(color: LuminaTheme.Colors.electricIndigo, radius: 6)
                .position(x: posX, y: size.height / 2)
            
            // Draggable Handle Pill
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundColor(LuminaTheme.Colors.electricIndigo)
                Text("原圖  |  換臉成果")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(LuminaTheme.Colors.textPrimary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundColor(LuminaTheme.Colors.electricIndigo)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.96))
                    .overlay(Capsule().stroke(LuminaTheme.Colors.electricIndigo, lineWidth: 1.5))
                    .shadow(color: LuminaTheme.Shadows.ambient, radius: 10, x: 0, y: 3)
            )
            .luminaGlow(color: LuminaTheme.Colors.electricIndigo, radius: 6)
            .position(x: posX, y: size.height / 2)
            .gesture(
                DragGesture()
                    .onChanged { val in
                        let newRatio = max(0.05, min(0.95, val.location.x / size.width))
                        splitCurtainPosition = newRatio
                    }
            )
            
            // Top Corner Badges (Original on top left, Swapped on top right)
            VStack {
                HStack {
                    Text("原圖 (BEFORE)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Capsule().fill(Color.black.opacity(0.65)))
                        .padding(.leading, 18)
                        .padding(.top, 14)
                    
                    Spacer()
                    
                    Text("換臉成果 (AFTER)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Capsule().fill(LuminaTheme.Colors.electricIndigo))
                        .padding(.trailing, 18)
                        .padding(.top, 14)
                }
                Spacer()
            }
        }
    }
    
    // MARK: - Side by Side Stage
    private func sideBySideStage(result: FaceSwapResult, size: CGSize) -> some View {
        let halfWidth = max(200, (size.width - 32) / 2)
        let contentHeight = max(200, size.height - 24)
        
        return HStack(spacing: 12) {
            // Left Card: Original
            VStack(spacing: 8) {
                LuminaBadge("原圖 (保持不變)", color: LuminaTheme.Colors.textSecondary)
                
                ZStack {
                    Color.white
                    
                    if let origImg = NSImage(contentsOf: result.targetURL) {
                        Image(nsImage: origImg)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(8)
                    }
                }
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.08), lineWidth: 1))
            }
            .frame(width: halfWidth, height: contentHeight)
            .padding(.vertical, 8)
            
            // Right Card: Swapped
            VStack(spacing: 8) {
                LuminaBadge("AI 換臉成果 (100% HEIC)", color: LuminaTheme.Colors.electricIndigo)
                
                ZStack {
                    Color.white
                    
                    if let swappedImg = NSImage(contentsOf: result.previewOutputURL) {
                        Image(nsImage: swappedImg)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(8)
                    }
                }
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(LuminaTheme.Colors.electricIndigo.opacity(0.4), lineWidth: 1.5))
                .shadow(color: LuminaTheme.Colors.electricIndigo.opacity(0.12), radius: 12, x: 0, y: 4)
            }
            .frame(width: halfWidth, height: contentHeight)
            .padding(.vertical, 8)
        }
        .padding(.horizontal, 10)
    }
    
    // MARK: - Bottom Decision Deck
    private func bottomDecisionDeck(result: FaceSwapResult) -> some View {
        HStack(spacing: 16) {
            // Discard Button
            Button(action: {
                viewModel.discardFaceSwapResult()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                    Text("放棄成果 (不儲存)")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(LuminaTheme.Colors.neonCoral)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LuminaTheme.Colors.neonCoral.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(LuminaTheme.Colors.neonCoral.opacity(0.2), lineWidth: 1))
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Re-run with another face button
            Button(action: {
                viewModel.isFaceSwapPreviewPresented = false
                viewModel.isFaceSwapSetupPresented = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                    Text("更換臉孔重試")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(LuminaTheme.Colors.textPrimary)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.12), lineWidth: 1))
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            // Primary Save Button & Options
            HStack(spacing: 8) {
                // Save As... (Picker)
                Menu {
                    Button("儲存於相片同資料夾 (_swap.heic)") {
                        viewModel.saveFaceSwapResult(destination: .sameFolder)
                    }
                    Button("儲存於 swap/output 目錄") {
                        viewModel.saveFaceSwapResult(destination: .swapOutput)
                    }
                    Divider()
                    Button("另存新檔 (選擇資料夾)...") {
                        viewModel.saveFaceSwapResult(destination: .saveAs)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("更多儲存選項")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.up")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(LuminaTheme.Colors.textSecondary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.1), lineWidth: 1))
                    )
                }
                .menuStyle(BorderlessButtonMenuStyle())
                
                // Direct Save to same folder (One-Click)
                Button(action: {
                    viewModel.saveFaceSwapResult(destination: .sameFolder)
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("確定儲存換臉影像")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 9)
                    .padding(.horizontal, 22)
                    .background(
                        Capsule()
                            .fill(LuminaTheme.Colors.electricIndigo)
                    )
                    .shadow(color: LuminaTheme.Colors.electricIndigo.opacity(0.35), radius: 8, x: 0, y: 3)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            Color.white
                .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))
        )
    }
}
