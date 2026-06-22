import SwiftUI
import OSLog
import AuthenticationServices
import UIKit
import UserNotifications

struct OnboardingView: View {
    @Environment(UserSession.self) private var session
    @State private var step: Step = .signIn

    // Shared ring state — owned here, animated across steps
    @State private var moveProgress: CGFloat    = 0
    @State private var exerciseProgress: CGFloat = 0
    @State private var standProgress: CGFloat   = 0
    @State private var contentVisible           = false
    @State private var checkVisible             = false
    @State private var welcomeName              = ""
    @State private var ringsMerging             = false   // phase 1
    @State private var ringsCollapsed           = false   // phase 2

    enum Step { case signIn, health, name, notifications, welcome }

    // MARK: - Ring geometry (drives persistent layer)

    private var ringSize: CGFloat {
        (step == .health || step == .notifications) ? 80 : 136
    }
    private var ringLineWidth: CGFloat {
        (step == .health || step == .notifications) ? 10 : 14
    }
    /// Ring center expressed as a fraction of screen height
    private func ringCenterY(_ h: CGFloat) -> CGFloat {
        switch step {
        case .health, .notifications:  return h * 0.21
        default:                       return h * 0.34
        }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // ── Content layer (no rings) ──────────────────────────
                Group {
                    switch step {
                    case .signIn:
                        SignInContent(
                            contentVisible: contentVisible,
                            ringBottomY: ringCenterY(geo.size.height) + ringSize / 2,
                            onSignedIn: handleSignIn
                        )
                        .transition(.asymmetric(insertion: .opacity, removal: .opacity))

                    case .health:
                        HealthContent(
                            ringBottomY: ringCenterY(geo.size.height) + ringSize / 2,
                            onContinue: requestHealthKit
                        )
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeIn.delay(0.2)),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))

                    case .name:
                        NameEntryScreen(initialName: welcomeName, onContinue: handleName)
                            .transition(.asymmetric(
                                insertion: .opacity,
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))

