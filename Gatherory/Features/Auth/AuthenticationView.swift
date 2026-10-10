import AuthenticationServices
import SwiftUI

struct AuthenticationView: View {
    @Environment(AuthenticationSession.self) private var authentication
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var mode = AuthenticationMode.signIn
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    var body: some View {
        ZStack {
            authenticationBackground

            VStack(spacing: 0) {
                authenticationPanel

                Spacer(minLength: 0)
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, AppTheme.Spacing.standard)
            .padding(.top, AppTheme.Spacing.compact)
            .frame(maxWidth: .infinity)

            if let errorMessage {
                authenticationError(errorMessage)
                    .frame(maxWidth: 520)
                    .padding(.horizontal, AppTheme.Spacing.standard)
                    .padding(.bottom, AppTheme.Spacing.spacious)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
                    .allowsHitTesting(false)
            }
        }
        .tint(AppTheme.ColorToken.accent)
        .animation(reduceMotion ? nil : .snappy, value: errorMessage)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button("Done") {
                    focusedField = nil
                }
            }
        }
        .onChange(of: mode) {
            errorMessage = nil
            password = ""
            focusedField = nil
        }
    }

    private var authenticationPanel: some View {
        VStack(spacing: focusedField == nil ? AppTheme.Spacing.standard : 10) {
            credentialsForm

            if focusedField == nil {
                providerDivider
                providerActions
                modeSwitcher
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: focusedField)
    }

    private var providerDivider: some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            Divider()

            Text("or")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Divider()
        }
        .frame(height: 20)
    }

    private var providerActions: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(
                mode.appleButtonLabel,
                onRequest: { request in
                    request.requestedScopes = mode == .createAccount ? [.fullName, .email] : [.email]
                },
                onCompletion: handleAppleAuthorization
            )
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))

            Button {
                authenticate(using: .google)
            } label: {
                HStack(spacing: 10) {
                    Text("G")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.ColorToken.accent)
                        .frame(width: 24, height: 24)

                    Text("Continue with Google")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(
                    AppTheme.ColorToken.background,
                    in: RoundedRectangle(
                        cornerRadius: AppTheme.Radius.control,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: AppTheme.Radius.control,
                        style: .continuous
                    )
                    .stroke(AppTheme.ColorToken.cardBorder, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var credentialsForm: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            if mode == .createAccount {
                authenticationField(focused: .displayName) {
                    TextField("Name", text: $displayName)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .displayName)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .email }
                        .accessibilityLabel("Name")
                }
            }

            authenticationField(focused: .email) {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .accessibilityLabel("Email")
            }

            authenticationField(focused: .password) {
                SecureField("Password", text: $password)
                    .textContentType(mode == .signIn ? .password : .newPassword)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(performPasswordAction)
                    .accessibilityLabel("Password")
            }

            Button(action: performPasswordAction) {
                Text(mode.primaryActionTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSubmitCredentials)
        }
    }

    private func authenticationError(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.compact) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)

            Text(message)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
        .padding(AppTheme.Spacing.standard)
        .background(
            AppTheme.ColorToken.surface,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                .stroke(Color.red.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
    }

    private func authenticationField<Content: View>(
        focused field: Field,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .textFieldStyle(.plain)
            .padding(.horizontal, AppTheme.Spacing.standard)
            .frame(minHeight: 54)
            .background(
                AppTheme.ColorToken.elevatedSurface,
                in: RoundedRectangle(
                    cornerRadius: AppTheme.Radius.control,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: AppTheme.Radius.control,
                    style: .continuous
                )
                .stroke(
                    focusedField == field
                        ? AppTheme.ColorToken.accent
                        : AppTheme.ColorToken.cardBorder,
                    lineWidth: focusedField == field ? 2 : 0.5
                )
            }
            .animation(.easeOut(duration: 0.16), value: focusedField)
    }

    private var modeSwitcher: some View {
        HStack(spacing: 4) {
            Text(mode.alternativePrompt)
                .foregroundStyle(.secondary)

            Button(mode.alternativeActionTitle) {
                mode = mode.alternative
            }
            .fontWeight(.semibold)
        }
        .font(.subheadline)
    }

    private var authenticationBackground: some View {
        ZStack {
            AppTheme.ColorToken.background

            Image("GatheroryLaunchMark")
                .resizable()
                .scaledToFit()
                .frame(width: 184, height: 184)
                .blur(radius: 18)
                .accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }

    private var canSubmitCredentials: Bool {
        let hasCredentials = email.contains("@") && !password.isEmpty
        return mode == .signIn
            ? hasCredentials
            : hasCredentials && !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func performPasswordAction() {
        errorMessage = nil

        do {
            switch mode {
            case .signIn:
                try authentication.signIn(email: email, password: password)
            case .createAccount:
                try authentication.register(
                    displayName: displayName,
                    email: email,
                    password: password
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func authenticate(using provider: AuthenticationProvider) {
        errorMessage = nil

        do {
            try authentication.signIn(using: provider)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleAppleAuthorization(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .success:
            authenticate(using: .apple)
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private enum AuthenticationMode {
    case signIn
    case createAccount

    var primaryActionTitle: String {
        switch self {
        case .signIn: "Sign In"
        case .createAccount: "Create Account"
        }
    }

    var alternativePrompt: String {
        switch self {
        case .signIn: "New to Gatherory?"
        case .createAccount: "Already have an account?"
        }
    }

    var alternativeActionTitle: String {
        switch self {
        case .signIn: "Create Account"
        case .createAccount: "Sign In"
        }
    }

    var alternative: AuthenticationMode {
        switch self {
        case .signIn: .createAccount
        case .createAccount: .signIn
        }
    }

    var appleButtonLabel: SignInWithAppleButton.Label {
        switch self {
        case .signIn: .signIn
        case .createAccount: .signUp
        }
    }
}

private enum Field {
    case displayName
    case email
    case password
}

#Preview("Authentication") {
    AuthenticationView()
        .environment(
            AuthenticationSession(
                environment: .development,
                skipsAuthentication: false
            )
        )
}
