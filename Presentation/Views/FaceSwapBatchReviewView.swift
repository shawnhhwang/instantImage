import SwiftUI
import AppKit

public struct FaceSwapBatchReviewView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var splitCurtainPosition: CGFloat = 0.5
    @State private var showCompleteSheet: Bool = false
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    private var currentIndex: Int {
        viewModel.faceSwapBatchReviewIndex
    }
    
    private var totalCount: Int {
        viewModel.faceSwapBatchItems.count
    }
    
    private var currentItem: FaceSwapBatchItem? {
        guard currentIndex >= 0 && currentIndex < viewModel.faceSwapBatchItems.count else { return nil }
        return viewModel.faceSwapBatchItems[currentIndex]
    }
    
    private var savedCount: Int {
        viewModel.faceSwapBatchItems.filter { $0.decision == .saved }.count
    }
    
    private var keptOriginalCount: Int {
        viewModel.faceSwapBatchItems.filter { $0.decision == .keptOriginal }.count
    }
    
    private var pendingCount: Int {
        viewModel.faceSwapBatchItems.filter { $0.decision == .pending }.count
    }
    
    public var body: some View {
        ZStack {
            // Background
            LuminaTheme.Colors.darkroomCanvas
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // 1. Top Navigation Bar
                topNavigationBar
                
                Divider().background(LuminaTheme.Colors.borderSubtle)
                
                // 2. Batch Thumbnail Filmstrip
                batchThumbnailStrip
                
                Divider().background(LuminaTheme.Colors.borderSubtle)
                
                // 3. Central Stage (Before/After Comparison)
                GeometryReader { geo in
                    if let item = currentItem {
                        if let result = item.result {
                            if viewModel.faceSwapPreviewMode == .splitCurtain {
                                splitCurtainComparison(item: item, result: result, size: geo.size)
                            } else {
                                sideBySideComparison(item: item, result: result, size: geo.size)
                            }
                        } else if let errorMsg = item.errorMessage {
                            errorStage(item: item, error: errorMsg)
                        } else {
                            loadingStage(item: item)
                        }
                    } else {
                        emptyStage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Completion Alert Banner
                if pendingCount == 0 && totalCount > 0 {
                    HStack(spacing: 14) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 15))
                            .foregroundColor(LuminaTheme.Colors.mintEmerald)
                        
                        Text("🎉 所有相片已審查完成！已標記取代 \(savedCount) 張，保持原圖 \(keptOriginalCount) 張。")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(LuminaTheme.Colors.textPrimary)
                        
                        Spacer()
                        
                        Button(action: {
                            viewModel.applyBatchDecisionsAndFinish()
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("立即套用取代並完成審查")
                            }
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 14)
                            .background(Capsule().fill(LuminaTheme.Colors.mintEmerald))
                            .shadow(color: LuminaTheme.Colors.mintEmerald.opacity(0.35), radius: 6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.95))
                    .overlay(Rectangle().fill(LuminaTheme.Colors.mintEmerald.opacity(0.3)).frame(height: 1), alignment: .top)
                }
                
                Divider().background(LuminaTheme.Colors.borderSubtle)
                
                // 4. Bottom Decision Deck (Keep Original vs Save Swapped)
                bottomDecisionDeck
            }
        }
        .onAppear {
            setupKeyboardMonitor()
        }
    }
    
    // MARK: - 1. Top Navigation Bar
    private var topNavigationBar: some View {
        HStack(spacing: 14) {
            // Apply Decisions & Finish button
            Button(action: {
                viewModel.applyBatchDecisionsAndFinish()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text(savedCount > 0 ? "完成審查並套用取代 (\(savedCount) 張)" : "完成審查 (保持原圖)")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(savedCount > 0 ? .white : LuminaTheme.Colors.textPrimary)
                .padding(.vertical, 7)
                .padding(.horizontal, 14)
                .background(
                    Capsule()
                        .fill(savedCount > 0 ? LuminaTheme.Colors.mintEmerald : Color.white)
                        .overlay(Capsule().stroke(Color.black.opacity(savedCount > 0 ? 0 : 0.12), lineWidth: 1))
                )
                .shadow(color: savedCount > 0 ? LuminaTheme.Colors.mintEmerald.opacity(0.3) : Color.clear, radius: 4)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Close / Cancel without applying
            Button(action: {
                viewModel.finishBatchReview(applyDecisions: false)
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.black.opacity(0.05)))
            }
            .buttonStyle(PlainButtonStyle())
            .help("關閉審查 (不套用取代)")
            
            // Current photo title & counter
            HStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack")
                    .foregroundColor(LuminaTheme.Colors.electricIndigo)
                
                Text("相片 \(currentIndex + 1) / \(max(1, totalCount))")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.textPrimary)
                
                if let item = currentItem {
                    Text("•  \(item.filename)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(LuminaTheme.Colors.textSecondary)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 12)
            .luminaGlass(cornerRadius: LuminaTheme.Radius.pill)
            
            // Decision Summary Counters
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(LuminaTheme.Colors.mintEmerald)
                    Text("標記儲存: \(savedCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(LuminaTheme.Colors.textPrimary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Capsule().fill(LuminaTheme.Colors.mintEmerald.opacity(0.12)))
                
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .foregroundColor(LuminaTheme.Colors.textTertiary)
                    Text("保持原圖: \(keptOriginalCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(LuminaTheme.Colors.textPrimary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Capsule().fill(Color.black.opacity(0.05)))
                
                if pendingCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.badge.questionmark.fill")
                            .foregroundColor(LuminaTheme.Colors.amberGold)
                        Text("待決定: \(pendingCount)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(LuminaTheme.Colors.textPrimary)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Capsule().fill(LuminaTheme.Colors.amberGold.opacity(0.14)))
                }
            }
            
            Spacer()
            
            // Mode Switcher
            HStack(spacing: 4) {
                ForEach(FaceSwapPreviewMode.allCases) { mode in
                    Button(action: {
                        viewModel.faceSwapPreviewMode = mode
                    }) {
                        Text(mode.rawValue)
                            .font(.system(size: 11, weight: viewModel.faceSwapPreviewMode == mode ? .bold : .medium))
                            .foregroundColor(viewModel.faceSwapPreviewMode == mode ? LuminaTheme.Colors.electricIndigo : LuminaTheme.Colors.textSecondary)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 10)
                            .background(
                                Capsule()
                                    .fill(viewModel.faceSwapPreviewMode == mode ? Color.white : Color.clear)
                                    .shadow(color: Color.black.opacity(viewModel.faceSwapPreviewMode == mode ? 0.08 : 0), radius: 3, x: 0, y: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(3)
            .background(Capsule().fill(Color.black.opacity(0.05)))
            
            // Batch Actions Dropdown
            Menu {
                Button("全部標記為儲存取代原檔 (待決定相片)") {
                    viewModel.decideAllBatchItems(decision: .saved)
                }
                Button("全部保持原圖 (略過待決定相片)") {
                    viewModel.decideAllBatchItems(decision: .keptOriginal)
                }
            } label: {
                HStack(spacing: 4) {
                    Text("批次標記")
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                }
                .foregroundColor(LuminaTheme.Colors.textSecondary)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.1), lineWidth: 1))
                )
            }
            .menuStyle(BorderlessButtonMenuStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            Color.white
                .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))
        )
    }
    
    // MARK: - 2. Batch Thumbnail Filmstrip
    private var batchThumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(viewModel.faceSwapBatchItems.enumerated()), id: \.element.id) { idx, item in
                        batchThumbnailCell(index: idx, item: item)
                            .id(idx)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .frame(height: 72)
            .background(Color.white.opacity(0.75))
            .onChange(of: viewModel.faceSwapBatchReviewIndex) { _, newIdx in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newIdx, anchor: .center)
                }
            }
        }
    }
    
    private func batchThumbnailCell(index: Int, item: FaceSwapBatchItem) -> some View {
        let isSelected = index == viewModel.faceSwapBatchReviewIndex
        
        return Button(action: {
            viewModel.faceSwapBatchReviewIndex = index
        }) {
            ZStack(alignment: .topTrailing) {
                // Thumbnail Image
                Group {
                    if let img = NSImage(contentsOf: item.result?.previewOutputURL ?? item.targetURL) {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.gray.opacity(0.2)
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                
                // Status Badge Overlay
                statusBadge(decision: item.decision, hasError: item.errorMessage != nil)
                    .offset(x: 4, y: -4)
            }
            .padding(2)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? LuminaTheme.Colors.electricIndigo : Color.clear, lineWidth: 2)
            )
            .shadow(color: isSelected ? LuminaTheme.Colors.electricIndigo.opacity(0.3) : Color.clear, radius: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func statusBadge(decision: FaceSwapDecision, hasError: Bool) -> some View {
        Group {
            if hasError {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(LuminaTheme.Colors.neonCoral)
                    .background(Circle().fill(Color.white).padding(1))
            } else {
                switch decision {
                case .saved:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(LuminaTheme.Colors.mintEmerald)
                        .background(Circle().fill(Color.white).padding(1))
                case .keptOriginal:
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .foregroundColor(LuminaTheme.Colors.textTertiary)
                        .background(Circle().fill(Color.white).padding(1))
                case .pending:
                    Circle()
                        .fill(LuminaTheme.Colors.amberGold)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                }
            }
        }
        .font(.system(size: 13))
    }
    
    // MARK: - 3. Central Stage (Split Curtain)
    private func splitCurtainComparison(item: FaceSwapBatchItem, result: FaceSwapResult, size: CGSize) -> some View {
        let originalImg = NSImage(contentsOf: item.targetURL)
        let swappedImg = NSImage(contentsOf: result.previewOutputURL)
        
        return ZStack {
            // Right Side: Swapped Output
            if let swapped = swappedImg {
                Image(nsImage: swapped)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)
            }
            
            // Left Side: Original Image with Curtain Mask
            if let original = originalImg {
                Image(nsImage: original)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)
                    .mask(
                        HStack(spacing: 0) {
                            Rectangle()
                                .frame(width: max(0, size.width * splitCurtainPosition))
                            Spacer(minLength: 0)
                        }
                    )
            }
            
            // Interactive Divider Handle
            ZStack {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2)
                    .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 0)
                
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .bold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(LuminaTheme.Colors.textPrimary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 2)
                )
            }
            .position(x: size.width * splitCurtainPosition, y: size.height / 2)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newPos = value.location.x / size.width
                        self.splitCurtainPosition = max(0.02, min(0.98, newPos))
                    }
            )
            
            // Top Corner Mode Tags
            VStack {
                HStack {
                    LuminaBadge("原圖 (保持不變)", color: LuminaTheme.Colors.textSecondary)
                        .padding(.leading, 24)
                        .padding(.top, 16)
                    
                    Spacer()
                    
                    LuminaBadge("AI 換臉成果", color: LuminaTheme.Colors.electricIndigo)
                        .padding(.trailing, 24)
                        .padding(.top, 16)
                }
                Spacer()
            }
        }
    }
    
    // MARK: - 3. Central Stage (Side-by-Side)
    private func sideBySideComparison(item: FaceSwapBatchItem, result: FaceSwapResult, size: CGSize) -> some View {
        let originalImg = NSImage(contentsOf: item.targetURL)
        let swappedImg = NSImage(contentsOf: result.previewOutputURL)
        let halfWidth = (size.width - 24) / 2
        
        return HStack(spacing: 16) {
            // Left: Original
            VStack(spacing: 8) {
                LuminaBadge("原圖 (保持不變)", color: LuminaTheme.Colors.textSecondary)
                
                ZStack {
                    if let original = originalImg {
                        Image(nsImage: original)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: halfWidth)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.85)))
            
            // Right: Swapped
            VStack(spacing: 8) {
                LuminaBadge("AI 換臉成果 (100% HEIC)", color: LuminaTheme.Colors.electricIndigo)
                
                ZStack {
                    if let swapped = swappedImg {
                        Image(nsImage: swapped)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: halfWidth)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.85)))
        }
        .padding(16)
    }
    
    private func errorStage(item: FaceSwapBatchItem, error: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundColor(LuminaTheme.Colors.neonCoral)
            
            Text("此相片換臉處理發生錯誤")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(LuminaTheme.Colors.textPrimary)
            
            Text(error)
                .font(.system(size: 12))
                .foregroundColor(LuminaTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            
            Text("建議點擊「保持原圖」以略過此相片繼續下一張。")
                .font(.system(size: 11))
                .foregroundColor(LuminaTheme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func loadingStage(item: FaceSwapBatchItem) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在加載換臉成果影像...")
                .font(.system(size: 12))
                .foregroundColor(LuminaTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStage: some View {
        VStack(spacing: 8) {
            Text("批次審查佇列為空")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(LuminaTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 4. Bottom Decision Deck
    private var bottomDecisionDeck: some View {
        HStack(spacing: 16) {
            // Previous Item Button
            Button(action: {
                viewModel.previousBatchReviewItem()
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                    Text("上一張")
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(currentIndex > 0 ? LuminaTheme.Colors.textPrimary : LuminaTheme.Colors.textTertiary)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.1), lineWidth: 1))
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(currentIndex == 0)
            
            // Current Decision Indicator Pill
            if let item = currentItem {
                HStack(spacing: 6) {
                    Text("目前決策:")
                        .font(.system(size: 11))
                        .foregroundColor(LuminaTheme.Colors.textTertiary)
                    
                    Text(item.decision.rawValue)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(
                            item.decision == .saved ? LuminaTheme.Colors.mintEmerald :
                            (item.decision == .keptOriginal ? LuminaTheme.Colors.textSecondary : LuminaTheme.Colors.amberGold)
                        )
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(Capsule().fill(Color.black.opacity(0.04)))
            }
            
            Spacer()
            
            // Core Action 1: Keep Original (Skip)
            Button(action: {
                viewModel.decideBatchItem(at: currentIndex, decision: .keptOriginal)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 13, weight: .bold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("保持原圖 (略過)")
                            .font(.system(size: 13, weight: .bold))
                        Text("快捷鍵: DEL / X / 空白鍵")
                            .font(.system(size: 9))
                            .opacity(0.7)
                    }
                }
                .foregroundColor(LuminaTheme.Colors.textPrimary)
                .padding(.vertical, 9)
                .padding(.horizontal, 18)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(currentItem?.decision == .keptOriginal ? Color.black.opacity(0.08) : Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(currentItem?.decision == .keptOriginal ? Color.black.opacity(0.3) : Color.black.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Core Action 2: Save Swapped Image
            Button(action: {
                viewModel.decideBatchItem(at: currentIndex, decision: .saved)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: currentItem?.decision == .saved ? "checkmark.circle.fill" : "sparkles.rectangle.stack.fill")
                        .font(.system(size: 14, weight: .bold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("標記儲存取代原檔")
                            .font(.system(size: 13, weight: .bold))
                        Text("完成審查時套用取代 • 快捷鍵: Enter / S")
                            .font(.system(size: 9))
                            .opacity(0.85)
                    }
                }
                .foregroundColor(.white)
                .padding(.vertical, 9)
                .padding(.horizontal, 24)
                .background(
                    Capsule()
                        .fill(currentItem?.decision == .saved ? LuminaTheme.Colors.mintEmerald : LuminaTheme.Colors.electricIndigo)
                )
                .shadow(color: (currentItem?.decision == .saved ? LuminaTheme.Colors.mintEmerald : LuminaTheme.Colors.electricIndigo).opacity(0.35), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(currentItem?.result == nil)
            
            Spacer()
            
            // Next Item Button
            Button(action: {
                viewModel.nextBatchReviewItem()
            }) {
                HStack(spacing: 5) {
                    Text("下一張")
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(currentIndex < totalCount - 1 ? LuminaTheme.Colors.textPrimary : LuminaTheme.Colors.textTertiary)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.1), lineWidth: 1))
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(currentIndex >= totalCount - 1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            Color.white
                .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))
        )
    }
    
    // MARK: - Keyboard Monitor
    private func setupKeyboardMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard viewModel.isFaceSwapBatchReviewPresented else { return event }
            
            switch event.keyCode {
            case 51, 117, 7, 49: // Delete, Forward Delete, X, Spacebar -> Keep Original
                viewModel.decideBatchItem(at: viewModel.faceSwapBatchReviewIndex, decision: .keptOriginal)
                return nil
            case 36, 76, 1: // Enter, Keypad Enter, S -> Save Swapped
                viewModel.decideBatchItem(at: viewModel.faceSwapBatchReviewIndex, decision: .saved)
                return nil
            case 123: // Left Arrow -> Previous
                viewModel.previousBatchReviewItem()
                return nil
            case 124: // Right Arrow -> Next
                viewModel.nextBatchReviewItem()
                return nil
            case 53: // ESC -> Finish without applying
                viewModel.finishBatchReview(applyDecisions: false)
                return nil
            default:
                return event
            }
        }
    }
}
