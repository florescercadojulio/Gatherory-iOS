import SwiftUI

struct AccountView: View {
    @Environment(AuthenticationSession.self) private var authentication
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppAppearance.storageKey) private var appearanceRawValue = AppAppearance.system.rawValue
    @AppStorage("planningNotifications") private var notificationsEnabled = true
    @State private var isEditingProfile = false

    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue) ?? .system
    }

    private var appearanceSelection: Binding<AppAppearance> {
        Binding(
            get: { selectedAppearance },
            set: { appearanceRawValue = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: AppTheme.Spacing.standard) {
                    UserAvatarView(
                        account: authentication.currentUser,
                        size: 64
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(authentication.currentUser?.displayName ?? "Your Account")
                            .font(.headline)
                        Text(authentication.currentUser?.email ?? "Gatherory member")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)

                Button("Edit Profile", systemImage: "pencil") {
                    isEditingProfile = true
                }
                .foregroundStyle(AppTheme.ColorToken.accent)
            }
            .listRowBackground(AppTheme.ColorToken.surface)

            Section("App Settings") {
                Toggle(isOn: $notificationsEnabled) {
                    Label("Planning Notifications", systemImage: "bell.badge")
                }
                .tint(AppTheme.ColorToken.accent)

                Picker(selection: appearanceSelection) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title).tag(option)
                    }
                } label: {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                }
                .pickerStyle(.navigationLink)
            }
            .listRowBackground(AppTheme.ColorToken.surface)

            Section {
                Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    dismiss()
                    authentication.signOut()
                }
            }
            .listRowBackground(AppTheme.ColorToken.surface)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .appSoftScrollEdges()
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .appUserAppearance(selectedAppearance)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $isEditingProfile) {
            NavigationStack {
                EditProfileView(account: authentication.currentUser) { displayName in
                    authentication.updateProfile(displayName: displayName)
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}

private struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String

    let account: UserAccount?
    let onSave: (String) -> Void

    init(account: UserAccount?, onSave: @escaping (String) -> Void) {
        self.account = account
        self.onSave = onSave
        _displayName = State(initialValue: account?.displayName ?? "")
    }

    private var normalizedName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: AppTheme.Spacing.standard) {
                    UserAvatarView(account: account, size: 56)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(account?.email ?? "Gatherory member")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)

                        Text("Your email is managed by your sign-in provider.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(AppTheme.ColorToken.surface)

            Section("Name") {
                TextField("Display name", text: $displayName)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit(save)
            }
            .listRowBackground(AppTheme.ColorToken.surface)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(normalizedName.isEmpty || normalizedName == account?.displayName)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func save() {
        guard !normalizedName.isEmpty else { return }
        onSave(normalizedName)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        AccountView()
            .environment(WeddingWorkspace.sample)
            .environment(
                AuthenticationSession(
                    environment: .development,
                    skipsAuthentication: true
                )
            )
    }
}
