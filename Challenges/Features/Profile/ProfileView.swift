import SwiftUI

struct ProfileView: View {
    @Environment(UserSession.self) private var session
    @State private var vm = ProfileViewModel()
    @State private var showGoals = false
    @State private var showHealthPermissions = false

    var body: some View {
        NavigationStack {
            Form {
                // Profile info
                Section("Profile") {
                    HStack {
                        Text("Name")
                        Spacer()
                        TextField("Display name", text: Bindable(vm).displayName)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(Color.secondaryText)
                    }

                    HStack {
                        Image(systemName: vm.hasAppleWatch ? "applewatch" : "iphone")
                        Text(vm.hasAppleWatch ? "Apple Watch connected" : "iPhone only")
                            .foregroundStyle(Color.secondaryText)
                        Spacer()
                    }
                }

                // Health
                Section("Health") {
                    NavigationLink("Permissions", destination: HealthPermissionsView())
                    if !vm.hasAppleWatch {
                        Button("My Goals") { showGoals = true }
                    }
                }

                // Account
                Section {
                    Button("Save Changes") {
                        Task {
                            guard let user = session.currentUser else { return }
                            await vm.save(user: user)
                        }
                    }
                    .disabled(vm.isSaving)

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
            .sheet(isPresented: $showGoals) {
                GoalsSettingsView()
            }
            .onAppear {
                if let user = session.currentUser {
                    vm.load(user: user)
                }
            }
        }
    }
}
