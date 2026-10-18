import SwiftUI
import AppKit

public struct FaceSwapSetupView: View {
    @ObservedObject var viewModel: AppViewModel
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
                        // Target Mode Switcher (Single / Folder / Multi-Select)
                        targetModeSection
                        
                        // Target Preview Card
                        targetDetailsCard
                        
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
                .frame(maxHeight: 540)
                
                Divider().background(LuminaTheme.Colors.borderSubtle)
                
                footerView
            }
            .frame(width: 660)
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
            viewModel.loadFaceSwapSettings()
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
                
                Text("將選定的來源臉孔融合至目標相片，支援單張與資料夾批次無損輸出")
                    .font(.system(size: 11))
                    .foregroundColor(LuminaTheme.Colors.textTertiary)
            }
            
            Spacer()
            
            // API Settings Quick Button
            Button(action: {
                viewModel.isFaceSwapSettingsPresented = true
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .bold))
                    Text("API 端點設定")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(LuminaTheme.Colors.textSecondary)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.08), lineWidth: 1))
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Close Button
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
    
    // MARK: - Target Mode Selector
    private var targetModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("目標處理模式 (TARGET MODE)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(LuminaTheme.Colors.textSecondary)
            
            HStack(spacing: 8) {
                ForEach(FaceSwapBatchTargetMode.allCases) { mode in
                    Button(action: {
                        viewModel.faceSwapBatchTargetMode = mode
                        if mode == .folder && viewModel.faceSwapBatchTargets.isEmpty {
                            if let current = viewModel.selectedFolder {
                                viewModel.faceSwapBatchFolderURL = current
                                let validExts: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "heif"]
                                viewModel.faceSwapBatchTargets = viewModel.images.map { $0.url }.filter { validExts.contains($0.pathExtension.lowercased()) }
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            switch mode {
                            case .single:
                                Image(systemName: "photo")
                            case .folder:
                                Image(systemName: "folder.fill")
                            case .selected:
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text(mode.rawValue)
                        }
                        .font(.system(size: 12, weight: viewModel.faceSwapBatchTargetMode == mode ? .bold : .medium))
                        .foregroundColor(viewModel.faceSwapBatchTargetMode == mode ? LuminaTheme.Colors.electricIndigo : LuminaTheme.Colors.textSecondary)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(viewModel.faceSwapBatchTargetMode == mode ? LuminaTheme.Colors.electricIndigo.opacity(0.1) : Color.black.opacity(0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(viewModel.faceSwapBatchTargetMode == mode ? LuminaTheme.Colors.electricIndigo.opacity(0.3) : Color.black.opacity(0.06), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(viewModel.isFaceSwapProcessing)
                }
            }
        }
    }
    
    // MARK: - Target Details Card
    private var targetDetailsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch viewModel.faceSwapBatchTargetMode {
            case .single:
                if let target = viewModel.faceSwapTargetImage {
                    let key = target.url.path
                    HStack(spacing: 14) {
                        if let cgImage = viewModel.thumbnails[key] {
                            Image(nsImage: NSImage(cgImage: cgImage, size: .zero))
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.1), lineWidth: 1))
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.1))
                                .frame(width: 60, height: 60)
                                .overlay(Image(systemName: "photo").foregroundColor(.gray))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(target.filename)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(LuminaTheme.Colors.textPrimary)
                            
                            Text(target.url.path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(LuminaTheme.Colors.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            HStack(spacing: 8) {
                                LuminaBadge(target.url.pathExtension.uppercased(), color: LuminaTheme.Colors.electricIndigo)
                                Text("單張相片處理")
                                    .font(.system(size: 10))
                                    .foregroundColor(LuminaTheme.Colors.textTertiary)
                            }
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.02))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.06), lineWidth: 1))
                    )
                }
                
            case .folder:
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(LuminaTheme.Colors.amberGold)
                                Text(viewModel.faceSwapBatchFolderURL?.lastPathComponent ?? "未選擇資料夾")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(LuminaTheme.Colors.textPrimary)
                                
                                LuminaBadge("共 \(viewModel.faceSwapBatchTargets.count) 張相片", color: LuminaTheme.Colors.mintEmerald)
                            }
                            
                            if let folder = viewModel.faceSwapBatchFolderURL {
                                Text(folder.path)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundColor(LuminaTheme.Colors.textTertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            viewModel.chooseCustomBatchFolder()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "folder.badge.gearshape")
                                Text("選擇其他資料夾...")
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(LuminaTheme.Colors.electricIndigo)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(LuminaTheme.Colors.electricIndigo.opacity(0.1))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(viewModel.isFaceSwapProcessing)
                    }
                    
                    if !viewModel.faceSwapBatchTargets.isEmpty {
                        Text("將批次處理此資料夾內的所有相片，轉換完成後提供逐張比對審查佇列。")
                            .font(.system(size: 11))
                            .foregroundColor(LuminaTheme.Colors.textSecondary)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.02))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.06), lineWidth: 1))
                )
                
            case .selected:
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.rectangle.stack.fill")
                                .foregroundColor(LuminaTheme.Colors.electricIndigo)
                            Text("已勾選 \(viewModel.faceSwapBatchTargets.count) 張相片")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(LuminaTheme.Colors.textPrimary)
                        }
                        Text("針對畫面中多選的相片執行 AI 換臉與逐張比對")
                            .font(.system(size: 11))
                            .foregroundColor(LuminaTheme.Colors.textSecondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.02))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.06), lineWidth: 1))
                )
            }
        }
    }
    
    // MARK: - Source Face Section
    private var sourceFaceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("來源人臉臉孔庫 (SOURCE FACE)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.textSecondary)
                
                Spacer()
                
                Button(action: selectCustomSourceFace) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("匯入自訂臉孔...")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.electricIndigo)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(viewModel.isFaceSwapProcessing)
            }
            
            if viewModel.availableSourceFaces.isEmpty {
                HStack {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .foregroundColor(LuminaTheme.Colors.amberGold)
                    Text("未在 swap/source 目錄偵測到預設臉孔，請點擊上方按鈕匯入。")
                        .font(.system(size: 12))
                        .foregroundColor(LuminaTheme.Colors.textTertiary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.02)))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.availableSourceFaces) { item in
                            sourceFaceCard(item: item)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
            }
        }
    }
    
    private func sourceFaceCard(item: SourceFaceItem) -> some View {
        let isSelected = viewModel.selectedSourceFace?.id == item.id
        
        return Button(action: {
            viewModel.selectedSourceFace = item
        }) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    if let nsImg = NSImage(contentsOf: item.url) {
                        Image(nsImage: nsImg)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 74, height: 74)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: 74, height: 74)
                            .overlay(Image(systemName: "person.fill").foregroundColor(.gray))
                    }
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(LuminaTheme.Colors.electricIndigo)
                            .background(Circle().fill(Color.white).padding(2))
                            .offset(x: 4, y: -4)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? LuminaTheme.Colors.electricIndigo : Color.black.opacity(0.08), lineWidth: isSelected ? 2.5 : 1)
                )
                
                Text(item.name)
                    .font(.system(size: 10.5, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? LuminaTheme.Colors.electricIndigo : LuminaTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .frame(width: 74)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(viewModel.isFaceSwapProcessing)
    }
    
    // MARK: - Parameters Section
    private var parametersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("核心調校參數 (FUSION PARAMETERS)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(LuminaTheme.Colors.textSecondary)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("臉部修復增強權重 (Face Enhancer Blend)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(LuminaTheme.Colors.textPrimary)
                    
                    Spacer()
                    
                    Text("\(Int(viewModel.faceEnhancerBlend))%")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(LuminaTheme.Colors.electricIndigo)
                }
                
                Slider(value: $viewModel.faceEnhancerBlend, in: 0...100, step: 5)
                    .accentColor(LuminaTheme.Colors.electricIndigo)
                    .disabled(viewModel.isFaceSwapProcessing)
                
                HStack {
                    Text("0% (原貌還原)")
                    Spacer()
                    Text("60% (推薦最佳平滑度)")
                    Spacer()
                    Text("100% (極致高清重塑)")
                }
                .font(.system(size: 10))
                .foregroundColor(LuminaTheme.Colors.textTertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.02))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.06), lineWidth: 1))
            )
        }
    }
    
    // MARK: - Status Section
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.isFaceSwapProcessing {
                processingCard
            }
            
            if let errorMsg = viewModel.faceSwapErrorMessage {
                errorCard(message: errorMsg)
            }
        }
    }
    
    private var processingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.7)
            
            VStack(alignment: .leading, spacing: 3) {
                if viewModel.faceSwapBatchTargetMode != .single && viewModel.faceSwapBatchTotalCount > 0 {
                    let cur = viewModel.faceSwapBatchCurrentIndex
                    let total = max(1, viewModel.faceSwapBatchTotalCount)
                    let pct = Int((Double(cur) / Double(total)) * 100)
                    
                    HStack {
                        Text("批次換臉進度: \(cur) / \(total)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(LuminaTheme.Colors.electricIndigo)
                        
                        Spacer()
                        
                        Text("\(pct)%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(LuminaTheme.Colors.electricIndigo)
                    }
                    
                    ProgressView(value: Double(cur), total: Double(total))
                        .accentColor(LuminaTheme.Colors.electricIndigo)
                }
                
                Text(viewModel.faceSwapStatusMessage.isEmpty ? "正在處理中..." : viewModel.faceSwapStatusMessage)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(LuminaTheme.Colors.textSecondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Button("取消運算") {
                viewModel.cancelFaceSwap()
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(LuminaTheme.Colors.neonCoral)
            .buttonStyle(PlainButtonStyle())
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(LuminaTheme.Colors.electricIndigo.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(LuminaTheme.Colors.electricIndigo.opacity(0.2), lineWidth: 1))
        )
    }
    
    private func errorCard(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(LuminaTheme.Colors.neonCoral)
            
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(LuminaTheme.Colors.neonCoral)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(LuminaTheme.Colors.neonCoral.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(LuminaTheme.Colors.neonCoral.opacity(0.2), lineWidth: 1))
        )
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
                        Text("處理中...")
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .bold))
                        
                        if viewModel.faceSwapBatchTargetMode == .single {
                            Text("送出 API 進行換臉")
                        } else {
                            Text("開始批次換臉 (共 \(viewModel.faceSwapBatchTargets.count) 張)")
                        }
                    }
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.vertical, 9)
                .padding(.horizontal, 22)
                .background(
                    Capsule()
                        .fill(isSubmitDisabled ? Color.gray : LuminaTheme.Colors.electricIndigo)
                )
                .shadow(color: LuminaTheme.Colors.electricIndigo.opacity(0.3), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isSubmitDisabled)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.02))
    }
    
    private var isSubmitDisabled: Bool {
        viewModel.selectedSourceFace == nil ||
        viewModel.isFaceSwapProcessing ||
        (viewModel.faceSwapBatchTargetMode != .single && viewModel.faceSwapBatchTargets.isEmpty)
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