                    case .notifications:
                        NotificationsContent(
                            ringBottomY: ringCenterY(geo.size.height) + ringSize / 2,
                            onContinue: requestNotifications
                        )
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeIn.delay(0.2)),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))

                    case .welcome:
                        WelcomeContent(
                            name: welcomeName,
                            ringBottomY: ringCenterY(geo.size.height) + ringSize / 2,
                            onComplete: completeOnboarding
                        )
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeIn.delay(0.1)),
                            removal: .opacity
                        ))
                    }
                }
                .animation(.easeInOut(duration: 0.35), value: step)

                // ── Persistent ring layer ─────────────────────────────
                // Hidden during name-entry (avatar circle replaces rings)
                if step != .name || ringsMerging || ringsCollapsed {
                    ringsOverlay(geo: geo)
                        .transition(.opacity.animation(.easeOut(duration: 0.2)))
                }
            }
        }
        .onAppear { animateSignInRings() }
    }

    // MARK: - Ring overlay

    @ViewBuilder
    private func ringsOverlay(geo: GeometryProxy) -> some View {
        let s  = ringSize
        let lw = ringLineWidth

        // When merging, inner/middle rings grow to match outer ring radius
        let outerSize  = s
        let middleSize = ringsMerging ? s : s * 0.735
        let innerSize  = ringsMerging ? s : s * 0.470

        ZStack {
            // Three individual rings — they fade as they converge
            OnboardingRing(progress: ringsMerging ? 1.0 : moveProgress,
                           color: .moveRing, size: outerSize, lineWidth: lw)
                .opacity(ringsMerging ? 0 : 1)
            OnboardingRing(progress: ringsMerging ? 1.0 : exerciseProgress,
                           color: .exerciseRing, size: middleSize, lineWidth: lw)
                .opacity(ringsMerging ? 0 : 1)
            OnboardingRing(progress: ringsMerging ? 1.0 : standProgress,
                           color: .standRing, size: innerSize, lineWidth: lw)
                .opacity(ringsMerging ? 0 : 1)

            // Single merged ring with all three colors in an angular gradient
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: lw)
                Circle()
                    .trim(from: 0, to: 0.9999)
                    .stroke(
                        AngularGradient(
                            colors: [.moveRing, .exerciseRing, .standRing, .moveRing],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: lw, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: outerSize, height: outerSize)
            .opacity(ringsMerging ? 1 : 0)
            .scaleEffect(ringsCollapsed ? 0.01 : (ringsMerging ? 1 : 0.85))

            centerIcon
                .opacity(ringsMerging ? 0 : 1)
        }
        .scaleEffect(ringsCollapsed ? 0.01 : 1)
        .opacity(ringsCollapsed ? 0 : 1)
        .position(x: geo.size.width / 2, y: ringCenterY(geo.size.height))
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: ringsMerging)
        .animation(.easeIn(duration: 0.25), value: ringsCollapsed)
        .animation(.spring(response: 0.6, dampingFraction: 0.78), value: step)
        .animation(.spring(response: 0.6, dampingFraction: 0.78), value: moveProgress)
        .animation(.spring(response: 0.6, dampingFraction: 0.78), value: exerciseProgress)
        .animation(.spring(response: 0.6, dampingFraction: 0.78), value: standProgress)
    }

    @ViewBuilder
    private var centerIcon: some View {
        switch step {
        case .signIn:
            Image(systemName: "trophy.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(LinearGradient(
                    colors: [.moveRing, .exerciseRing],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .opacity(contentVisible ? 1 : 0)
                .scaleEffect(contentVisible ? 1 : 0.4)
                .animation(.spring(response: 0.5, dampingFraction: 0.65).delay(0.05), value: contentVisible)
        case .welcome:
            Image(systemName: "checkmark")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .opacity(checkVisible ? 1 : 0)
                .scaleEffect(checkVisible ? 1 : 0.3)
                .animation(.spring(response: 0.4, dampingFraction: 0.65), value: checkVisible)
        default:
            EmptyView()
        }
    }

    // MARK: - Animations

    private func animateSignInRings() {
        withAnimation(.spring(response: 1.1, dampingFraction: 0.78).delay(0.05))  { moveProgress     = 0.72 }
        withAnimation(.spring(response: 1.1, dampingFraction: 0.78).delay(0.15))  { exerciseProgress = 0.90 }
        withAnimation(.spring(response: 1.1, dampingFraction: 0.78).delay(0.25))  { standProgress    = 0.58 }
        withAnimation(.easeOut(duration: 0.5).delay(0.55))                         { contentVisible   = true  }
    }

    // MARK: - Actions

    private func handleSignIn(name: String) {
        welcomeName = name
        // Health step: rings partially full — they fill further across the next steps.
        withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) {
            moveProgress     = 0.42
            exerciseProgress = 0.50
            standProgress    = 0.34
            step             = .health
        }
    }

    private func requestHealthKit() {
        Task {
            try? await HealthKitManager.shared.requestAuthorization()
            // Start background delivery now that access is granted, so scores can sync
            // without waiting for the next launch.
            HealthKitManager.shared.startBackgroundDelivery()
            let hasWatch = await WatchDetector().detectAppleWatch()
            UserDefaults.standard.set(hasWatch, forKey: "hasAppleWatch")
            if var user = AuthManager.shared.pendingUser {
                user.hasAppleWatch = hasWatch
                AuthManager.shared.pendingUser = user
                try? await CloudKitManager.shared.saveUser(user)
            }
            await MainActor.run {
                let needsName = welcomeName.isEmpty || welcomeName == "Challenger"
                if needsName {
                    // Phase 1: converge rings into single gradient ring
                    ringsMerging = true
                    // Phase 2: collapse merged ring to a point
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        ringsCollapsed = true
                    }
                    // Phase 3: slide in name screen, reset ring state
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) {
                        withAnimation(.easeInOut(duration: 0.4)) { step = .name }
                        var t = Transaction(); t.disablesAnimations = true
                        withTransaction(t) { ringsMerging = false; ringsCollapsed = false }
                    }
                } else {
                    goToNotifications()
                }
            }
        }
    }

    private func handleName(name: String, avatarImage: UIImage?) {
        welcomeName = name
        if var user = AuthManager.shared.pendingUser {
            user.displayName = name
            if let image = avatarImage {
                user.avatarURL = AvatarCache.save(image, userID: user.id)
            }
            AuthManager.shared.pendingUser = user
            UserDefaults.standard.set(name, forKey: "displayName")
            Task {
                let jpegData = avatarImage.flatMap {
                    $0.preparingThumbnail(of: CGSize(width: 400, height: 400))
                      .flatMap { $0.jpegData(compressionQuality: 0.8) }
                }
                try? await CloudKitManager.shared.saveUser(user, avatarData: jpegData)
            }
        }
        goToNotifications()
    }

    /// Advances to the notifications explainer, ensuring the rings read as complete
    /// behind it (the name step may have left them merged/collapsed).
    private func goToNotifications() {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { ringsMerging = false; ringsCollapsed = false }
        // Notifications step: rings fill further than the health step (but not all the
        // way — they complete on the welcome screen).
        withAnimation(.spring(response: 1.0, dampingFraction: 0.8)) {
            moveProgress = 0.72; exerciseProgress = 0.80; standProgress = 0.64
        }
        withAnimation(.easeInOut(duration: 0.4)) { step = .notifications }
    }

    /// Triggers the system notification prompt, then advances to the welcome screen
    /// once the user has responded (allow or deny).
    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                Logger.app.error("Notification authorization error: \(error.localizedDescription, privacy: .public)")
            } else {
                Logger.app.notice("Notification authorization granted: \(granted, privacy: .public)")
            }
            DispatchQueue.main.async {
                startWelcomeRings()
                withAnimation(.easeInOut(duration: 0.45)) { step = .welcome }
            }
        }
    }

    private func startWelcomeRings() {
        // Snap to zero without any animation (suppresses implicit spring on the overlay)
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            moveProgress = 0; exerciseProgress = 0; standProgress = 0; checkVisible = false
        }
        // Fill each ring with a staggered spring — outer first, inner last
        withAnimation(.spring(response: 1.1, dampingFraction: 0.75).delay(0.15)) { moveProgress     = 1.0 }
        withAnimation(.spring(response: 1.1, dampingFraction: 0.75).delay(0.32)) { exerciseProgress = 1.0 }
        withAnimation(.spring(response: 1.1, dampingFraction: 0.75).delay(0.49)) { standProgress    = 1.0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { checkVisible = true }
    }

    private func completeOnboarding() {
        guard var user = AuthManager.shared.pendingUser else { return }
        user.hasAppleWatch = UserDefaults.standard.bool(forKey: "hasAppleWatch")
        session.update(user: user)
    }
}

