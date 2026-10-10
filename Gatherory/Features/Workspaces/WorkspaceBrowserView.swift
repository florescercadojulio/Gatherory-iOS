import SwiftUI

struct WorkspaceBrowserView: View {
    @Environment(WorkspaceLibrary.self) private var library
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isAddingWorkspace = false

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }

        return [GridItem(.adaptive(minimum: 300, maximum: 520), spacing: AppTheme.Spacing.standard)]
    }

    var body: some View {
        Group {
            if library.workspaces.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: AppTheme.Spacing.standard) {
                        ForEach(library.workspaces, id: \.mainEventID) { workspace in
                            Button {
                                library.open(workspace)
                            } label: {
                                WorkspacePreviewCard(workspace: workspace)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens this workspace")
                        }
                    }
                    .padding(.horizontal, AppTheme.Layout.screenHorizontal)
                    .padding(.top, AppTheme.Layout.screenTop)
                    .padding(.bottom, AppTheme.Layout.screenBottom)
                }
                .scrollIndicators(.hidden)
                .appSoftScrollEdges()
            }
        }
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Workspaces")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Add workspace", systemImage: "plus") {
                    isAddingWorkspace = true
                }
                .labelStyle(.iconOnly)

                AccountToolbarButton()
            }
        }
        .sheet(isPresented: $isAddingWorkspace) {
            NavigationStack {
                NewWorkspaceView()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Workspaces", systemImage: "rectangle.stack.badge.plus")
        } description: {
            Text("Create a workspace to start shaping an event with your people.")
        } actions: {
            Button("Add Workspace", systemImage: "plus") {
                isAddingWorkspace = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.Spacing.spacious)
    }
}

private struct WorkspacePreviewCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let workspace: WeddingWorkspace

    private var locationText: String? {
        let value = workspace.mainEventLocation?.formatted
            ?? [workspace.venueName, workspace.location]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        return value.isEmpty ? nil : value
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            MediaArtwork(
                imageData: workspace.mainEventImageData,
                assetName: workspace.mainEventImageData == nil ? "WeddingVenueHero" : nil,
                symbol: "sparkles",
                colors: [AppTheme.ColorToken.accent, AppTheme.ColorToken.lilac, AppTheme.ColorToken.mint],
                accent: .white,
                // Keep the library's first frame lightweight. Full-screen event
                // views can afford Glur; collection thumbnails already gain
                // legibility from the gradient below.
                progressiveBlurRadius: 0,
                blurStart: 0.5
            )

            LinearGradient(
                colors: [.clear, .black.opacity(0.12), .black.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                Label(
                    workspace.currentMainEventStatus.title,
                    systemImage: workspace.currentMainEventStatus.symbol
                )
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(minHeight: 30)
                .background(.ultraThinMaterial, in: Capsule())

                Spacer(minLength: AppTheme.Spacing.section)

                Text(workspace.title)
                    .font(AppTheme.Typography.sectionTitle)
                    .lineLimit(2)

                Text(workspace.weddingDate.formatted(date: .long, time: .omitted))
                    .font(.headline)

                if let locationText {
                    Label(locationText, systemImage: "mappin")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)
                }

                Label(
                    "\(workspace.participants(for: .main).count) people",
                    systemImage: "person.2.fill"
                )
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.82))
            }
            .padding(AppTheme.Spacing.spacious)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: dynamicCardHeight)
        .background(AppTheme.ColorToken.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var dynamicCardHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 560 : 470
    }

    private var accessibilitySummary: String {
        let date = workspace.weddingDate.formatted(date: .long, time: .omitted)
        let location = locationText.map { ", \($0)" } ?? ""
        return "\(workspace.title), \(date)\(location), \(workspace.currentMainEventStatus.title)"
    }
}

struct NewWorkspaceView: View {
    private enum FocusedField: Hashable {
        case eventName
        case budget
    }

