import SwiftUI
import UserNotifications

// MARK: - Profile View

struct ProfileView: View {
    @Environment(UserSession.self) private var session
    @State private var vm = ProfileViewModel()
    @State private var showCropPicker = false

    var body: some View {
        NavigationStack {
            List {
                // ── Avatar ────────────────────────────────────────
                Section {
                    avatarHeader
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                // ── Account ───────────────────────────────────────
                Section("Account") {
                    LabeledContent("Name") {
                        TextField("Display name", text: Bindable(vm).displayName)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }
                }

                // ── Health ────────────────────────────────────────
                Section("Health") {
                    NavigationLink(destination: HealthPermissionsView()) {
                        Label("Permissions", systemImage: "heart.text.clipboard")
                    }

                    NavigationLink(destination: DataSourceView(vm: vm)) {
                        LabeledContent {
                            Text(vm.hasAppleWatch ? "Apple Watch" : "iPhone")
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("Data Source", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    }

                    if !vm.hasAppleWatch {
                        NavigationLink(destination: GoalsSettingsView()) {
                            Label("Goals", systemImage: "target")
                        }
                    }
                }

                // ── Notifications ─────────────────────────────────
                Section("Notifications") {
                    NavigationLink(destination: NotificationSettingsView()) {
                        Label("Notification Preferences", systemImage: "bell.badge")
                    }
                }

                // ── Units ─────────────────────────────────────────
                Section("Units") {
                    Picker(selection: Binding(
                        get: { UserDefaults.standard.string(forKey: "preferredUnits") ?? "Imperial" },
                        set: { UserDefaults.standard.set($0, forKey: "preferredUnits") }
                    )) {
                        Text("Imperial").tag("Imperial")
                        Text("Metric").tag("Metric")
                    } label: {
                        Label("Units", systemImage: "ruler")
                    }
                }

                // ── About ─────────────────────────────────────────
                Section("About") {
                    LabeledContent("Version") {
                        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
                        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
                        Text("\(version) (\(build))")
                            .foregroundStyle(.secondary)
                    }
                }

                // ── App ───────────────────────────────────────────
                Section {
                    Button("Sign Out", role: .destructive) {
                        vm.signOut()
                    }
                }

                if let error = vm.error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            if let user = session.currentUser { vm.load(user: user) }
        }
        // Auto-save name on dismiss — no Save button needed
        .onDisappear {
            Task {
                guard let user = session.currentUser else { return }
                await vm.save(user: user)
            }
        }
    }

    // MARK: - Avatar

    private var avatarHeader: some View {
        Button { showCropPicker = true } label: {
            ZStack(alignment: .bottomTrailing) {
                avatarCircle
                    .frame(width: 110, height: 110)

                Image(systemName: "camera.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color(.systemGray3)))
                    .offset(x: 3, y: 3)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .sheet(isPresented: $showCropPicker) {
            ProfileCropPicker { image in
                vm.saveProfilePhoto(image)
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var avatarCircle: some View {
        if let photo = vm.profilePhoto {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: 110, height: 110)
                .clipShape(Circle())
        } else {
            let initials = vm.displayName
                .split(separator: " ")
                .prefix(2)
                .compactMap { $0.first.map(String.init) }
                .joined()

            ZStack {
                Circle().fill(Color(.systemGray4))
                if initials.isEmpty {
                    Image(systemName: "person.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                } else {
                    Text(initials.uppercased())
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}

// MARK: - Crop Picker (UIImagePickerController with allowsEditing)

import UIKit

private struct ProfileCropPicker: UIViewControllerRepresentable {
    let onPicked: (UIImage) -> Void
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
        let parent: ProfileCropPicker
        init(_ parent: ProfileCropPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = (info[.editedImage] ?? info[.originalImage]) as? UIImage {
                parent.onPicked(img)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Data Source View

struct DataSourceView: View {
    @Bindable var vm: ProfileViewModel

    var body: some View {
        List {
            Section {
                LabeledContent {
                    Text(vm.hasAppleWatch ? "Connected" : "Not connected")
                        .foregroundStyle(vm.hasAppleWatch ? .green : .secondary)
                } label: {
                    Label("Apple Watch", systemImage: "applewatch")
                }
            } footer: {
                Text(vm.hasAppleWatch
                    ? "Activity rings are sourced from your Apple Watch."
                    : "Steps and active energy are sourced from your iPhone.")
            }

            Section {
                Button {
                    Task { await vm.redetectWatch() }
                } label: {
                    Label("Re-detect Apple Watch", systemImage: "arrow.clockwise")
                }
            } footer: {
                Text("Run this if you've recently paired or unpaired an Apple Watch.")
            }
        }
        .navigationTitle("Data Source")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Notification Settings View

private struct NotificationItem: Identifiable {
    let id: String
    let icon: String
    let color: Color
    let title: String
    let description: String
}

struct NotificationSettingsView: View {

    @AppStorage("notif.challengeStarting")  private var challengeStarting = true
    @AppStorage("notif.dailyUpdate")        private var dailyUpdate       = true
    @AppStorage("notif.challengeEnding")    private var challengeEnding   = true
    @AppStorage("notif.finalStandings")     private var finalStandings    = true
    @AppStorage("notif.overtaken")          private var overtaken         = true
    @AppStorage("notif.reactions")          private var reactions         = true
    @AppStorage("notif.joins")              private var joins             = true

    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var showDeniedAlert = false

    private var items: [(NotificationItem, Binding<Bool>)] {[
        (NotificationItem(id: "start",    icon: "flag.fill",        color: .exerciseRing,      title: "Challenge Starting",   description: "The day before your challenge begins"),     $challengeStarting),
        (NotificationItem(id: "daily",    icon: "chart.bar.fill",   color: .standRing,         title: "Daily Update",         description: "Your leaderboard position each morning"),   $dailyUpdate),
        (NotificationItem(id: "ending",   icon: "timer",            color: .stepsColor,        title: "Challenge Ending",     description: "When a challenge ends in 24 hours"),        $challengeEnding),
        (NotificationItem(id: "final",    icon: "trophy.fill",      color: .activeEnergyColor, title: "Final Standings",      description: "Your result when a challenge completes"),   $finalStandings),
        (NotificationItem(id: "overtake", icon: "figure.run",       color: .moveRing,          title: "Overtake Alerts",      description: "When someone passes you on the leaderboard"), $overtaken),
        (NotificationItem(id: "reaction", icon: "hands.clap.fill",  color: .rankGold,          title: "Reactions",            description: "When a friend sends you a reaction"),        $reactions),
        (NotificationItem(id: "join",     icon: "person.badge.plus", color: .standRing,        title: "Challenge Joins",      description: "When someone joins one of your challenges"), $joins),
    ]}

    var body: some View {
        List {
            // Permission warning banner
            if authStatus == .denied {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "bell.slash.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notifications are off")
                                .font(.subheadline.weight(.semibold))
                            Text("Enable them in Settings to receive alerts.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Settings") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                ForEach(items, id: \.0.id) { item, binding in
                    notificationRow(item: item, isOn: binding)
                }
            } footer: {
                Text("Notifications are only sent for challenges you're part of.")
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshStatus() }
        // Reschedule whenever any preference changes so the pending queue stays in sync.
        .onChange(of: challengeStarting) { _, _ in rescheduleFromPrefs() }
        .onChange(of: dailyUpdate)       { _, _ in rescheduleFromPrefs() }
        .onChange(of: challengeEnding)   { _, _ in rescheduleFromPrefs() }
        .onChange(of: finalStandings)    { _, _ in rescheduleFromPrefs() }
        .alert("Notifications Blocked", isPresented: $showDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Go to Settings to allow Challenges to send notifications.")
        }
    }

    private func notificationRow(item: NotificationItem, isOn: Binding<Bool>) -> some View {
        Button {
            handleTap(isOn: isOn)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: item.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(item.color)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(item.color.opacity(0.15)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(item.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isOn.wrappedValue {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func handleTap(isOn: Binding<Bool>) {
        if isOn.wrappedValue {
            // Turning off — always allowed
            isOn.wrappedValue = false
            return
        }
        // Turning on — check permission first
        Task {
            switch authStatus {
            case .notDetermined:
                let granted = (try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
                await refreshStatus()
                if granted { isOn.wrappedValue = true }
            case .authorized, .provisional, .ephemeral:
                isOn.wrappedValue = true
            case .denied:
                showDeniedAlert = true
            @unknown default:
                break
            }
        }
    }

    private func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authStatus = settings.authorizationStatus
    }

    /// Re-runs the scheduler using cached challenges so the pending queue immediately
    /// reflects the user's new toggle state — no CloudKit fetch required.
    private func rescheduleFromPrefs() {
        guard let userID = UserSession.shared.userID,
              let cached = ChallengeCache.load(userID: userID) else { return }
        Task { await NotificationScheduler.reschedule(for: cached.challenges) }
    }
}
