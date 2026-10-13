import SwiftUI
import AppKit

public struct FilmstripView: View {
    @ObservedObject var viewModel: AppViewModel
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(0..<viewModel.displayedImages.count, id: \.self) { index in
                        let item = viewModel.displayedImages[index]
                        let isSelected = viewModel.selectedImageIndex == index
                        let key = item.url.path
                        
                        Button(action: {
                            viewModel.selectedImageIndex = index
                            viewModel.calculateHistogramForSelected()
                            viewModel.prefetchAdjacentImages()
                        }) {
                            ZStack(alignment: .bottom) {
                                // Thumbnail frame
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.black.opacity(0.6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(isSelected ? LuminaTheme.Colors.cyanAccent : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
                                    )
                                    .shadow(color: isSelected ? LuminaTheme.Colors.cyanAccent.opacity(0.4) : Color.clear, radius: 6, x: 0, y: 0)
                                
                                if let cgImage = viewModel.thumbnails[key] {
                                    Image(nsImage: NSImage(cgImage: cgImage, size: .zero))
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 72, height: 50)
                                        .clipped()
                                        .cornerRadius(5)
                                        .padding(isSelected ? 2 : 1)
                                } else {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                        .frame(width: 72, height: 50)
                                }
                                
                                // Mini rating / tag indicator bar
                                if let exif = viewModel.exifMetadata[key] {
                                    HStack(spacing: 2) {
                                        if exif.isTagged {
                                            Circle()
                                                .fill(LuminaTheme.Colors.neonCoral)
                                                .frame(width: 4, height: 4)
                                        }
                                        if exif.rating > 0 {
                                            HStack(spacing: 1) {
                                                Image(systemName: "star.fill")
                                                    .font(.system(size: 6))
                                                    .foregroundColor(LuminaTheme.Colors.amberGold)
                                                Text("\(exif.rating)")
                                                    .font(.system(size: 7, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.65))
                                    .cornerRadius(3)
                                    .padding(2)
                                }
                            }
                            .frame(width: 74, height: 52)
                            .id(index)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.75))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .onChange(of: viewModel.selectedImageIndex) { _, newIndex in
                if let idx = newIndex {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
        }
    }
}
