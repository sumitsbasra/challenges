import SwiftUI

struct HealthPermissionsView: View {
    @ObservedObject private var hk = HealthKitManager.shared

    var body: some View {
        List {
            Section {
                StatusRow(title: "Active Energy", icon: "figure.run",
                          color: .moveRing, status: hk.authorizationStatus)
                StatusRow(title: "Steps", icon: "shoeprints.fill",
                          color: .stepsColor, status: hk.authorizationStatus)
                StatusRow(title: "Exercise Minutes", icon: "timer",
                          color: .exerciseRing, status: hk.authorizationStatus)
                StatusRow(title: "Stand Hours (Watch)", icon: "figure.stand",
                          color: .standRing, status: hk.authorizationStatus)
            } header: {
                Text("Health Data Access")
            } footer: {
                switch hk.authorizationStatus {
                case .authorized:
                    Text("All permissions granted. Your data is syncing normally.")
                case .partiallyAuthorized:
                    Text("Some permissions are missing. Your competition score may be incomplete.")
                case .denied, .unknown:
                    Text("Health access is denied. Open Settings to grant permissions.")
                }
            }

            if hk.authorizationStatus != .authorized {
                Section {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
        }
        .navigationTitle("Health Permissions")
        .onAppear { hk.updateAuthorizationStatus() }
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
