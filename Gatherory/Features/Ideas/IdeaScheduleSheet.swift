import SwiftUI

struct IdeaScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationSession.self) private var authentication: AuthenticationSession?
    @Environment(PlanningWorkspace.self) private var workspace

    let request: EventIdeaScheduleRequest
    let initialConfiguration: EventIdeaConfiguration

    @State private var startsAt: Date
    @State private var endsAt: Date?
    @State private var isAllDay: Bool
    @State private var timeZoneIdentifier: String
    @State private var location: EventLocation?
    @State private var isEditingDateAndTime = false
    @State private var isEditingLocation = false
    @State private var showingScheduleError = false

    init(
        request: EventIdeaScheduleRequest,
        initialConfiguration: EventIdeaConfiguration
    ) {
        self.request = request
        self.initialConfiguration = initialConfiguration
        _startsAt = State(initialValue: initialConfiguration.proposedDate ?? .now)
        _endsAt = State(initialValue: initialConfiguration.proposedEndDate)
        _isAllDay = State(initialValue: initialConfiguration.isAllDay)
        _timeZoneIdentifier = State(initialValue: initialConfiguration.timeZoneIdentifier)
        _location = State(initialValue: initialConfiguration.location)
    }

    private var ideaTitle: String {
        request.ideaSnapshot.title
    }

    private var scheduleSummary: String {
        EventSchedule(
            startsAt: startsAt,
            endsAt: endsAt,
            isAllDay: isAllDay,
            timeZoneIdentifier: timeZoneIdentifier
        ).summary
    }

    private var currentScheduleRequest: EventIdeaScheduleRequest? {
        workspace.makeScheduleRequest(for: request.ideaSnapshot)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(ideaTitle)
                        .font(.headline)
                        .accessibilityIdentifier("idea.schedule.title")

                    IdeaScheduleTeamInput(summary: workspace.teamResponseSummary(for: request.ideaSnapshot))

                    Button {
                        isEditingDateAndTime = true
                    } label: {
                        Label(scheduleSummary, systemImage: "calendar")
                            .frame(minHeight: AppTheme.Layout.minimumTouchTarget, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Date and time, \(scheduleSummary)")
                    .accessibilityIdentifier("idea.schedule.date")

                    Button {
                        isEditingLocation = true
                    } label: {
                        Label(location?.title ?? "Add Location", systemImage: "mappin.and.ellipse")
                            .frame(minHeight: AppTheme.Layout.minimumTouchTarget, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("idea.schedule.location")

                    if location != nil {
                        Button("Remove Location", systemImage: "mappin.slash", role: .destructive) {
                            location = nil
                        }
                        .accessibilityIdentifier("idea.schedule.removeLocation")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.ColorToken.background)
            .navigationTitle("Schedule Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("idea.schedule.cancel")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(IdeaScheduleCopy.action) {
                        confirmSchedule()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("idea.schedule.confirm")
                    .keyboardShortcut(.defaultAction)
                }
            }
            .alert("Couldn’t Schedule Event", isPresented: $showingScheduleError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(scheduleErrorMessage)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $isEditingDateAndTime) {
            EventDateTimeEditorView(
                startsAt: startsAt,
                endsAt: endsAt,
                isAllDay: isAllDay,
                timeZoneIdentifier: timeZoneIdentifier,
                accessibilityIdentifierPrefix: "idea.schedule.dateTime"
            ) { updatedStart, updatedEnd, updatedAllDay, updatedTimeZone in
                startsAt = updatedStart
                endsAt = updatedEnd
                isAllDay = updatedAllDay
                timeZoneIdentifier = updatedTimeZone
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isEditingLocation) {
            EventLocationEditorView(
                location: location,
                accessibilityIdentifierPrefix: "idea.schedule.locationPicker"
            ) { updatedLocation in
                location = updatedLocation
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            guard workspace.makeScheduleRequest(for: request.ideaSnapshot) == request else {
                dismiss()
                return
            }
        }
        .onChange(of: authentication?.principalGeneration) { _, _ in
            dismiss()
        }
        .onChange(of: currentScheduleRequest) { _, updatedRequest in
            guard updatedRequest == request else {
                dismiss()
                return
            }
        }
    }

    private var scheduleErrorMessage: String {
        if let amount = initialConfiguration.proposedBudget, amount > .zero,
           (workspace.workspaceBudgetCap == nil || amount > workspace.freeBudgetPool + (workspace.mainEventBudgetCap ?? .zero)) {
            return String(localized: "There isn’t enough available budget for this event. Adjust its budget or the available funds, then try again.")
        }
        if let amount = initialConfiguration.proposedBudget, amount > .zero,
           initialConfiguration.audience == .hostsOnly,
           workspace.currentViewerMember(for: .main)?.participantRole != .host {
            return String(localized: "You can’t allocate this event’s budget with its current participants. Update its audience before scheduling.")
        }
        return String(localized: "This event couldn’t be scheduled. Try again.")
    }

    private func confirmSchedule() {
        guard workspace.makeScheduleRequest(for: request.ideaSnapshot) == request else {
            dismiss()
            return
        }

        var configuration = initialConfiguration
        let normalizedSchedule = EventSchedule(
            startsAt: startsAt,
            endsAt: endsAt,
            isAllDay: isAllDay,
            timeZoneIdentifier: timeZoneIdentifier
        ).normalized
        configuration.proposedDate = normalizedSchedule.startsAt
        configuration.proposedEndDate = normalizedSchedule.endsAt
        configuration.isAllDay = normalizedSchedule.isAllDay
        configuration.timeZoneIdentifier = normalizedSchedule.timeZoneIdentifier
        configuration.location = location

        let scheduledEventID = withAnimation {
            workspace.confirmScheduleEventIdea(request, configuration: configuration)
        }
        guard scheduledEventID != nil else {
            showingScheduleError = true
            return
        }

        AppHaptics.play(.success)
        dismiss()
    }
}

enum IdeaScheduleCopy {
    static var action: String {
        String(localized: "idea.schedule.action", defaultValue: "Schedule")
    }
}
