import SwiftUI

/// マネーフォワード風フィンテックテーマ
enum Theme {
    // Primary
    static let accent = Color(red: 0.18, green: 0.74, blue: 0.56)       // #2EBD8F テールグリーン
    static let accentDark = Color(red: 0.13, green: 0.55, blue: 0.42)   // #218C6B
    static let navy = Color(red: 0.11, green: 0.13, blue: 0.19)         // #1C2130
    static let darkCard = Color(red: 0.15, green: 0.17, blue: 0.24)     // #262B3D

    // Semantic
    static let positive = Color(red: 0.18, green: 0.74, blue: 0.56)     // 上昇・良好
    static let negative = Color(red: 0.93, green: 0.36, blue: 0.36)     // 下落・注意
    static let warning = Color(red: 1.0, green: 0.76, blue: 0.28)       // 警告
    static let info = Color(red: 0.35, green: 0.56, blue: 0.98)         // 情報

    // Text
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textOnDark = Color.white
    static let textMuted = Color(white: 0.6)

    // Background
    static let bgPrimary = Color(.systemBackground)
    static let bgSecondary = Color(.secondarySystemGroupedBackground)
    static let bgCard = Color(.secondarySystemGroupedBackground)

    // Gradients
    static let heroGradient = LinearGradient(
        colors: [accent, accentDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let navyGradient = LinearGradient(
        colors: [navy, darkCard],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Fonts
    static func numericLarge(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
    static func numericMedium(_ size: CGFloat = 18) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
    static func numericSmall(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }
    static let sectionTitle = Font.system(size: 13, weight: .bold)
    static let caption = Font.system(size: 11, weight: .medium)
}

// MARK: - Reusable Card Modifier

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
    }
}

extension View {
    func cardStyle(padding: CGFloat = 16) -> some View {
        modifier(CardStyle(padding: padding))
    }
}

// MARK: - Badge View

struct BadgeView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color)
            .clipShape(Capsule())
    }
}

// MARK: - Section Header

struct FinSectionHeader: View {
    let title: String
    let icon: String?

    init(_ title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            Text(title)
                .font(Theme.sectionTitle)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .padding(.top, 8)
    }
}
