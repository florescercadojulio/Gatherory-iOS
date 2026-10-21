import SwiftUI

struct LocalGuestNameView: View {
    @Environment(AuthenticationSession.self) private var authentication
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var failed = false
    private var valid: Bool {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && value.unicodeScalars.count <= 80
    }

    var body: some View {
        Form {
            Section {
                TextField(GuestCopy.name, text: $name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
            } footer: { Text(GuestCopy.nameHelp) }
            Section { Text(GuestCopy.deviceOnly).foregroundStyle(.secondary) }
        }
        .navigationTitle(GuestCopy.nameTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(AppCopy.Common.cancel) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(AppCopy.Common.continueAction) {
                    do { try authentication.continueAsGuest(displayName: name); dismiss() }
                    catch { failed = true }
                }.disabled(!valid || authentication.isProcessing)
            }
        }
        .alert(GuestCopy.storageFailed, isPresented: $failed) {
            Button(AppCopy.Common.close, role: .cancel) {}
        }
    }
}

struct LocalGuestAccountView: View {
    @Environment(AuthenticationSession.self) private var authentication
    @Environment(NotificationController.self) private var notifications
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsExit = false
    @State private var failed = false

    var body: some View {
        Form {
            Section {
                Label(authentication.localGuestProfile?.displayName ?? GuestCopy.guestAccount,
                      systemImage: "person.crop.circle")
                    .font(.headline)
                Text(GuestCopy.deviceOnly).foregroundStyle(.secondary)
                if let profile = authentication.localGuestProfile {
                    Toggle(isOn: Binding(
                        get: { notifications.isEnabled(for: .guest(id: profile.id)) },
                        set: { enabled in Task { await notifications.setEnabled(enabled, for: .guest(id: profile.id)) } }
                    )) {
                        Label("Event Updates", systemImage: "bell.badge")
                    }
                    .disabled(!notifications.isConfigured)
                    .tint(AppTheme.ColorToken.accent)
                }
                Button(GuestCopy.signInToSave) { dismiss(); authentication.requestGuestSignIn() }
            }
            Section {
                Button(GuestCopy.leave, role: .destructive) { confirmsExit = true }
            }
        }
        .navigationTitle(GuestCopy.guestAccount)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .disabled(authentication.isProcessing)
        .confirmationDialog(GuestCopy.exitTitle, isPresented: $confirmsExit, titleVisibility: .visible) {
            Button(GuestCopy.signInToSave) { dismiss(); authentication.requestGuestSignIn() }
            Button(GuestCopy.remove, role: .destructive) {
                Task {
                    do { try await authentication.discardGuestSession(); dismiss() }
                    catch { failed = true }
                }
            }
            Button(GuestCopy.stay, role: .cancel) {}
        } message: { Text(GuestCopy.exitHelp) }
        .alert(GuestCopy.storageFailed, isPresented: $failed) {
            Button(AppCopy.Common.close, role: .cancel) {}
        }
    }
}

struct LocalGuestSignInGate: View {
    @Environment(AuthenticationSession.self) private var authentication
    var message: String = GuestCopy.shareHelp
    var body: some View {
        ContentUnavailableView {
            Label(GuestCopy.signInRequired, systemImage: "lock")
        } description: { Text(message) } actions: {
            Button(GuestCopy.signInToSave) { authentication.requestGuestSignIn() }
                .buttonStyle(.borderedProminent)
        }
    }
}
