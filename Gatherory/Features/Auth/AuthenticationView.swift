import AuthenticationServices
import CryptoKit
import GoogleSignIn
import Security
import SwiftUI
import UIKit

struct AuthenticationView: View {
    @Environment(AuthenticationSession.self) private var authentication
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var mode = AuthenticationMode.signIn
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var currentAppleNonce: String?
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

            if let message = errorMessage ?? authentication.registrationNotice {
                authenticationMessage(message, isError: errorMessage != nil)
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
        .onChange(of: focusedField) { _, field in
            if field != nil, mode == .signIn {
                authentication.clearRegistrationNotice()
            }
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
                    let nonce = Self.randomNonce()
                    currentAppleNonce = nonce
                    request.nonce = Self.sha256(nonce)
                    request.requestedScopes = mode == .createAccount ? [.fullName, .email] : [.email]
                },
                onCompletion: handleAppleAuthorization
            )
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
            .disabled(authentication.isProcessing)

            Button {
                authenticateWithGoogle()
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
            .disabled(authentication.isProcessing)
        }
    }

    private var credentialsForm: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            if mode == .createAccount {
                authenticationField(focused: .displayName) {
                    TextField(
                        "",
                        text: $displayName,
                        prompt: authenticationPrompt("Name")
                    )
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .displayName)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .email }
                        .accessibilityLabel("Name")
                }
            }

            authenticationField(focused: .email) {
                TextField(
                    "",
                    text: $email,
                    prompt: authenticationPrompt("Email")
                )
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
                SecureField(
                    "",
                    text: $password,
                    prompt: authenticationPrompt("Password")
                )
                    .textContentType(mode.passwordContentType)
                    .id(mode.passwordFieldID)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(performPasswordAction)
                    .accessibilityLabel("Password")
            }

            Button(action: performPasswordAction) {
                // Keep the localized title in layout, including at larger text
                // sizes. The spinner must not replace the button's size anchor.
                Text(mode.primaryActionTitle)
                    .font(.headline)
                    .opacity(authentication.isProcessing ? 0 : 1)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .overlay {
                        if authentication.isProcessing {
                            ProgressView()
                                .accessibilityHidden(true)
                        }
                    }
            }
            .accessibilityLabel(mode.primaryActionTitle)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSubmitCredentials || authentication.isProcessing)
        }
    }

    private func authenticationMessage(_ message: String, isError: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.compact) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "envelope.badge.fill")
                .foregroundStyle(isError ? AppTheme.ColorToken.destructive : AppTheme.ColorToken.accent)

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
                .stroke(
                    (isError ? AppTheme.ColorToken.destructive : AppTheme.ColorToken.accent).opacity(0.35),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
    }

    private func authenticationField<Content: View>(
        focused field: Field,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: AppTheme.Radius.control,
            style: .continuous
        )

        return content()
            .textFieldStyle(.plain)
            .foregroundStyle(AppTheme.ColorToken.textPrimary)
            .padding(.horizontal, AppTheme.Spacing.standard)
            .frame(minHeight: 56)
            .background(authenticationFieldSurface, in: shape)
            .contentShape(shape)
            .onTapGesture {
                focusedField = field
            }
            .animation(.easeOut(duration: 0.16), value: focusedField)
    }

    private func authenticationPrompt(_ title: String) -> Text {
        Text(title)
            .foregroundStyle(Color(uiColor: .secondaryLabel))
    }

    private var authenticationFieldSurface: Color {
        if colorScheme == .light {
            return Color(uiColor: colorSchemeContrast == .increased ? .systemGray5 : .systemGray6)
        }
        return Color(uiColor: .secondarySystemBackground)
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

        Task {
            do {
                switch mode {
                case .signIn:
                    try await authentication.signIn(email: email, password: password)
                case .createAccount:
                    try await authentication.register(
                        displayName: displayName,
                        email: email,
                        password: password
                    )
                    if authentication.registrationNotice != nil {
                        mode = .signIn
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func authenticateWithGoogle() {
        errorMessage = nil

        guard let presenter = Self.presentingViewController else {
            errorMessage = AuthenticationFailure.providerUnavailable.localizedDescription
            return
        }

        let nonce = Self.randomNonce()
        GIDSignIn.sharedInstance.signIn(
            withPresenting: presenter,
            hint: nil,
            additionalScopes: nil,
            nonce: nonce
        ) { result, error in
            Task { @MainActor in
                guard let result else {
                    if let error, (error as NSError).code != -5 {
                        errorMessage = error.localizedDescription
                    }
                    return
                }

                guard let identityToken = result.user.idToken?.tokenString else {
                    errorMessage = AuthenticationFailure.invalidServerResponse.localizedDescription
                    return
                }

                do {
                    try await authentication.signInWithGoogle(
                        identityToken: identityToken,
                        nonce: nonce,
                        requestingSignUp: mode == .createAccount
                    )
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func handleAppleAuthorization(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let identityToken = String(data: tokenData, encoding: .utf8),
                let codeData = credential.authorizationCode,
                let authorizationCode = String(data: codeData, encoding: .utf8),
                let nonce = currentAppleNonce
            else {
                errorMessage = AuthenticationFailure.invalidServerResponse.localizedDescription
                return
            }

            let identity = AppleIdentity(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                nonce: nonce,
                email: credential.email,
                givenName: credential.fullName?.givenName,
                familyName: credential.fullName?.familyName
            )
            currentAppleNonce = nil
            errorMessage = nil

            Task {
                do {
                    try await authentication.signInWithApple(
                        identity,
                        requestingSignUp: mode == .createAccount
                    )
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        case .failure(let error):
            currentAppleNonce = nil
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        result.reserveCapacity(length)

        while result.count < length {
            var random: UInt8 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &random) == errSecSuccess else {
                return UUID().uuidString
            }
            if Int(random) < characters.count {
                result.append(characters[Int(random)])
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static var presentingViewController: UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)

        var presenter = window?.rootViewController
        while let presented = presenter?.presentedViewController {
            presenter = presented
        }
        return presenter
    }
}

private enum AuthenticationMode: Hashable {
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

    var passwordContentType: UITextContentType {
        switch self {
        case .signIn: .password
        case .createAccount: .newPassword
        }
    }

    var passwordFieldID: String {
        switch self {
        case .signIn: "existing-password"
        case .createAccount: "new-password"
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
