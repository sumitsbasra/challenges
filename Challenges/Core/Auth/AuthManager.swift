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
        print("[AuthManager] Sign in failed: \(error.localizedDescription)")
    }

    // MARK: - Handle successful credential

    private func handleSignIn(credential: ASAuthorizationAppleIDCredential) async {
        let appleUserID = credential.user
        keychainSave(key: Self.appleUserIDKeychainKey, value: appleUserID)

        do {
            // Fetch CloudKit user record ID (tied to iCloud account).
            let ckUserRecordID = try await CKContainer(identifier: "iCloud.com.yourname.challenges")
                .userRecordID()
            let ckRecordName = ckUserRecordID.recordName
            UserDefaults.standard.set(ckRecordName, forKey: "cloudKitUserRecordName")
            currentUserID = ckRecordName
            isSignedIn = true

            // Build display name from credential (only available on first sign-in).
            let displayName: String
            if let fullName = credential.fullName,
               let given = fullName.givenName {
                let family = fullName.familyName ?? ""
                displayName = "\(given) \(family)".trimmingCharacters(in: .whitespaces)
            } else {
                displayName = UserDefaults.standard.string(forKey: "displayName") ?? "Challenger"
            }
            UserDefaults.standard.set(displayName, forKey: "displayName")

            // Upsert User record in CloudKit Public Database.
            let hasWatch = UserDefaults.standard.bool(forKey: "hasAppleWatch")
            let user = AppUser(
                id: ckRecordName,
                displayName: displayName,
                appleUserID: appleUserID,
                hasAppleWatch: hasWatch
            )
            try await CloudKitManager.shared.saveUser(user)

        } catch {
            print("[AuthManager] CloudKit linkage failed: \(error.localizedDescription)")
            isSignedIn = false
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
