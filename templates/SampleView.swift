import SwiftUI

struct SampleView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "swift")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("SwiftUI Preview")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("This is a sample view for testing the preview capture system.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: {}) {
                Text("Get Started")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)
            .padding(.top, 20)

            Spacer()
        }
        .padding(.top, 60)
    }
}

#Preview {
    SampleView()
}