    @Environment(WorkspaceLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    var onWorkspaceCreated: ((WeddingWorkspace) -> Void)?
    @State private var title = ""
    @State private var startsAt = Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now
    @State private var endsAt: Date?
    @State private var isAllDay = false
    @State private var timeZoneIdentifier = TimeZone.autoupdatingCurrent.identifier
    @State private var eventLocation: EventLocation?
    @State private var imageData: Data?
    @State private var budgetAmount = ""
    @State private var isEditingDateAndTime = false
    @State private var isEditingLocation = false
    @FocusState private var focusedField: FocusedField?

    init(onWorkspaceCreated: ((WeddingWorkspace) -> Void)? = nil) {
        self.onWorkspaceCreated = onWorkspaceCreated
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedBudget: Decimal? {
        guard !budgetAmount.isEmpty else { return nil }
        let decimalSeparator = Locale.current.decimalSeparator ?? "."
        let normalized = budgetAmount
            .replacingOccurrences(of: decimalSeparator, with: ".")
            .replacingOccurrences(of: ",", with: "")
        return Decimal(string: normalized)
    }

    private var budgetIsValid: Bool {
        budgetAmount.isEmpty || (parsedBudget.map { $0 > .zero } ?? false)
    }

    var body: some View {
        Form {
            Section("Event Name") {
                TextField("Event name", text: $title)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($focusedField, equals: .eventName)
                    .onSubmit { focusedField = nil }
            }
            .listRowBackground(AppTheme.ColorToken.surface)

            Section("Location (Optional)") {
                Button {
                    isEditingLocation = true
                } label: {
                    HStack(spacing: AppTheme.Spacing.standard) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(AppTheme.ColorToken.accent)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(eventLocation?.title ?? "Add Location")
                                .foregroundStyle(
                                    eventLocation == nil
                                        ? AppTheme.ColorToken.accent
                                        : AppTheme.ColorToken.textPrimary
                                )

                            if let detail = eventLocation?.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listRowBackground(AppTheme.ColorToken.surface)

            Section("Date & Time") {
                Button {
                    isEditingDateAndTime = true
                } label: {
                    EventScheduleRow(
                        startsAt: startsAt,
                        endsAt: endsAt,
                        isAllDay: isAllDay,
                        timeZoneIdentifier: timeZoneIdentifier
                    )
                }
                .buttonStyle(.plain)
            }
            .listRowBackground(AppTheme.ColorToken.surface)

            Section {
                TextField("Budget cap", text: $budgetAmount)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .budget)
            } header: {
                Text("Budget (Optional)")
            } footer: {
                Text("The main event starts with the full budget. You can allocate part of it to sub-events later.")
            }
            .listRowBackground(AppTheme.ColorToken.surface)

            Section("Cover") {
                PhotoAttachmentPicker(
                    imageData: $imageData,
                    emptySymbol: "rectangle.stack.badge.plus",
                    fallbackAssetName: "WeddingVenueHero",
                    suggestedConcept: "Artwork for \(trimmedTitle.isEmpty ? "our event" : trimmedTitle)"
                )
            }
            .listRowBackground(AppTheme.ColorToken.surface)
        }
        .formStyle(.grouped)
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .background(AppTheme.ColorToken.background)
        .navigationTitle("New Workspace")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    let workspace = WeddingWorkspace.newWorkspace(
                        title: trimmedTitle,
                        startsAt: startsAt,
                        endsAt: endsAt,
                        isAllDay: isAllDay,
                        timeZoneIdentifier: timeZoneIdentifier,
                        eventLocation: eventLocation,
                        imageData: imageData,
                        budgetCap: parsedBudget
                    )

                    if let onWorkspaceCreated {
                        onWorkspaceCreated(workspace)
                    } else {
                        library.add(workspace)
                    }
                    dismiss()
                }
                .disabled(trimmedTitle.isEmpty || !budgetIsValid)
                .keyboardShortcut(.defaultAction)
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
        .sheet(isPresented: $isEditingDateAndTime) {
            EventDateTimeEditorView(
                startsAt: startsAt,
                endsAt: endsAt,
                isAllDay: isAllDay,
                timeZoneIdentifier: timeZoneIdentifier
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
            EventLocationEditorView(location: eventLocation) { updatedLocation in
                eventLocation = updatedLocation
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

struct WorkspaceLibraryToolbarButton: View {
    let action: () -> Void

    var body: some View {
        Button("Workspaces", systemImage: "rectangle.grid.2x2.fill", action: action)
            .labelStyle(.iconOnly)
            .accessibilityHint("Returns to all workspaces")
    }
}
