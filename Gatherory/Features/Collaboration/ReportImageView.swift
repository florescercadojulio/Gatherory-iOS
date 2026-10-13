import SwiftUI

struct ReportImageView: View {
    @Environment(ImageSafetyStore.self) private var safety
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ImageReportReason.inappropriate
    @State private var detail = ""
    @State private var isSending = false
    @State private var failure: String?
    let moment: EventMoment

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(AppCopy.Safety.reportExplanation)
                    Picker(AppCopy.Safety.reason, selection: $reason) {
                        ForEach(ImageReportReason.allCases) { value in Text(value.title).tag(value) }
                    }
                    TextField(AppCopy.Safety.detail, text: $detail, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: detail) { _, value in if value.count > 2000 { detail = String(value.prefix(2000)) } }
                }
                if let failure {
                    Section { Text(failure).foregroundStyle(AppTheme.ColorToken.warning) }
                }
                Section {
                    Button {
                        Task { await send() }
                    } label: {
                        HStack { Text(isSending ? AppCopy.Safety.sending : AppCopy.Safety.submit); if isSending { ProgressView() } }
                    }
                    .disabled(isSending || moment.mediaAssetID == nil)
                    Link(AppCopy.Safety.contact, destination: GatheroryLegalDestination.support)
                }
            }
            .navigationTitle(AppCopy.Safety.report)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(AppCopy.Common.cancel) { dismiss() }.disabled(isSending) } }
            .interactiveDismissDisabled(isSending)
        }
        .appUserAppearance(AppAppearance(rawValue: UserDefaults.standard.string(forKey: AppAppearance.storageKey) ?? "system") ?? .system)
    }

    @MainActor private func send() async {
        guard let assetID = moment.mediaAssetID, let baseURL = AppRuntimeConfiguration.authenticationBaseURL else { failure = AppCopy.Safety.failed; return }
        isSending = true; failure = nil
        safety.hide(moment)
        defer { isSending = false }
        do {
            try await ImageSafetyClient(baseURL: baseURL).report(assetID, reason: reason, detail: detail)
            dismiss()
        } catch {
            // Keep the report form and retry available; do not claim submission.
            failure = AppCopy.Safety.failed + " " + error.localizedDescription
        }
    }
}
