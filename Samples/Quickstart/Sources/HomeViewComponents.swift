// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderIDSwiftUI

// MARK: - Shared Components

struct UserAvatarView: View {
    let user: User?
    let radius: CGFloat

    var body: some View {
        if let urlString = pictureUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.accentColor.opacity(0.3)
            }
            .frame(width: radius * 2, height: radius * 2)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: radius * 2, height: radius * 2)
                .overlay(
                    Text(initial)
                        .font(.system(size: radius * 0.9, weight: .bold))
                        .foregroundColor(.accentColor)
                )
        }
    }

    private var pictureUrl: String? {
        if let pic = user?.profilePicture, !pic.isEmpty { return pic }
        if let pic = user?.claims?["picture"]?.value as? String, !pic.isEmpty { return pic }
        return nil
    }

    private var initial: String {
        if let name = user?.displayName, !name.isEmpty { return String(name.prefix(1)).uppercased() }
        if let email = user?.email, !email.isEmpty { return String(email.prefix(1)).uppercased() }
        return "?"
    }
}

struct StatItemView: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2).bold()
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct FeatureCardView: View {
    let label: String
    let imageUrl: String
    let isNew: Bool

    var body: some View {
        ZStack {
            AsyncImage(url: URL(string: imageUrl)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.secondary.opacity(0.12)
            }
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading) {
                if isNew {
                    Text("NEW")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor)
                        .cornerRadius(12)
                }
                Spacer()
                Text(label)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Listing Data & Card

struct Listing {
    let title: String
    let location: String
    let price: Int
    let rating: Double
    let imageUrl: String
}

struct ListingCardView: View {
    let listing: Listing

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: URL(string: listing.imageUrl)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.12)
                }
                .frame(height: 130)
                .clipped()

                Image(systemName: "heart")
                    .foregroundColor(.white)
                    .padding(8)
            }
            .frame(height: 130)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(listing.location)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.accentColor)
                    Text(String(format: "%.2f", listing.rating))
                        .font(.caption)
                }
                Text(listing.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                Text("$\(listing.price)/night")
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }
}
