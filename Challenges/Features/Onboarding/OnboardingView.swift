import SwiftUI
import AuthenticationServices

/// First-launch onboarding: Sign in with Apple → HealthKit explanation → permissions.
struct OnboardingView: View {
    @Environment(UserSession.self) private var session
    @State private var showHealthExplanation = false
    @State private var isRequestingHealth = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if showHealthExplanation {
                HealthExplanationView {
                    requestHealthKitPermission()
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                signInView
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showHealthExplanation)
    }

    // MARK: - Sign-in screen

    private var signInView: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            VStack(spacing: 20) {
                ZStack {
                    // Concentric ring decorations matching Apple Fitness colors
                    Circle()
                        .stroke(Color.moveRing.opacity(0.25), lineWidth: 3)
                        .frame(width: 110, height: 110)
                    Circle()
                        .stroke(Color.exerciseRing.opacity(0.25), lineWidth: 3)
                        .frame(width: 84, height: 84)
                    Circle()
                        .stroke(Color.standRing.opacity(0.25), lineWidth: 3)
                        .frame(width: 58, height: 58)

                    Image(systemName: "trophy.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.moveRing, .exerciseRing],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                }
                .padding(.bottom, 8)

                Text("Challenges")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)

                Text("Compete with friends.\nSee who closes their rings.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(white: 0.60))
            }

            Spacer()

            // Sign in with Apple — white style on black background
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                handleSignInResult(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 54)
            .padding(.horizontal, 32)

            Text("Your health data never leaves Apple's servers.")
                .font(.caption)
                .foregroundStyle(Color(white: 0.45))
                .multilineTextAlignment(.center)
                .padding(.top, 14)
                .padding(.bottom, 52)
        }
    }

    // MARK: - Sign-in handler

    private func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential
        else { return }

        Task {
            // Delegate to AuthManager which does the CK linkage internally.
            await AuthManager.shared.handleSignInCompletion(credential: credential,
                                                             session: session)
            showHealthExplanation = true
        }
    }

    // MARK: - HealthKit permission

    private func requestHealthKitPermission() {
        isRequestingHealth = true
        Task {
            try? await HealthKitManager.shared.requestAuthorization()

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
