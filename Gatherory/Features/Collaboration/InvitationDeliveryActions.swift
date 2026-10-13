import MessageUI
import SwiftUI

/// Captures the invitation at the time Messages is opened. Editing the role
/// or changing event context later cannot retarget a message already drafted.
struct InvitationMessageDraft: Identifiable {
    let id = UUID()
    let eventTitle: String
    let invitationURL: URL

    var body: String {
        String(localized: "Join \(eventTitle)") + "\n" + invitationURL.absoluteString
    }
}

/// Delivery uses system-owned recipient selection. Gatherory never reads the
/// contact store and does not need a Contacts permission or a contact primer.
struct InvitationDeliveryActions: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var messageDraft: InvitationMessageDraft?
    @State private var messageError: String?

    let eventTitle: String
    let invitationURL: URL
    var previewImage: Image = Image(systemName: "envelope")

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))

        VStack(alignment: .leading, spacing: 8) {
            layout {
                if MFMessageComposeViewController.canSendText() {
                    Button {
                        messageError = nil
                        messageDraft = InvitationMessageDraft(
                            eventTitle: eventTitle,
                            invitationURL: invitationURL
                        )
                    } label: {
                        Label("Messages", systemImage: "message")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Choose recipients and send using the system message composer")
                }

                ShareLink(
                    item: invitationURL,
                    subject: Text("Join \(eventTitle)"),
                    preview: SharePreview(eventTitle, image: previewImage)
                ) {
                    Label("AirDrop & More", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Opens sharing options including AirDrop")
            }

            Text("Share using AirDrop, Messages, or another app. You choose who receives the invitation.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let messageError {
                Label {
                    Text(messageError)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.footnote)
                .foregroundStyle(AppTheme.ColorToken.warning)
            }
        }
        .sheet(item: $messageDraft) { draft in
            InvitationMessageComposer(draft: draft) { result in
                messageDraft = nil
                if result == .failed {
                    messageError = String(localized: "The message could not be sent. Try again or use AirDrop & More.")
                }
            }
            .ignoresSafeArea()
        }
    }
}

private struct InvitationMessageComposer: UIViewControllerRepresentable {
    let draft: InvitationMessageDraft
    let onCompletion: (MessageComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.body = draft.body
        // No preselected recipients: the system composer owns contact lookup
        // and the user explicitly chooses recipients and taps Send or Cancel.
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onCompletion: (MessageComposeResult) -> Void

        init(onCompletion: @escaping (MessageComposeResult) -> Void) {
            self.onCompletion = onCompletion
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            onCompletion(result)
        }
    }
}