// MARK: - Shared ring primitive

private struct OnboardingRing: View {
    let progress: CGFloat
    let color: Color
    let size: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(progress, 0.9999))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Screen 1 content (Sign In — no rings)

private struct SignInContent: View {
    let contentVisible: Bool
    let ringBottomY: CGFloat        // absolute Y of ring bottom edge in screen coords
    let onSignedIn: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Reserve space for rings + gap
            Spacer().frame(height: ringBottomY + 28)

            VStack(spacing: 10) {
                Text("Challenges")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
                Text("Close your rings.\nTop the leaderboard.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(white: 0.55))
            }
            .opacity(contentVisible ? 1 : 0)
            .offset(y: contentVisible ? 0 : 20)

            Spacer()

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                handleResult(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 54)
            .cornerRadius(27)
            .padding(.horizontal, 24)
            .padding(.bottom, 52)
            .opacity(contentVisible ? 1 : 0)
            .offset(y: contentVisible ? 0 : 24)
        }
    }

    private func handleResult(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let auth) = result,
              let credential = auth.credential as? ASAuthorizationAppleIDCredential
        else { return }
        Task {
            await AuthManager.shared.handleSignInCompletion(credential: credential)
            let name = AuthManager.shared.pendingUser?.displayName ?? ""
            await MainActor.run { onSignedIn(name) }
        }
    }
}

// MARK: - Screen 2 content (Health — no rings)

private struct HealthContent: View {
    let ringBottomY: CGFloat
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                // Reserve space for rings
                Spacer().frame(height: ringBottomY + 20)

                Text("Activity Access")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .padding(.bottom, 10)

                Text("Challenges reads your Apple Health data to calculate your score. Your data never leaves your device and is never shared with anyone.")
                    .font(.subheadline)
                    .foregroundStyle(Color(white: 0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .padding(.bottom, 28)

                VStack(spacing: 0) {
                    HealthDataRow(icon: "flame.fill",   color: .moveRing,     title: "Active Energy",    detail: "Calories burned while moving")
                    Divider().padding(.horizontal, 16)
                    HealthDataRow(icon: "figure.run",   color: .exerciseRing, title: "Exercise Minutes", detail: "Brisk activity from Apple Watch")
                    Divider().padding(.horizontal, 16)
                    HealthDataRow(icon: "figure.stand", color: .standRing,    title: "Stand Hours",      detail: "Hours you stood at least a minute")
                    Divider().padding(.horizontal, 16)
                    HealthDataRow(icon: "figure.walk",  color: .stepsColor,   title: "Step Count",       detail: "Daily steps for iPhone users")
                }
                .background(Color.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 16)

                Text("You can change these any time in Settings.")
                    .font(.caption2)
                    .foregroundStyle(Color(white: 0.38))
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .padding(.horizontal, 32)

                Spacer()

                Button(action: onContinue) {
                    Text("Allow Activity Access")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(Color.moveRing)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 52)
            }
        }
    }
}

private struct HealthDataRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Screen 2.75 content (Notifications — no rings)

private struct NotificationsContent: View {
    let ringBottomY: CGFloat
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                // Reserve space for rings
                Spacer().frame(height: ringBottomY + 20)

                Text("Stay in the Game")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .padding(.bottom, 10)

