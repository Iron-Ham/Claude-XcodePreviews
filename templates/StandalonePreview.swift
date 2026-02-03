// StandalonePreview.swift - A self-contained SwiftUI view for testing preview capture

import SwiftUI

struct CardView: View {
    let title: String
    let subtitle: String
    let iconName: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.title)
                .foregroundStyle(.blue)
                .frame(width: 44, height: 44)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
}

#Preview("Card View") {
    VStack(spacing: 16) {
        CardView(
            title: "Messages",
            subtitle: "3 unread conversations",
            iconName: "message.fill"
        )

        CardView(
            title: "Calendar",
            subtitle: "Next: Team standup at 10am",
            iconName: "calendar"
        )

        CardView(
            title: "Reminders",
            subtitle: "5 tasks due today",
            iconName: "checklist"
        )
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}
