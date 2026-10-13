import SwiftUI

public struct KeyboardCheatSheetView: View {
    @Binding var isPresented: Bool
    
    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }
    
    private struct ShortcutItem: Identifiable {
        let id = UUID()
        let keys: [String]
        let description: String
    }
    
    private struct ShortcutSection: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        let items: [ShortcutItem]
    }
    
    private let sections: [ShortcutSection] = [
        ShortcutSection(
            title: "瀏覽導航 (Navigation)",
            icon: "arrow.left.and.right",
            items: [
                ShortcutItem(keys: ["◀", "▶"], description: "上一張 / 下一張照片"),
                ShortcutItem(keys: ["▲", "▼"], description: "跳至第一張 / 最後一張"),
                ShortcutItem(keys: ["Space"], description: "進入 / 退出高解析詳細檢視"),
                ShortcutItem(keys: ["Esc"], description: "退出詳細檢視或對比模式"),
                ShortcutItem(keys: ["Z"], description: "切換 100% 滿版像素對焦檢查"),
                ShortcutItem(keys: ["F", "Enter"], description: "切換 macOS 原生全螢幕"),
                ShortcutItem(keys: ["L"], description: "開啟 / 關閉 2.5× 局部高解析放大鏡")
            ]
        ),
        ShortcutSection(
            title: "極速挑片評估 (ACDSee Culling)",
            icon: "star.fill",
            items: [
                ShortcutItem(keys: ["1", "–", "5"], description: "設定 1 至 5 星級評等"),
                ShortcutItem(keys: ["0"], description: "清除星級評等 (未評級)"),
                ShortcutItem(keys: ["T"], description: "切換標記 / 取消標記 (Flagged)"),
                ShortcutItem(keys: ["M"], description: "搬移至目標資料夾 (Culling Move)"),
                ShortcutItem(keys: ["⌘", "Delete"], description: "安全移至資源回收桶 (Trash)")
            ]
        ),
        ShortcutSection(
            title: "暗房光線調校 (Lightroom Tone)",
            icon: "wand.and.stars",
            items: [
                ShortcutItem(keys: ["E"], description: "一鍵自動最佳化光線 (Auto Tone)"),
                ShortcutItem(keys: ["W"], description: "自動白平衡校正 (Auto WB)"),
                ShortcutItem(keys: ["\\"], description: "切換左右前後對比分割簾 (Before/After)"),
                ShortcutItem(keys: ["J"], description: "開啟過曝(紅)與死黑(藍)剪裁警告"),
                ShortcutItem(keys: ["⌘", "C"], description: "複製當前照片之調光參數"),
                ShortcutItem(keys: ["⌘", "V"], description: "貼上並同步調光參數至選取照片")
            ]
        ),
        ShortcutSection(
            title: "介面與系統 (Interface)",
            icon: "slider.horizontal.3",
            items: [
                ShortcutItem(keys: ["⌘", "F"], description: "聚焦即時檔名與元數據搜尋列"),
                ShortcutItem(keys: ["?"], description: "顯示 / 關閉本快捷鍵指南"),
                ShortcutItem(keys: ["雙擊滑鼠"], description: "網格雙擊開圖 / 詳細檢視雙擊縮放")
            ]
        )
    ]
    
    public var body: some View {
        ZStack {
            // Backdrop dimming blur
            Color.black.opacity(0.65)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isPresented = false
                    }
                }
            
            // Modal Sheet Card
            VStack(spacing: 0) {
                headerView
                Divider().background(Color.white.opacity(0.08))
                contentGrid
                Divider().background(Color.white.opacity(0.08))
                footerView
            }
            .frame(width: 720)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.085, blue: 0.11))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.6), radius: 30, x: 0, y: 15)
            )
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }
    
    private var headerView: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "command.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(LuminaTheme.Colors.cyanAccent)
                    .luminaGlow(color: LuminaTheme.Colors.cyanAccent, radius: 8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("LUMINA PRO 快捷鍵指南")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(LuminaTheme.Colors.textPrimary)
                    Text("專業攝影師極速盲操選片工作流")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(LuminaTheme.Colors.textSecondary)
                }
            }
            
            Spacer()
            
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isPresented = false
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(Color.white.opacity(0.03))
    }
    
    private var contentGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)], spacing: 18) {
                ForEach(sections) { section in
                    sectionCard(section: section)
                }
            }
            .padding(22)
        }
        .frame(maxHeight: 500)
    }
    
    private func sectionCard(section: ShortcutSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: section.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(LuminaTheme.Colors.cyanAccent)
                Text(section.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.textPrimary)
            }
            .padding(.bottom, 2)
            
            VStack(spacing: 7) {
                ForEach(section.items) { item in
                    HStack {
                        Text(item.description)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(LuminaTheme.Colors.textSecondary)
                        
                        Spacer()
                        
                        HStack(spacing: 3) {
                            ForEach(item.keys, id: \.self) { key in
                                KeyCap(key: key)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
    
    private var footerView: some View {
        HStack {
            Text("提示：可在任何介面隨時按下 ? 鍵開啟此面板")
                .font(.system(size: 11))
                .foregroundColor(LuminaTheme.Colors.textTertiary)
            Spacer()
            Button("了解並關閉") {
                withAnimation { isPresented = false }
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(LuminaTheme.Colors.cyanAccent)
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .background(
                Capsule()
                    .fill(LuminaTheme.Colors.cyanAccent.opacity(0.15))
                    .overlay(Capsule().stroke(LuminaTheme.Colors.cyanAccent.opacity(0.4), lineWidth: 1))
            )
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.4))
    }
}

// KeyCap Visual Component
private struct KeyCap: View {
    let key: String
    
    var body: some View {
        Text(key)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(LuminaTheme.Colors.textPrimary)
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.09))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 0.75)
                    )
                    .shadow(color: Color.black.opacity(0.4), radius: 1, x: 0, y: 1)
            )
    }
}
