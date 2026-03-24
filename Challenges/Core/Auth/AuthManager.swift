import Foundation
import AuthenticationServices
import CloudKit
import Security

/// Manages Sign in with Apple and maps the Apple user identity to a CloudKit record ID.
@MainActor
final class AuthManager: NSObject, ObservableObject, ASAuthorizationControllerDelegate {

    static let shared = AuthManager()

    @Published var isSignedIn: Bool = false
    @Published var currentUserID: String? = nil  // CloudKit recordName

    /// Populated after a successful sign-in, before HealthKit permissions are granted.
    /// OnboardingView reads this to complete the session once permissions are known.
    var pendingUser: AppUser?

    // Keychain key for the stable Apple user identifier.
    private static let appleUserIDKeychainKey = "com.challenges.appleUserID"

    override private init() {
        super.init()
        checkExistingCredential()
    }

    // MARK: - Check existing credential on launch

    private func checkExistingCredential() {
        guard let storedAppleUserID = keychainLoad(key: Self.appleUserIDKeychainKey) else {
            return
        }
        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: storedAppleUserID) { [weak self] state, _ in
            Task { @MainActor in
                if state == .authorized {
                    self?.currentUserID = UserDefaults.standard.string(forKey: "cloudKitUserRecordName")
                    self?.isSignedIn = self?.currentUserID != nil
                } else {
                    self?.signOut()
                }
            }
        }
    }

    // MARK: - Sign In with Apple

    func signIn() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.performRequests()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            return
        }
        Task {
            await handleSignIn(credential: credential)
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        // User cancelled or error — remain signed out.
        #if DEBUG
        print("[AuthManager] Sign in failed: \(error.localizedDescription)")
        #endif
    }

    // MARK: - Handle successful credential

    /// Called by OnboardingView after a successful SignInWithAppleButton completion.
    /// Performs CloudKit linkage and stores a `pendingUser` but does NOT update
    /// `UserSession` — that happens in OnboardingView after HealthKit permissions are granted.
    func handleSignInCompletion(credential: ASAuthorizationAppleIDCredential) async {
        await handleSignIn(credential: credential)
    }

    private func handleSignIn(credential: ASAuthorizationAppleIDCredential) async {
        let appleUserID = credential.user
        keychainSave(key: Self.appleUserIDKeychainKey, value: appleUserID)

        // Apple only provides fullName on the very first sign-in ever.
        // Subsequent sign-ins (new device, reinstall) have nil fullName.
        var resolvedName: String? = nil
        if let fullName = credential.fullName, let given = fullName.givenName {
            let family = fullName.familyName ?? ""
            resolvedName = "\(given) \(family)".trimmingCharacters(in: .whitespaces)
        }

        // Final fallback chain: credential → CloudKit → UserDefaults cache → generic
        // Declared before the do/catch so the catch block can reference it.
        var displayName = resolvedName
            ?? UserDefaults.standard.string(forKey: "displayName")
            ?? "Challenger"

        do {
            // Fetch CloudKit user record ID (tied to iCloud account).
            let ckUserRecordID = try await CKContainer(identifier: "iCloud.studio.ssb.challenges")
                .userRecordID()
            let ckRecordName = ckUserRecordID.recordName
            UserDefaults.standard.set(ckRecordName, forKey: "cloudKitUserRecordName")
            currentUserID = ckRecordName
            isSignedIn = true

            // If Apple didn't give us a name, try to recover it from CloudKit
            // (covers reinstalls and new devices where the credential has no fullName).
            if resolvedName == nil {
                if let existing = try? await CloudKitManager.shared.fetchUser(recordName: ckRecordName) {
                    resolvedName = existing.displayName
                    displayName = resolvedName ?? displayName
                }
            }
            UserDefaults.standard.set(displayName, forKey: "displayName")
            // Build a pending user immediately so OnboardingView can complete the session
            // even if the CloudKit save below fails (schema not yet deployed, etc.).
            let user = AppUser(
                id: ckRecordName,
                displayName: displayName,
                appleUserID: appleUserID,
                hasAppleWatch: false
            )
            pendingUser = user

            // Upsert User record in CloudKit Public Database.
            // hasAppleWatch is unknown until HealthKit permissions are granted;
            // OnboardingView will update it and re-save after requesting permissions.
            try await CloudKitManager.shared.saveUser(user)

        } catch {
            #if DEBUG
            print("[AuthManager] CloudKit linkage failed: \(error.localizedDescription)")
            #endif
            // pendingUser may be nil here if CKContainer.userRecordID() itself failed
            // (e.g. no iCloud account). Fall back to a local-only user so onboarding
            // can still proceed and HealthKit permissions can still be requested.
            if pendingUser == nil {
                let fallbackID = UUID().uuidString
                pendingUser = AppUser(
                    id: fallbackID,
                    displayName: displayName,
                    appleUserID: appleUserID,
                    hasAppleWatch: false
                )
            }
            isSignedIn = pendingUser != nil
        }
    }

    // MARK: - Sign Out

    func signOut() {
        keychainDelete(key: Self.appleUserIDKeychainKey)
        UserDefaults.standard.removeObject(forKey: "cloudKitUserRecordName")
        currentUserID = nil
        isSignedIn = false
    }

    // MARK: - Keychain helpers

    private func keychainSave(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: data,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func keychainLoad(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainDelete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
