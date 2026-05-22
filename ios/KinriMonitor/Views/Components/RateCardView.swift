import SwiftUI

struct RateCardView: View {
    let rate: LatestRate
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rate.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let latest = rate.latest {
                        Text(latest.date)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let latest = rate.latest {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(String(format: "%.3f%%", latest.value))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        if let change = rate.change {
                            HStack(spacing: 2) {
                                Image(systemName: change > 0 ? "arrow.up.right" : change < 0 ? "arrow.down.right" : "minus")
                                    .font(.caption2)
                                Text(String(format: "%+.3f", change))
                                    .font(.caption.monospacedDigit())
                            }
                            .foregroundStyle(change > 0 ? .red : change < 0 ? .green : .secondary)
                        }
                    }
                } else {
                    Text("N/A")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? .blue : .clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
