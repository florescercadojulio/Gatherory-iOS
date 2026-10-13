import SwiftUI

struct AccountView: View {
    @Environment(AuthenticationSession.self) private var authentication
    @Environment(WorkspaceLibrary.self) private var workspaceLibrary
    @Environment(WorkspacePersistenceController.self) private var persistence
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    @Environment(GuestInvitationStore.self) private var guestInvitations
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppAppearance.storageKey) private var appearanceRawValue = AppAppearance.system.rawValue
    @AppStorage(AppColorThemeChoice.storageKey) private var colorThemeRawValue = AppColorThemeChoice.gatheroryBlue.rawValue
    @AppStorage("planningNotifications") private var notificationsEnabled = true
    @State private var isEditingProfile = false
    @State private var isDeletingAccount = false
    @State private var weatherAttribution: EventWeatherAttribution?

    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue) ?? .system
    }

    private var appearanceSelection: Binding<AppAppearance> {
        Binding(
            get: { selectedAppearance },
            set: { appearanceRawValue = $0.rawValue }
        )
    }

    private var selectedColorTheme: AppColorThemeChoice {
        AppColorThemeChoice(rawValue: colorThemeRawValue) ?? .gatheroryBlue
    }

    private var colorThemeSelection: Binding<AppColorThemeChoice> {
        Binding(
            get: { selectedColorTheme },
            set: { colorThemeRawValue = $0.rawValue }
        )
    }

    private var syncStatusTitle: String {
        if cloudSync.isSynchronizing { return "Syncing" }
        if cloudSync.lastError != nil { return "Needs Attention" }
        if cloudSync.lastMediaError != nil || cloudSync.hasPendingMediaUploads { return "Photos Waiting" }
        return cloudSync.lastSuccessfulSyncAt == nil ? "Ready" : "Up to Date"
    }

    private var syncStatusSymbol: String {
        if cloudSync.lastError != nil { return "exclamationmark.triangle.fill" }
        if cloudSync.lastMediaError != nil || cloudSync.hasPendingMediaUploads { return "photo.badge.exclamationmark" }
        return cloudSync.lastSuccessfulSyncAt == nil ? "icloud" : "checkmark.circle.fill"
    }

    private var accountTitle: String {
        guard let account = authentication.currentUser else { return "Your Account" }
        let name = account.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.caseInsensitiveCompare(account.email) != .orderedSame else {
            return "Your Account"
        }
        return name
    }

    private var syncStatusDetail: String {
        guard let error = cloudSync.lastError else {
            return "Changes are saved on this device first and sync when a connection is available."
        }

        if let failure = error as? CloudSyncFailure {
            switch failure {
            case .invalidSession:
                return "Your session expired. Sign in again to resume cloud sync."
            case .payloadTooLarge:
                return "A photo is waiting for a separate upload. Your other changes remain saved on this device."
            case .invalidResponse:
                return "Gatherory received an unexpected response. Try again shortly."
            case .server(let code):
                return "Cloud sync needs attention (\(code)). Your changes remain on this device."
            }
        }

        if let urlError = error as? URLError {
            return "Gatherory could not reach the cloud (\(urlError.code.rawValue)). Your changes remain on this device."
        }

        return "Cloud sync could not finish. Your changes remain on this device."
    }

    private var mediaSyncDetail: String? {
        guard cloudSync.lastMediaError != nil || cloudSync.hasPendingMediaUploads else { return nil }
        guard let error = cloudSync.lastMediaError else {
            return "Your planning changes are synced. Photos are queued to upload."
        }
        if let failure = error as? MediaSyncFailure {
            switch failure {
            case .invalidSession:
                return "Sign in again to finish uploading photos."
            case .imageTooLarge:
                return "One photo is larger than the 20 MB upload limit."
            case .invalidResponse:
                return "A photo is waiting for a valid cloud response."
            case .server(let code):
                return "Your planning changes are synced. A photo is waiting to upload (\(code))."
            }
        }
        return "Your planning changes are synced. A photo is waiting to upload."
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: AppTheme.Spacing.standard) {
                    UserAvatarView(
                        account: authentication.currentUser,
                        size: 58
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(accountTitle)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.ColorToken.textPrimary)
                            .lineLimit(2)

                        Text(authentication.currentUser?.email ?? "Gatherory member")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.ColorToken.textSecondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }

                    Spacer(minLength: AppTheme.Spacing.compact)

                    Button {
                        isEditingProfile = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(AppTheme.ColorToken.elevatedSurface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .accessibilityLabel("Edit profile")
                }
                .padding(.vertical, 8)
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

                Picker(selection: colorThemeSelection) {
                    ForEach(AppColorThemeChoice.allCases) { option in
                        AppColorThemeOptionLabel(option: option)
                            .tag(option)
                    }
                } label: {
                    Label("Color Theme", systemImage: "paintpalette")
                }
                .pickerStyle(.navigationLink)
            }
            .listRowBackground(AppTheme.ColorToken.surface)

            Section {
                LabeledContent {
                    HStack(spacing: AppTheme.Spacing.compact) {
                        if cloudSync.isSynchronizing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: syncStatusSymbol)
                                .foregroundStyle(cloudSync.lastError == nil
                                    && cloudSync.lastMediaError == nil
                                    && !cloudSync.hasPendingMediaUploads
                                    ? AppTheme.ColorToken.accent
                                    : AppTheme.ColorToken.warning)
                        }

                        Text(syncStatusTitle)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ColorToken.textSecondary)
                    }
                } label: {
                    Label("Cloud Sync", systemImage: "arrow.triangle.2.circlepath.icloud")
                }

                Button("Sync Now", systemImage: "arrow.clockwise") {
                    Task { await cloudSync.synchronize(trigger: .manual) }
                }
                .disabled(cloudSync.isSynchronizing || authentication.currentUser == nil)
                .foregroundStyle(AppTheme.ColorToken.accent)
            } header: {
                Text("Cloud Data")
            } footer: {
                Text(cloudSync.lastError != nil ? syncStatusDetail : (mediaSyncDetail ?? syncStatusDetail))
                    .foregroundStyle(
                        cloudSync.lastError == nil
                            && cloudSync.lastMediaError == nil
                            && !cloudSync.hasPendingMediaUploads
                            ? AppTheme.ColorToken.textSecondary
                            : AppTheme.ColorToken.warning
                    )
            }
            .listRowBackground(AppTheme.ColorToken.surface)

            Section("Privacy & Information") {
                AccountExternalLink(
                    title: "How Your Data Is Managed",
                    systemImage: "hand.raised",
                    destination: GatheroryLegalDestination.privacyPolicy
                )

                AccountExternalLink(
                    title: "Terms of Use",
                    systemImage: "doc.text",
                    destination: GatheroryLegalDestination.termsOfUse
                )

                AccountExternalLink(
                    title: "Privacy Questions",
                    systemImage: "envelope",
                    destination: GatheroryLegalDestination.privacyQuestions
                )
            }
            .listRowBackground(AppTheme.ColorToken.surface)

            Section("Account") {
                Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") {
                    dismiss()
                    authentication.signOut()
                }

                Button("Delete Account", systemImage: "trash", role: .destructive) {
                    isDeletingAccount = true
                }
            }
            .listRowBackground(AppTheme.ColorToken.surface)

            Section {
                AccountWeatherAttributionFooter(attribution: weatherAttribution)
                    .listRowBackground(Color.clear)
                    .listRowInsets(
                        EdgeInsets(
                            top: AppTheme.Spacing.standard,
                            leading: AppTheme.Spacing.standard,
                            bottom: AppTheme.Spacing.compact,
                            trailing: AppTheme.Spacing.standard
                        )
                    )
            }
        }
        .formStyle(.grouped)
        .contentMargins(.top, AppTheme.Spacing.compact, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .appSoftScrollEdges()
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .appUserAppearance(selectedAppearance)
        .appColorTheme(selectedColorTheme)
        .task {
            weatherAttribution = try? await WeatherKitEventWeatherProvider().attribution()
        }
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
        .sheet(isPresented: $isDeletingAccount) {
            DeleteAccountView(
                isProcessing: authentication.isProcessing
            ) {
                let deletedUserID = authentication.currentUser?.id
                try await authentication.deleteAccount()
                if let deletedUserID { try guestInvitations.purgeCache(accountID: deletedUserID) }
                try persistence.purgeAllLocalData(from: workspaceLibrary)
                dismiss()
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(authentication.isProcessing)
        }
    }
}

