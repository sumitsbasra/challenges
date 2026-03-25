import SwiftUI

// MARK: - Unified Create / Join Sheet

struct NewChallengeView: View {
    @Environment(UserSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var vm       = NewChallengeViewModel()
    @State private var joinVM   = JoinChallengeViewModel()
    @State private var mode: Mode
    @State private var copied   = false
    @State private var createdChallenge: Challenge? = nil

    /// Called with the newly created challenge so the caller can update local state immediately
    /// without waiting for CloudKit query propagation.
    var onCreated: ((Challenge) -> Void)? = nil

    enum Mode { case create, join }

    private let prefillCode: String

    init(mode: Mode = .create, prefillCode: String = "", onCreated: ((Challenge) -> Void)? = nil) {
        _mode = State(initialValue: mode)
        self.prefillCode = prefillCode
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if let created = createdChallenge {
                    ChallengeCreatedView(challenge: created)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        ))
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            // ── Mode picker ──────────────────────────────
                            Picker("", selection: $mode) {
                                Text("Create").tag(Mode.create)
                                Text("Join").tag(Mode.join)
                            }
                            .pickerStyle(.segmented)
                            .padding(.top, 4)

                            // ── Content ──────────────────────────────────
                            if mode == .create {
                                createContent
                            } else {
                                joinContent
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                    // Prevent the parent HomeView's .refreshable from bleeding into this sheet
                    .refreshable {}
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: createdChallenge == nil)
            .navigationTitle(mode == .create ? "New Challenge" : "Join Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if createdChallenge == nil {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if createdChallenge != nil {
                        Button { dismiss() } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.moveRing)
                        }
                    } else if mode == .create {
                        if vm.isSaving {
                            ProgressView().tint(.moveRing)
                        } else {
                            Button {
                                Task {
                                    guard let user = session.currentUser else { return }
                                    await vm.create(creator: user)
                                    if let created = vm.createdChallenge {
                                        onCreated?(created)
                                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                                        withAnimation { createdChallenge = created }
                                    }
                                }
                            } label: {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(vm.canCreate ? .moveRing : Color.tertiaryText)
                            }
                            .disabled(!vm.canCreate)
                        }
                    } else {
                        if joinVM.isJoining {
                            ProgressView().tint(.moveRing)
                        } else {
                            Button {
                                Task {
                                    guard let userID = session.userID else { return }
                                    await joinVM.joinChallenge(userID: userID, hasWatch: session.currentUser?.hasAppleWatch ?? false)
                                    if joinVM.joined {
                                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                                        dismiss()
                                    }
                                }
                            } label: {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(joinVM.previewChallenge != nil && !joinVM.alreadyJoined ? .moveRing : Color.tertiaryText)
                            }
                            .disabled(joinVM.previewChallenge == nil || joinVM.alreadyJoined)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Create

    @ViewBuilder
    private var createContent: some View {
        // Name
        FitnessFormCard {
            HStack(spacing: 10) {
                Image(systemName: "trophy.fill")
                    .font(.body)
                    .foregroundStyle(.moveRing)
                TextField("Challenge name", text: Bindable(vm).title)
                    .font(.body)
                    .textInputAutocapitalization(.words)
            }
        }

        // Dates
        FitnessFormCard {
            VStack(spacing: 0) {
                DatePicker("Start Date", selection: Bindable(vm).startDate,
                           in: Calendar.current.date(byAdding: .day, value: 1, to: Date())!...,
                           displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .tint(.moveRing)

                Divider().padding(.vertical, 10)

                DatePicker("End Date", selection: Bindable(vm).endDate,
                           in: Calendar.current.date(byAdding: .day, value: 1, to: Bindable(vm).startDate.wrappedValue)!...,
                           displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .tint(.moveRing)

                Divider().padding(.vertical, 10)

                HStack {
                    Text("Duration")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(vm.durationDays) days")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.subheadline)
            }
        }

        // Compact invite code row
        FitnessFormCard {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("INVITE CODE")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.8)
                    Text(vm.inviteCode)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                }

                Spacer()

                Button {
                    UIPasteboard.general.string = vm.inviteCode
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { copied = false }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption.weight(.semibold))
                        Text(copied ? "Copied" : "Copy")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(copied ? .exerciseRing : .moveRing)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background((copied ? Color.exerciseRing : Color.moveRing).opacity(0.14))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }

        if let error = vm.error {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }

    // MARK: - Join

    @ViewBuilder
    private var joinContent: some View {
        // 6-box OTP code input
        InviteCodeInputField(code: Bindable(joinVM).code)
            .frame(maxWidth: .infinity)
            .onAppear {
                joinVM.userID = session.userID
                if !prefillCode.isEmpty { joinVM.code = prefillCode }
            }

        if joinVM.isLooking {
            ProgressView("Finding challenge…")
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        } else if let challenge = joinVM.previewChallenge {
            // Challenge preview
            FitnessFormCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(challenge.title).font(.headline)
                    HStack(spacing: 6) {
                        Image(systemName: "calendar").foregroundStyle(.tertiary)
                        Text("\(challenge.startDate.formatted(.dateTime.month(.abbreviated).day())) – \(challenge.endDate.formatted(.dateTime.month(.abbreviated).day().year()))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if joinVM.alreadyJoined {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.exerciseRing)
                            Text("You're already in this challenge")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        if let error = joinVM.error {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }

}

// MARK: - Challenge Created confirmation screen

private struct ChallengeCreatedView: View {
    let challenge: Challenge

    @State private var checkVisible = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Check mark hero
            ZStack {
                Circle()
                    .fill(Color.exerciseRing.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "checkmark")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(Color.exerciseRing)
                    .scaleEffect(checkVisible ? 1 : 0.3)
                    .opacity(checkVisible ? 1 : 0)
                    .animation(.spring(response: 0.45, dampingFraction: 0.6).delay(0.1), value: checkVisible)
            }
            .padding(.bottom, 28)

            Text("Challenge Created")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.bottom, 8)

            Text("Share the invite code with friends\nso they can join.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.bottom, 36)

            // Invite code card
            FitnessFormCard {
                InviteCodeView(code: challenge.inviteCode)
            }
            .padding(.horizontal, 16)

            Spacer()

            ShareLink(
                item: "Join my Challenges fitness challenge! Code: \(challenge.inviteCode)",
                subject: Text("Join my challenge")
            ) {
                Text("Share Invite Code")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.moveRing)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .onAppear { checkVisible = true }
    }
}

// MARK: - Invite Code Input (6 individual boxes)

private struct InviteCodeInputField: View {
    @Binding var code: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<6, id: \.self) { index in
                let chars = Array(code)
                let char: String = index < chars.count ? String(chars[index]) : ""
                let isCurrent = isFocused && index == min(chars.count, 5)
                let isFilled  = index < chars.count

                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.cardBackground)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    isCurrent ? Color.moveRing : (isFilled ? Color.moveRing.opacity(0.35) : Color.clear),
                                    lineWidth: isCurrent ? 2 : 1.5
                                )
                        }

                    if char.isEmpty && isCurrent {
                        Rectangle()
                            .fill(Color.moveRing)
                            .frame(width: 2, height: 24)
                    } else {
                        Text(char)
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                }
                .frame(width: 46, height: 58)
                .animation(.easeInOut(duration: 0.15), value: isCurrent)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .contextMenu {
            Button {
                if let pasted = UIPasteboard.general.string {
                    code = pasted // JoinChallengeViewModel.didSet handles uppercase + trim to 6
                }
            } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
        }
        .background {
            // Tiny hidden TextField — handles keyboard input only
            TextField("", text: $code)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($isFocused)
                .opacity(0)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
        }
        .onAppear { isFocused = true }
    }
}

