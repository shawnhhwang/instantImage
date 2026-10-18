import SwiftUI
import AppKit

public struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            // Left Sidebar
            FolderTreeView(viewModel: viewModel)
                .frame(minWidth: 220, idealWidth: 260)
        } detail: {
            // Main Stage Area
            ZStack {
                // Base Canvas: Image Grid View
                ImageGridView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(viewModel.isDetailActive || viewModel.isCompareActive ? 0 : 1)
                
                // Fullscreen Metal Detail View
                if viewModel.isDetailActive {
                    ImageDetailView(viewModel: viewModel)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98)).animation(.spring(response: 0.24, dampingFraction: 0.8)),
                            removal: .opacity.animation(.easeOut(duration: 0.16))
                        ))
                        .zIndex(1)
                }
                
                // Multi-Photo Compare Arena
                if viewModel.isCompareActive {
                    CompareView(viewModel: viewModel)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98)).animation(.spring(response: 0.24, dampingFraction: 0.8)),
                            removal: .opacity.animation(.easeOut(duration: 0.16))
                        ))
                        .zIndex(2)
                }
                
                // Loading Indicator: Minimal Floating Pill at Top (Non-Intrusive, No Black Screen Veil)
                if viewModel.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.85)
                        
                        Text("正在快速解析影像快取...")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(LuminaTheme.Colors.textPrimary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.96))
                            .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).clipShape(Capsule()))
                            .overlay(
                                Capsule().stroke(LuminaTheme.Colors.cyanAccent.opacity(0.5), lineWidth: 1)
                            )
                            .shadow(color: LuminaTheme.Shadows.ambient, radius: 12, x: 0, y: 4)
                    )
                    .luminaGlow(color: LuminaTheme.Colors.cyanAccent, radius: 8)
                    .padding(.top, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(3)
                }
                
                // Toast Notification Overlay (Bright Tech Crisp Pill)
                if let toast = viewModel.toastMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(LuminaTheme.Colors.cyanAccent)
                        
                        Text(toast)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(LuminaTheme.Colors.textPrimary)
                    }
                    .padding(.vertical, 9)
                    .padding(.horizontal, 18)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.96))
                            .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).clipShape(Capsule()))
                            .overlay(
                                Capsule().stroke(LuminaTheme.Colors.cyanAccent.opacity(0.4), lineWidth: 1)
                            )
                            .shadow(color: LuminaTheme.Shadows.ambient, radius: 14, x: 0, y: 6)
                    )
                    .luminaGlow(color: LuminaTheme.Colors.cyanAccent, radius: 8)
                    .padding(.bottom, 28)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(4)
                }
                
                // Global Keyboard Shortcuts Sheet Modal Overlay
                if viewModel.isShortcutSheetVisible {
                    KeyboardCheatSheetView(isPresented: $viewModel.isShortcutSheetVisible)
                        .zIndex(5)
                }
                
                // AI FaceSwap Setup Sheet Modal Overlay
                if viewModel.isFaceSwapSetupPresented {
                    FaceSwapSetupView(viewModel: viewModel)
                        .zIndex(6)
                }
                
                // AI FaceSwap Batch Review Arena
                if viewModel.isFaceSwapBatchReviewPresented {
                    FaceSwapBatchReviewView(viewModel: viewModel)
                        .zIndex(7)
                }
                
                // AI FaceSwap Preview & Comparison Arena (Single)
                if viewModel.isFaceSwapPreviewPresented {
                    FaceSwapPreviewView(viewModel: viewModel)
                        .zIndex(8)
                }
                
                // AI FaceSwap Settings Modal Overlay
                if viewModel.isFaceSwapSettingsPresented {
                    FaceSwapSettingsView(viewModel: viewModel)
                        .zIndex(9)
                }
            }
            .navigationTitle(viewModel.selectedFolder?.lastPathComponent ?? "Lumina Pro")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        viewModel.isFaceSwapSettingsPresented = true
                    }) {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .help("FaceFusion API 端點設定")
                }
            }
        }
        .frame(minWidth: 1040, minHeight: 640)
        .preferredColorScheme(.light)
    }
}

// macOS Native NSVisualEffectView wrapper for glassmorphism
public struct VisualEffectView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material = .hudWindow
    public var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    
    public init(material: NSVisualEffectView.Material = .hudWindow, blendingMode: NSVisualEffectView.BlendingMode = .withinWindow) {
        self.material = material
        self.blendingMode = blendingMode
    }
    
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
