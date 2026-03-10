import SwiftUI

struct YouTubeSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Group {
                if state.youtubeVideos.isEmpty {
                    ContentUnavailableView("No Videos", systemImage: "play.slash")
                } else {
                    List(state.youtubeVideos) { video in
                        Button {
                            if let url = URL(string: video.videoURL) {
                                openURL(url)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                thumbnail(for: video)
                                    .frame(width: 80, height: 54)
                                    .cornerRadius(8)
                                    .clipped()

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(video.title)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                    Label("Watch on YouTube", systemImage: "play.fill")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Related Videos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { state.showYouTube = false }
                }
            }
        }
    }

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
            Color(.systemGray5)
            Image(systemName: "play.rectangle.fill")
                .font(.title2)
                .foregroundColor(.secondary)
        }
    }
}
