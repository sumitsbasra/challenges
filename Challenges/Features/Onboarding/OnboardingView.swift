import SwiftUI
import AuthenticationServices

/// First-launch onboarding: Sign in with Apple → HealthKit explanation → permissions.
struct OnboardingView: View {
    @Environment(UserSession.self) private var session
    @StateObject private var auth = AuthManager.shared
    @State private var showHealthExplanation = false
    @State private var isRequestingHealth = false

    var body: some View {
        if showHealthExplanation {
            HealthExplanationView {
                requestHealthKitPermission()
            }
        } else {
            signInView
        }
    }

    private var signInView: some View {
        VStack(spacing: 0) {
            Spacer()

            // App logo area
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(
                            LinearGradient(colors: [.moveRing, .exerciseRing],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing)
                        )
                        .frame(width: 100, height: 100)
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.white)
                }
                Text("Challenges")
                    .font(.largeTitle.bold())
                Text("Compete with friends.\nClose your rings.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.secondaryText)
            }
            .padding(.bottom, 64)

            Spacer()

            // Sign in with Apple
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                handleSignInResult(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 52)
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
        .background(Color.appBackground.ignoresSafeArea())
    }

    private func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            Task {
                await AuthManager.shared.handleExternalCredential(credential)
                showHealthExplanation = true
            }
        case .failure:
            break
        }
    }

    private func requestHealthKitPermission() {
        isRequestingHealth = true
        Task {
            try? await HealthKitManager.shared.requestAuthorization()
            // Detect Watch and update user record.
            let hasWatch = await WatchDetector().detectAppleWatch()
            UserDefaults.standard.set(hasWatch, forKey: "hasAppleWatch")
            if var user = session.currentUser {
                user.hasAppleWatch = hasWatch
                session.update(user: user)
                try? await CloudKitManager.shared.saveUser(user)
            }
            isRequestingHealth = false
        }
    }
}
