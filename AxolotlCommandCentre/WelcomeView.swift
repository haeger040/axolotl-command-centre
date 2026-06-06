import SwiftUI

struct WelcomeView: View {
    let onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 28)

            Image("AxolotlLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 170, height: 170)
                .padding(.bottom, 22)

            VStack(spacing: 8) {
                Text("Welcome to Axolotl!")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Your mobile command centre")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.64))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            VStack(alignment: .center, spacing: 13) {
                Text("You will unlock on the go:")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 3)

                VStack(alignment: .leading, spacing: 13) {
                    WelcomeCapabilityRow(text: "your agents")
                    WelcomeCapabilityRow(text: "file exploration")
                    WelcomeCapabilityRow(text: "file edition")
                    WelcomeCapabilityRow(text: "your full terminal")
                    WelcomeCapabilityRow(text: "full source control")
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 28)
            .padding(.top, 34)

            Spacer(minLength: 22)

            Button(action: onUnlock) {
                Text("Unlock!")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 1.00, green: 0.24, blue: 0.55),
                                Color(red: 0.42, green: 0.34, blue: 0.95)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.09, blue: 0.10))
    }
}

private struct WelcomeCapabilityRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 1.00, green: 0.30, blue: 0.62))
                .frame(width: 18, alignment: .center)

            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
        }
    }
}

#Preview {
    WelcomeView {}
}
