import SwiftUI

struct IdeaApprovalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationSession.self) private var authentication: AuthenticationSession?
    @Environment(PlanningWorkspace.self) private var workspace

    let request: IdeaApprovalRequest
    @State private var showingApprovalError = false

    private var currentRequest: IdeaApprovalRequest? {
        workspace.makeIdeaApprovalRequest(for: request.ideaSnapshot)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(request.ideaSnapshot.title)
                        .font(.headline)
                        .accessibilityIdentifier("idea.approval.title")

                    LabeledContent("Event", value: request.parentEventName)
                        .accessibilityIdentifier("idea.approval.event")

                    if let cost = request.ideaSnapshot.estimatedCost {
                        LabeledContent("Estimated cost") {
                            Text(cost, format: .currency(code: workspace.currencyCode))
                        }
                        .accessibilityIdentifier("idea.approval.cost")
                    }

                    IdeaScheduleTeamInput(
                        summary: workspace.teamResponseSummary(for: request.ideaSnapshot),
                        accessibilityIdentifier: "idea.approval.teamInput"
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.ColorToken.background)
            .navigationTitle("Approve Idea")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("idea.approval.cancel")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Approve") {
                        confirmApproval()
                    }
                    .fontWeight(.semibold)
                    .disabled(currentRequest != request)
                    .accessibilityIdentifier("idea.approval.confirm")
                    .keyboardShortcut(.defaultAction)
                }
            }
            .alert("Couldn’t Approve Idea", isPresented: $showingApprovalError) {
                Button("OK", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text("This idea or its parent event changed. Review the latest details and try again.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            guard currentRequest == request else {
                dismiss()
                return
            }
        }
        .onChange(of: authentication?.principalGeneration) { _, _ in
            dismiss()
        }
        .onChange(of: currentRequest) { _, updatedRequest in
            guard updatedRequest == request else {
                dismiss()
                return
            }
        }
    }

    private func confirmApproval() {
        guard workspace.confirmIdeaApproval(request) else {
            showingApprovalError = true
            return
        }
        AppHaptics.play(.success)
        dismiss()
    }
}
