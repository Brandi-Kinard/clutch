import SwiftUI

struct ProductsSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            CosmicGradientBackground()

            VStack(spacing: 0) {
                // Header bar
                ZStack {
                    Text("Products Nearby")
                        .font(.headline)
                        .foregroundColor(.white)

                    HStack {
                        Spacer()
                        Button { state.showProducts = false } label: {
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
                if state.productItems.isEmpty {
                    Spacer()
                    VStack(spacing: 14) {
                        Image(systemName: "cart.badge.questionmark")
                            .font(.system(size: 44))
                            .foregroundColor(.white.opacity(0.35))
                        Text("No Products Found")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.55))
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(state.productItems) { product in
                                productCard(for: product)
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

    // MARK: - Product Card

    private func productCard(for product: ProductItem) -> some View {
        Button {
            if let url = URL(string: product.url) {
                openURL(url)
            }
        } label: {
            HStack(spacing: 14) {
                // Thumbnail
                productThumbnail(for: product)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.clutchPrimary.opacity(0.30), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    // Stars + review count
                    HStack(spacing: 4) {
                        starView(rating: product.rating)
                        if product.reviews > 0 {
                            Text("(\(product.reviews))")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.55))
                        }
                    }

                    // Store + distance
                    HStack(spacing: 4) {
                        Text(product.store)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.65))
                        if let dist = product.distanceMi {
                            Text("· \(String(format: "%.1f", dist)) mi")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.45))
                        }
                    }
                }

                Spacer()

                // Price
                Text(product.price)
                    .font(.subheadline.bold())
                    .foregroundColor(Color(red: 0.25, green: 0.85, blue: 0.45))
            }
            .padding(14)
            .glassCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private func productThumbnail(for product: ProductItem) -> some View {
        if let url = URL(string: product.thumbnail), !product.thumbnail.isEmpty {
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
            Image(systemName: "cart.fill")
                .font(.title2)
                .foregroundColor(.clutchPrimary.opacity(0.60))
        }
    }

    // MARK: - Stars

    private func starView(rating: Double) -> some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: Double(i) <= rating ? "star.fill" : "star")
                    .font(.system(size: 9))
                    .foregroundColor(Color(red: 1.0, green: 0.75, blue: 0.0))
            }
            Text(String(format: "%.1f", rating))
                .font(.caption2)
                .foregroundColor(.white.opacity(0.70))
                .padding(.leading, 2)
        }
    }
}
