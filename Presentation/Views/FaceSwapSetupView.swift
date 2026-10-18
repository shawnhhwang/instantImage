import SwiftUI
import AppKit

public struct FaceSwapSetupView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var serverUrl: String = ""
    @State private var isCustomSourcePickerPresented: Bool = false
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        ZStack {
            // Backdrop dimming
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    if !viewModel.isFaceSwapProcessing {
                        viewModel.isFaceSwapSetupPresented = false
                    }
                }
            
            // Modal Sheet Card
            VStack(spacing: 0) {
                headerView
                
                Divider().background(LuminaTheme.Colors.borderSubtle)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Target Image Preview Card
                        targetImageCard
                        
                        // Source Face Selector Section
                        sourceFaceSection
                        
                        // Parameters & Options Section
                        parametersSection
                        
                        // Live Process Status (if running or failed)
                        if viewModel.isFaceSwapProcessing || viewModel.faceSwapErrorMessage != nil {
                            statusSection
                        }
                    }
                    .padding(24)
                }
                .frame(maxHeight: 520)
                
                Divider().background(LuminaTheme.Colors.borderSubtle)
                
                footerView
            }
            .frame(width: 640)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.black.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 25, x: 0, y: 12)
            )
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
        .onAppear {
            viewModel.loadSourceFaces()
            self.serverUrl = FaceSwapService.shared.readApiServerUrl() ?? "http://192.168.1.3:7870/api/predict"
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LuminaTheme.Colors.electricIndigo.opacity(0.12))
                    .frame(width: 36, height: 36)
                
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 16))
                    .foregroundColor(LuminaTheme.Colors.electricIndigo)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("FaceFusion AI 人臉替換")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.textPrimary)
                
                Text("將選定的來源臉孔融合至目標相片，高精度無損輸出")
                    .font(.system(size: 11))
                    .foregroundColor(LuminaTheme.Colors.textTertiary)
            }
            
            Spacer()
            
            Button(action: {
                if !viewModel.isFaceSwapProcessing {
                    viewModel.isFaceSwapSetupPresented = false
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.black.opacity(0.05)))
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(viewModel.isFaceSwapProcessing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.015))
    }
    
    // MARK: - Target Image Card
    private var targetImageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("目標相片 (TARGET)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(LuminaTheme.Colors.textSecondary)
            
            if let target = viewModel.faceSwapTargetImage {
                let key = target.url.path
                HStack(spacing: 14) {
                    if let cgImage = viewModel.thumbnails[key] {
                        Image(nsImage: NSImage(cgImage: cgImage, size: .zero))
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.1), lineWidth: 1))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.1))
                            .frame(width: 64, height: 64)
                            .overlay(Image(systemName: "photo").foregroundColor(.gray))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(target.filename)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(LuminaTheme.Colors.textPrimary)
                            .lineLimit(1)
                        
                        Text(target.url.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(LuminaTheme.Colors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        HStack(spacing: 6) {
                            LuminaBadge("目標待換臉", color: LuminaTheme.Colors.cyanAccent)
                            let sizeMB = Double(target.sizeBytes) / (1024 * 1024)
                            LuminaBadge(String(format: "%.1f MB", sizeMB))
                        }
                    }
                    
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.97, green: 0.975, blue: 0.985))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.06), lineWidth: 1))
                )
            }
        }
    }
    
    // MARK: - Source Face Section
    private var sourceFaceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("選擇來源人臉 (SOURCE FACE)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.textSecondary)
                
                Spacer()
                
                // Pick custom image from disk
                Button(action: selectCustomSourceFace) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("自訂來源圖檔...")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(LuminaTheme.Colors.cyanAccent)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(viewModel.isFaceSwapProcessing)
            }
            
            if viewModel.availableSourceFaces.isEmpty {
                Text("在 swap/source 目錄中未找到任何相片，請將人臉相片放置於 swap/source 或點選自訂選取。")
                    .font(.system(size: 11))
                    .foregroundColor(LuminaTheme.Colors.textTertiary)
                    .padding(14)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(viewModel.availableSourceFaces) { face in
                            let isSelected = viewModel.selectedSourceFace?.id == face.id
                            
                            Button(action: {
                                viewModel.selectedSourceFace = face
                            }) {
                                VStack(spacing: 6) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color.gray.opacity(0.08))
                                            .frame(width: 76, height: 76)
                                        
                                        if let nsImg = NSImage(contentsOf: face.url) {
                                            Image(nsImage: nsImg)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 76, height: 76)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        } else {
                                            Image(systemName: "person.crop.circle")
                                                .font(.system(size: 28))
                                                .foregroundColor(.gray)
                                        }
                                        
                                        if isSelected {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(LuminaTheme.Colors.electricIndigo, lineWidth: 2.5)
                                                .shadow(color: LuminaTheme.Colors.electricIndigo.opacity(0.4), radius: 6)
                                            
                                            VStack {
                                                HStack {
                                                    Spacer()
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .font(.system(size: 14))
                                                        .foregroundColor(LuminaTheme.Colors.electricIndigo)
                                                        .background(Circle().fill(Color.white))
                                                        .padding(4)
                                                }
                                                Spacer()
                                            }
                                        }
                                    }
                                    
                                    Text(face.name)
                                        .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                        .foregroundColor(isSelected ? LuminaTheme.Colors.electricIndigo : LuminaTheme.Colors.textPrimary)
                                        .lineLimit(1)
                                        .frame(width: 76)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(viewModel.isFaceSwapProcessing)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
            }
        }
    }
    
    // MARK: - Parameters Section
    private var parametersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("融合與增強參數")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(LuminaTheme.Colors.textSecondary)
            
            VStack(spacing: 12) {
                // Blend Slider
                LuminaPrecisionSlider(
                    label: "人臉增強融合比例 (Face Enhancer Blend)",
                    valueDisplay: String(format: "%.0f%%", viewModel.faceEnhancerBlend),
                    value: Binding(
                        get: { Float(viewModel.faceEnhancerBlend) },
                        set: { viewModel.faceEnhancerBlend = Double($0) }
                    ),
                    range: 0...100,
                    defaultValue: 60.0
                )
                
                // Server Info Chip
                HStack(spacing: 8) {
                    Image(systemName: "network")
                        .font(.system(size: 11))
                        .foregroundColor(LuminaTheme.Colors.textSecondary)
                    
                    Text("API 端點: \(serverUrl)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(LuminaTheme.Colors.textSecondary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    LuminaBadge("Gradio/FaceFusion", color: LuminaTheme.Colors.mintEmerald)
                }
                .padding(.top, 4)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.98, green: 0.985, blue: 0.995))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.06), lineWidth: 1))
            )
        }
    }
    
    // MARK: - Status Section
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.isFaceSwapProcessing {
                HStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.85)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI 換臉連線運算中...")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(LuminaTheme.Colors.electricIndigo)
                        
                        Text(viewModel.faceSwapStatusMessage.isEmpty ? "正在與遠端 FaceFusion API 進行圖片交換..." : viewModel.faceSwapStatusMessage)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(LuminaTheme.Colors.textSecondary)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    Button("取消") {
                        viewModel.cancelFaceSwap()
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.neonCoral)
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LuminaTheme.Colors.electricIndigo.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(LuminaTheme.Colors.electricIndigo.opacity(0.2), lineWidth: 1))
                )
            } else if let error = viewModel.faceSwapErrorMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(LuminaTheme.Colors.neonCoral)
                        .font(.system(size: 14))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("執行失敗")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(LuminaTheme.Colors.neonCoral)
                        Text(error)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(LuminaTheme.Colors.textPrimary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LuminaTheme.Colors.neonCoral.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(LuminaTheme.Colors.neonCoral.opacity(0.2), lineWidth: 1))
                )
            }
        }
    }
    
    // MARK: - Footer
    private var footerView: some View {
        HStack {
            Button("取消") {
                if !viewModel.isFaceSwapProcessing {
                    viewModel.isFaceSwapSetupPresented = false
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(LuminaTheme.Colors.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .buttonStyle(PlainButtonStyle())
            .disabled(viewModel.isFaceSwapProcessing)
            
            Spacer()
            
            // Primary Submit Button
            Button(action: {
                viewModel.startFaceSwap()
            }) {
                HStack(spacing: 8) {
                    if viewModel.isFaceSwapProcessing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .colorInvert()
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .bold))
                    }
                    
                    Text(viewModel.isFaceSwapProcessing ? "處理中..." : "送出 API 進行換臉")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 20)
                .background(
                    Capsule()
                        .fill(viewModel.selectedSourceFace == nil || viewModel.isFaceSwapProcessing ? Color.gray : LuminaTheme.Colors.electricIndigo)
                )
                .shadow(color: LuminaTheme.Colors.electricIndigo.opacity(0.3), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(viewModel.selectedSourceFace == nil || viewModel.isFaceSwapProcessing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.02))
    }
    
    private func selectCustomSourceFace() {
        let openPanel = NSOpenPanel()
        openPanel.title = "選取自訂來源人臉圖片"
        openPanel.allowedContentTypes = [.jpeg, .png, .heic, .webP]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = false
        
        if openPanel.runModal() == .OK, let url = openPanel.url {
            let customItem = SourceFaceItem(url: url)
            if !viewModel.availableSourceFaces.contains(where: { $0.id == customItem.id }) {
                viewModel.availableSourceFaces.insert(customItem, at: 0)
            }
            viewModel.selectedSourceFace = customItem
        }
    }
}