enum GatheroryLegalDestination {
    static let privacyPolicy = URL(string: "https://gatherory.com/privacy")!
    static let termsOfUse = URL(string: "https://gatherory.com/terms")!
    static let privacyQuestions = URL(string: "mailto:privacy@gatherory.com")!
}

private struct AccountExternalLink: View {
    let title: String
    let systemImage: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityHint(destination.isFileURL ? "Opens a document" : "Opens outside Gatherory")
    }
}

private struct AccountWeatherAttributionFooter: View {
    @Environment(\.colorScheme) private var colorScheme

    let attribution: EventWeatherAttribution?

    var body: some View {
        Group {
            if let attribution {
                Link(destination: attribution.legalPageURL) {
                    HStack(spacing: 4) {
                        Text("Weather data provided by")
                        weatherMark(for: attribution)
                        Text("Learn More")
                            .foregroundStyle(AppTheme.ColorToken.accent)
                    }
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Weather data attribution")
                .accessibilityHint("Opens Apple Weather data sources")
            } else {
                Text("Weather data provided by Apple Weather")
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(AppTheme.ColorToken.textSecondary)
    }

    @ViewBuilder
    private func weatherMark(for attribution: EventWeatherAttribution) -> some View {
        AsyncImage(
            url: colorScheme == .light
                ? attribution.combinedMarkLightURL
                : attribution.combinedMarkDarkURL
        ) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFit()
            } else {
                Text(attribution.serviceName)
                    .font(.caption2)
            }
        }
        .frame(width: 92, height: 22, alignment: .leading)
        .accessibilityHidden(true)
    }
}

private struct DeleteAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var confirmation = ""
    @State private var errorMessage: String?

