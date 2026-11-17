import SwiftUI

extension Nutrient {
    /// SF Symbol used as this nutrient's small illustration.
    var symbol: String {
        switch self {
        case .calories: return "flame.fill"
        case .protein: return "fish.fill"
        case .carbs: return "bolt.fill"
        case .fat: return "drop.fill"
        case .fiber: return "leaf.fill"
        case .addedSugar: return "cube.fill"
        case .sodium: return "water.waves"
        case .vitaminD: return "sun.max.fill"
        case .selenium: return "shield.fill"
        case .iron: return "dumbbell.fill"
        case .zinc: return "sparkles"
        case .iodine: return "atom"
        case .magnesium: return "moon.zzz.fill"
        case .vitaminB12: return "brain.head.profile"
        case .calcium: return "figure.walk"
        case .omega3: return "heart.fill"
        }
    }

    var color: Color {
        switch self {
        case .calories: return .orange
        case .protein: return .pink
        case .carbs: return .yellow
        case .fat: return .cyan
        case .fiber: return .green
        case .addedSugar: return .purple
        case .sodium: return .teal
        case .vitaminD: return .orange
        case .selenium: return .indigo
        case .iron: return .red
        case .zinc: return .mint
        case .iodine: return .blue
        case .magnesium: return .purple
        case .vitaminB12: return .pink
        case .calcium: return .brown
        case .omega3: return .red
        }
    }
}

extension Meal {
    var symbol: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snack: return "carrot.fill"
        }
    }

    var color: Color {
        switch self {
        case .breakfast: return .orange
        case .lunch: return .yellow
        case .dinner: return .indigo
        case .snack: return .green
        }
    }
}

/// A symbol on a soft tinted tile.
struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// A circular progress ring that fills clockwise from the top.
struct RingView: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 14

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.spring(duration: 0.6), value: progress)
    }
}

/// A rounded progress bar.
struct CapsuleBar: View {
    let progress: Double
    let color: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.15))
                Capsule()
                    .fill(color.gradient)
                    .frame(width: geometry.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: height)
        .animation(.spring(duration: 0.6), value: progress)
    }
}

/// A friendly placeholder for empty lists.
struct EmptyIllustration: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 110, height: 110)
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 78, height: 78)
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .listRowSeparator(.hidden)
    }
}