                Text("Get a heads-up when a challenge starts, on the final day, and when results are in — plus a daily nudge to close your rings.")
                    .font(.subheadline)
                    .foregroundStyle(Color(white: 0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .padding(.bottom, 28)

                VStack(spacing: 0) {
                    HealthDataRow(icon: "flag.checkered", color: .exerciseRing, title: "Challenge Updates", detail: "Start, final day, and final standings")
                    Divider().padding(.horizontal, 16)
                    HealthDataRow(icon: "bell.badge.fill", color: .moveRing,    title: "Daily Reminders",  detail: "A nudge to keep your streak alive")
                }
                .background(Color.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 16)

                Text("You can change these any time in Settings.")
                    .font(.caption2)
                    .foregroundStyle(Color(white: 0.38))
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .padding(.horizontal, 32)

                Spacer()

                Button(action: onContinue) {
                    Text("Allow Notifications")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(Color.moveRing)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 52)
            }
        }
    }
}

// MARK: - Screen 3 content (Welcome — no rings)

private struct WelcomeContent: View {
    let name: String
    let ringBottomY: CGFloat
    let onComplete: () -> Void

    @State private var textVisible = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: ringBottomY + 36)

            VStack(spacing: 10) {
                Text(name.isEmpty ? "You're in." : "Welcome, \(name).")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                Text("You're ready to compete.")
                    .font(.title3)
                    .foregroundStyle(Color(white: 0.55))
            }
            .opacity(textVisible ? 1 : 0)
            .offset(y: textVisible ? 0 : 16)

            Spacer()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.45).delay(0.3)) { textVisible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { onComplete() }
        }
    }
}

// MARK: - Screen 2.5: Name + Photo

private struct NameEntryScreen: View {
    let initialName: String
    let onContinue: (String, UIImage?) -> Void

    @State private var name = ""
    @State private var avatarImage: UIImage? = nil
    @State private var showPicker = false
    @FocusState private var focused: Bool

    // Entrance animations
    @State private var avatarVisible  = false   // avatar springs up first
    @State private var contentVisible = false   // text + field + button fade in after

    var canContinue: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var initials: String {
        let parts = name.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
        return parts.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Avatar — springs in from scale 0, born from the collapsed ring point
            Button { focused = false; showPicker = true } label: {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let img = avatarImage {
                            Image(uiImage: img).resizable().scaledToFill()
                        } else {
                            ZStack {
                                Color(white: 0.14)
                                if initials.isEmpty {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 40))
                                        .foregroundStyle(Color(white: 0.35))
                                } else {
                                    Text(initials)
                                        .font(.system(size: 38, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                    }
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())

                    ZStack {
                        Circle().fill(Color.moveRing)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 30, height: 30)
                    .opacity(avatarVisible ? 1 : 0)
                    .offset(x: 4, y: 4)
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(avatarVisible ? 1 : 0.01)
            .opacity(avatarVisible ? 1 : 0)
            .sheet(isPresented: $showPicker) {
                CropImagePicker(image: $avatarImage).ignoresSafeArea()
            }
            .padding(.bottom, 28)

            // Text, field and button fade up after the avatar has landed
            VStack(spacing: 8) {
                Text("What's your name?")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                Text("This is how you'll appear\non the leaderboard.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(white: 0.55))
            }
            .padding(.bottom, 32)
            .opacity(contentVisible ? 1 : 0)
            .offset(y: contentVisible ? 0 : 12)

            TextField("Your name", text: $name)
                .font(.system(size: 20, weight: .medium))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($focused)
                .padding(.vertical, 16)
                .background(Color(white: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 32)
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 12)

            Spacer()

            Button {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                onContinue(trimmed, avatarImage)
            } label: {
                Text("Continue")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(canContinue ? Color.moveRing : Color(white: 0.2))
                    .foregroundStyle(canContinue ? .white : Color(white: 0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(!canContinue)
            .padding(.horizontal, 32)
            .padding(.bottom, 52)
            .opacity(contentVisible ? 1 : 0)
            .offset(y: contentVisible ? 0 : 12)
            .animation(.easeInOut(duration: 0.2), value: canContinue)
        }
        .onAppear {
            if !initialName.isEmpty && initialName != "Challenger" { name = initialName }
            // Avatar springs up immediately — synced with ring collapse completion
            withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) {
                avatarVisible = true
            }
            // Text + field + button fade in after avatar has landed
            withAnimation(.easeOut(duration: 0.35).delay(0.22)) {
                contentVisible = true
            }
            // Keyboard after content is visible
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { focused = true }
        }
    }
}

// MARK: - UIImagePickerController wrapper with crop/zoom

private struct CropImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CropImagePicker
        init(_ parent: CropImagePicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