    let isProcessing: Bool
    let onDelete: () async throws -> Void

    private var isConfirmed: Bool {
        confirmation.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "DELETE"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                        Label("This is permanent", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.red)

                        Text("Deleting your account removes your Gatherory identity, private events you solely own, participation, decisions, and uploaded photos. Shared events remain available to their other members.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(AppTheme.ColorToken.surface)

                Section {
                    TextField("Type DELETE", text: $confirmation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()

                    Button("Delete Account", systemImage: "trash", role: .destructive) {
                        Task { await deleteAccount() }
                    }
                    .disabled(!isConfirmed || isProcessing)
                } header: {
                    Text("Type DELETE to confirm")
                } footer: {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    } else {
                        Text("You may be asked to sign in again if your current session is no longer recent.")
                    }
                }
                .listRowBackground(AppTheme.ColorToken.surface)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.ColorToken.background)
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isProcessing)
                }
            }
        }
    }

    @MainActor
    private func deleteAccount() async {
        guard isConfirmed, !isProcessing else { return }
        errorMessage = nil

        do {
            try await onDelete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AppColorThemeOptionLabel: View {
    let option: AppColorThemeChoice

    var body: some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            HStack(spacing: -4) {
                ForEach(Array(option.previewColors.enumerated()), id: \.offset) { _, color in
                    Circle()
                        .fill(color)
                        .frame(width: 18, height: 18)
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.8), lineWidth: 1)
                        }
                }
            }
            .accessibilityHidden(true)

            Text(option.accountSettingsTitle)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(option.title)
    }
}

private extension AppColorThemeChoice {
    var accountSettingsTitle: String {
        switch self {
        case .gatheroryBlue: "Blue"
        case .orchid: "Orchid"
        case .sage: "Sage"
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
    let persistence = try! WorkspacePersistenceController(isStoredInMemoryOnly: true)
    let library = WorkspaceLibrary.sample

    return NavigationStack {
        AccountView()
            .environment(PlanningWorkspace.sample)
            .environment(library)
            .environment(persistence)
            .environment(
                WorkspaceCloudSyncController(
                    persistence: persistence,
                    library: library,
                    baseURL: nil
                )
            )
            .environment(
                AuthenticationSession(
                    environment: .development,
                    skipsAuthentication: true
                )
            )
    }
}
