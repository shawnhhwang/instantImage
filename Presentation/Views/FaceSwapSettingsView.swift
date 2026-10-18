import SwiftUI
import AppKit

public struct FaceSwapSettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var apiUrlInput: String = ""
    @State private var pythonInfo: (path: String?, version: String?, hasRequiredPackages: Bool, message: String) = (nil, nil, false, "")
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.45)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    viewModel.isFaceSwapSettingsPresented = false
                }
            
            // Settings Window Card
            VStack(spacing: 0) {
                // Header
                headerView
                
                Divider().background(LuminaTheme.Colors.borderSubtle)
                
                // Content Body
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        // Section 1: API Endpoint Configuration
                        apiEndpointSection
                        
                        // Section 2: Quick Presets
                        presetsSection
                        
                        // Section 3: Connection Test & Diagnostics
                        connectionTestSection
                        
                        // Section 4: Python Environment & Gradio Bridge Status
                        pythonStatusSection
                    }
                    .padding(24)
                }
                .frame(maxHeight: 520)
                
                Divider().background(LuminaTheme.Colors.borderSubtle)
                
                // Footer
                footerView
            }
            .frame(width: 620)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.black.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.22), radius: 28, x: 0, y: 14)
            )
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
        .onAppear {
            self.apiUrlInput = viewModel.faceSwapApiUrl
            self.pythonInfo = FaceSwapService.shared.checkPythonEnvironment()
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LuminaTheme.Colors.electricIndigo.opacity(0.12))
                    .frame(width: 36, height: 36)
                
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.electricIndigo)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("FaceFusion API 端點與連線設定")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.textPrimary)
                
                Text("設定遠端或本機 FaceFusion Gradio 伺服器網址與通訊環境")
                    .font(.system(size: 11))
                    .foregroundColor(LuminaTheme.Colors.textTertiary)
            }
            
            Spacer()
            
            Button(action: {
                viewModel.isFaceSwapSettingsPresented = false
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(LuminaTheme.Colors.textTertiary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(LuminaTheme.Colors.bgSurfaceElevated)
    }
    
    // MARK: - Section 1: API Endpoint
    private var apiEndpointSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("API 伺服器端點 (Gradio Predict URL)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.textPrimary)
                
                Spacer()
                
                LuminaBadge("Gradio 4+ / 5+", color: LuminaTheme.Colors.electricIndigo)
            }
            
            HStack(spacing: 10) {
                TextField("http://192.168.1.3:7870/api/predict", text: $apiUrlInput)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.vertical, 9)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .stroke(LuminaTheme.Colors.borderSubtle, lineWidth: 1)
                            )
                    )
                
                Button(action: {
                    viewModel.testFaceSwapConnection(url: apiUrlInput)
                }) {
                    HStack(spacing: 6) {
                        if viewModel.faceSwapConnectionStatus == .testing {
                            ProgressView()
                                .scaleEffect(0.65)
                        } else {
                            Image(systemName: "bolt.horizontal.fill")
                                .font(.system(size: 12))
                        }
                        Text("測試連線")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(LuminaTheme.Colors.electricIndigo)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(LuminaTheme.Colors.electricIndigo.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .stroke(LuminaTheme.Colors.electricIndigo.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Text("支援完整 URL (包含 /api/predict) 或基礎網址 (如 http://192.168.1.3:7870)，系統將自動對接 Gradio WebSocket Queue。")
                .font(.system(size: 11))
                .foregroundColor(LuminaTheme.Colors.textTertiary)
        }
    }
    
    // MARK: - Section 2: Presets
    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("快速填入預設位置")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(LuminaTheme.Colors.textSecondary)
            
            HStack(spacing: 10) {
                presetButton(title: "🖥️ 本機 Localhost (7860)", url: "http://127.0.0.1:7860/api/predict")
                presetButton(title: "⚡ 區網 GPU 主機 (7870)", url: "http://192.168.1.3:7870/api/predict")
                presetButton(title: "🌐 區網 NAS (7860)", url: "http://192.168.1.100:7860/api/predict")
            }
        }
    }
    
    private func presetButton(title: String, url: String) -> some View {
        Button(action: {
            self.apiUrlInput = url
            viewModel.testFaceSwapConnection(url: url)
        }) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(apiUrlInput == url ? LuminaTheme.Colors.electricIndigo : LuminaTheme.Colors.textSecondary)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(apiUrlInput == url ? LuminaTheme.Colors.electricIndigo.opacity(0.08) : Color.black.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(apiUrlInput == url ? LuminaTheme.Colors.electricIndigo.opacity(0.3) : Color.black.opacity(0.06), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Section 3: Connection Diagnostic Card
    private var connectionTestSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("連線診斷狀態")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(LuminaTheme.Colors.textSecondary)
            
            HStack(spacing: 12) {
                switch viewModel.faceSwapConnectionStatus {
                case .idle:
                    Image(systemName: "circle.dotted")
                        .foregroundColor(LuminaTheme.Colors.textTertiary)
                    Text("尚未測試連線，點擊上方「測試連線」驗證 API 端點")
                        .font(.system(size: 12))
                        .foregroundColor(LuminaTheme.Colors.textTertiary)
                    
                case .testing:
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("正在向端點發送交握請求並測量延遲...")
                        .font(.system(size: 12))
                        .foregroundColor(LuminaTheme.Colors.electricIndigo)
                    
                case .connected(let latencyMs):
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(LuminaTheme.Colors.mintEmerald)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("連線成功！FaceFusion 伺服器運作正常")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(LuminaTheme.Colors.mintEmerald)
                            
                            LuminaBadge("\(latencyMs) ms", color: LuminaTheme.Colors.mintEmerald)
                        }
                        Text(viewModel.faceSwapConnectionMessage)
                            .font(.system(size: 11))
                            .foregroundColor(LuminaTheme.Colors.textSecondary)
                    }
                    
                case .failed(let error):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(LuminaTheme.Colors.neonCoral)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("無法連線至 FaceFusion 伺服器")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(LuminaTheme.Colors.neonCoral)
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(LuminaTheme.Colors.textSecondary)
                    }
                }
                
                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
            )
        }
    }
    
    // MARK: - Section 4: Python Environment Card
    private var pythonStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("本機 Python 與 Gradio 中繼狀態")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(LuminaTheme.Colors.textSecondary)
                
                Spacer()
                
                if pythonInfo.hasRequiredPackages {
                    LuminaBadge("環境就緒 (Ready)", color: LuminaTheme.Colors.mintEmerald)
                } else {
                    LuminaBadge("環境需配置", color: LuminaTheme.Colors.amberGold)
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                if let path = pythonInfo.path {
                    HStack(spacing: 6) {
                        Text("Python 執行檔:")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(LuminaTheme.Colors.textSecondary)
                        Text(path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(LuminaTheme.Colors.textPrimary)
                    }
                }
                
                HStack(spacing: 6) {
                    Text("核心通訊套件:")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(LuminaTheme.Colors.textSecondary)
                    Text("gradio_client, Pillow, pillow-heif, requests")
                        .font(.system(size: 11))
                        .foregroundColor(pythonInfo.hasRequiredPackages ? LuminaTheme.Colors.mintEmerald : LuminaTheme.Colors.neonCoral)
                }
                
                Text("📌 提示: 目前前端與渲染 100% 純原生 Swift；API 佇列透過背景無頭 Python 驅動。純 Swift Gradio WebSocket 模組已納入底層升級排程。")
                    .font(.system(size: 10))
                    .foregroundColor(LuminaTheme.Colors.textTertiary)
                    .padding(.top, 4)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
            )
        }
    }
    
    // MARK: - Footer
    private var footerView: some View {
        HStack(spacing: 12) {
            Button(action: {
                viewModel.isFaceSwapSettingsPresented = false
            }) {
                Text("取消")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(LuminaTheme.Colors.textSecondary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.04))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            Button(action: {
                viewModel.saveFaceSwapApiUrl(apiUrlInput)
                viewModel.isFaceSwapSettingsPresented = false
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                    Text("儲存端點設定")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 20)
                .background(
                    Capsule()
                        .fill(LuminaTheme.Colors.electricIndigo)
                )
                .shadow(color: LuminaTheme.Colors.electricIndigo.opacity(0.3), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(LuminaTheme.Colors.bgSurfaceElevated)
    }
}
