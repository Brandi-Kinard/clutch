import SwiftUI

struct YouTubeSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            CosmicGradientBackground()

            VStack(spacing: 0) {
                // Header bar
                ZStack {
                    Text("Related Videos")
                        .font(.headline)
                        .foregroundColor(.white)

                    HStack {
                        Spacer()
                        Button { state.showYouTube = false } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white.opacity(0.80))
                                .glassCircle(size: 32)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                // Content
                if state.youtubeVideos.isEmpty {
                    Spacer()
                    VStack(spacing: 14) {
                        Image(systemName: "play.slash.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.white.opacity(0.35))
                        Text("No Videos")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.55))
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(state.youtubeVideos) { video in
                                videoCard(for: video)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .presentationBackground(.clear)
    }

    // MARK: - Video Card

    private func videoCard(for video: YouTubeVideo) -> some View {
        Button {
            if let url = URL(string: video.videoURL) {
                openURL(url)
            }
        } label: {
            HStack(spacing: 14) {
                // Thumbnail with play icon overlay
                ZStack {
                    thumbnail(for: video)
                        .frame(width: 100, height: 68)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.clutchPrimary.opacity(0.30), lineWidth: 1)
                        )

                    // Play icon overlay
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 30, height: 30)
                        Image(systemName: "play.fill")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .offset(x: 1)
                    }
                }
                .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)

                // Title + subtitle
                VStack(alignment: .leading, spacing: 5) {
                    Text(video.title)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Label("Watch on YouTube", systemImage: "arrow.up.forward.app.fill")
                        .font(.caption2)
                        .foregroundColor(.clutchPrimary.opacity(0.85))
                }

                Spacer()
            }
            .padding(14)
            .glassCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private func thumbnail(for video: YouTubeVideo) -> some View {
        if let urlStr = video.thumbnailURL, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    placeholderThumb
                }
            }
        } else {
            placeholderThumb
        }
    }

    private var placeholderThumb: some View {
        ZStack {
            Color.clutchDeepIndigo.opacity(0.60)
            Image(systemName: "play.rectangle.fill")
                .font(.title2)
                .foregroundColor(.clutchPrimary.opacity(0.60))
        }
    }
}
