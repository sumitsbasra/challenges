import SwiftUI

struct HealthPermissionsView: View {
    @ObservedObject private var hk = HealthKitManager.shared
    @State private var isRequesting = false
    @State private var requestError: String? = nil

    /// Green checkmarks would be a lie when nothing is actually readable.
    private var effectiveStatus: HealthKitManager.AuthorizationStatus {
        hk.dataUnreadable && hk.authorizationStatus == .authorized ? .denied : hk.authorizationStatus
    }

    var body: some View {
        List {
            Section {
                StatusRow(title: "Active Energy", icon: "figure.run",
                          color: .moveRing, status: effectiveStatus)
                StatusRow(title: "Steps", icon: "shoeprints.fill",
                          color: .stepsColor, status: effectiveStatus)
                StatusRow(title: "Exercise Minutes", icon: "timer",
                          color: .exerciseRing, status: effectiveStatus)
                StatusRow(title: "Stand Hours (Watch)", icon: "figure.stand",
                          color: .standRing, status: effectiveStatus)
            } header: {
                Text("Health Data Access")
            } footer: {
                // iOS never reveals whether a READ permission was granted, so "asked"
                // is the most we can claim — and we only say data is flowing when we
                // can actually read some.
                switch hk.authorizationStatus {
                case .authorized where hk.dataUnreadable:
                    Text("No activity data is readable. Open Settings → Privacy & Security → Health → Challenges and turn on Steps, Active Energy, and Exercise Minutes.")
                case .authorized:
                    Text("Activity data is readable and syncing normally.")
                case .partiallyAuthorized:
                    Text("Some permissions are missing. Your competition score may be incomplete.")
                case .denied, .unknown:
                    Text("Tap \"Request Permissions\" to grant access. If the prompt doesn't appear, open Settings → Privacy & Security → Health → Challenges.")
                }
            }

            if hk.authorizationStatus != .authorized || hk.dataUnreadable {
                Section {
                    Button {
                        isRequesting = true
                        requestError = nil
                        Task {
                            do {
                                try await hk.requestAuthorization()
                                // Re-check readability: iOS silently no-ops the request
                                // once the dialog has been shown, so this is what tells
                                // the user whether anything actually changed.
                                await hk.checkDataReadable()
                            } catch {
                                requestError = error.localizedDescription
                            }
                            isRequesting = false
                        }
                    } label: {
                        HStack {
                            Text("Request Permissions")
                            if isRequesting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRequesting)

                    Button("Open Health Settings") {
                        // Deep-links into the Health app; falls back to app Settings.
                        let healthURL = URL(string: "x-apple-health://")
                        let settingsURL = URL(string: UIApplication.openSettingsURLString)
                        if let url = healthURL, UIApplication.shared.canOpenURL(url) {
                            UIApplication.shared.open(url)
                        } else if let url = settingsURL {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
        }
        .navigationTitle("Health Permissions")
        .softTopScrollEdge()
        .onAppear { hk.updateAuthorizationStatus() }
        .task { await hk.checkDataReadable() }
        .alert("Permission Error", isPresented: Binding(
            get: { requestError != nil },
            set: { if !$0 { requestError = nil } }
        )) {
            Button("OK", role: .cancel) { requestError = nil }
        } message: {
            Text(requestError ?? "")
        }
    }
}

private struct StatusRow: View {
    let title: String
    let icon: String
    let color: Color
    let status: HealthKitManager.AuthorizationStatus

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(title)
            Spacer()
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
        }
    }

    private var statusIcon: String {
        switch status {
        case .authorized: return "checkmark.circle.fill"
        case .partiallyAuthorized: return "exclamationmark.circle.fill"
        case .denied, .unknown: return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .authorized: return .exerciseRing
        case .partiallyAuthorized: return .stepsColor
        case .denied, .unknown: return .moveRing
        }
    }
}
