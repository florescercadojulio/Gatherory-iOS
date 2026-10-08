import Combine
import CoreLocation
import CoreLocationUI
import MapKit
import SwiftUI

struct EventLocationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissSearch) private var dismissSearch
    @StateObject private var searchModel = LocationSearchModel()
    @StateObject private var currentLocationModel = CurrentLocationModel()
    @State private var draft: EventLocation?
    @State private var isResolvingSelection = false
    private let save: (EventLocation?) -> Void

    init(
        location: EventLocation?,
        save: @escaping (EventLocation?) -> Void
    ) {
        _draft = State(initialValue: location)
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                if searchModel.query.isEmpty {
                    currentLocation
                }

                if !searchModel.query.isEmpty {
                    searchResults
                }

                if draft != nil {
                    selectedLocation
                    optionalDetails
                } else if searchModel.query.isEmpty {
                    ContentUnavailableView(
                        "Choose a Location",
                        systemImage: "mappin.and.ellipse",
                        description: Text("Search for an address or place for this event.")
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
            .onChange(of: currentLocationModel.resolvedLocation) { _, location in
                guard let location else { return }
                draft = location
                searchModel.query = ""
                dismissSearch()
            }
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchModel.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search Locations"
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        save(draft)
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                    .disabled(isResolvingSelection)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var currentLocation: some View {
        Section {
            if currentLocationModel.isLocating {
                HStack(spacing: AppTheme.Spacing.compact) {
                    ProgressView()
                    Text("Finding your location…")
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
            } else {
                LocationButton(.currentLocation) {
                    currentLocationModel.requestLocation()
                }
                .symbolVariant(.fill)
                .labelStyle(.titleAndIcon)
                .tint(AppTheme.ColorToken.accent)
                .foregroundStyle(.white)
                .clipShape(.capsule)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } header: {
            Text("Nearby")
        } footer: {
            if let errorMessage = currentLocationModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            } else {
                Text("Gatherory uses your location once to find the event address.")
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        Section("Search Results") {
            if isResolvingSelection {
                HStack(spacing: AppTheme.Spacing.compact) {
                    ProgressView()
                    Text("Loading location…")
                        .foregroundStyle(.secondary)
                }
            } else if searchModel.completions.isEmpty {
                if let errorMessage = searchModel.errorMessage {
                    ContentUnavailableView(
                        "Search Unavailable",
                        systemImage: "wifi.exclamationmark",
                        description: Text(errorMessage)
                    )
                } else if searchModel.isSearching {
                    HStack(spacing: AppTheme.Spacing.compact) {
                        ProgressView()
                        Text("Searching…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ContentUnavailableView(
                        "No Locations Found",
                        systemImage: "mappin.slash",
                        description: Text("Try a different place name or a more complete address.")
                    )
                }
            } else {
                ForEach(Array(searchModel.completions.enumerated()), id: \.offset) { _, completion in
                    Button {
                        choose(completion)
                    } label: {
                        HStack(spacing: AppTheme.Spacing.standard) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundStyle(AppTheme.ColorToken.accent)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(completion.title)
                                    .foregroundStyle(.primary)
                                if !completion.subtitle.isEmpty {
                                    Text(completion.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var selectedLocation: some View {
        Section("Event Location") {
            if let draft {
                HStack(spacing: AppTheme.Spacing.standard) {
                    Image(systemName: "mappin")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.ColorToken.accent, in: Circle())
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(draft.title)
                            .font(.body.weight(.medium))
                        if !draft.detail.isEmpty {
                            Text(draft.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)

                    Spacer(minLength: AppTheme.Spacing.compact)

                    Button("Clear Location", systemImage: "xmark.circle.fill") {
                        self.draft = nil
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: AppTheme.Layout.minimumTouchTarget, minHeight: AppTheme.Layout.minimumTouchTarget)
                }
            }
        }
    }

    @ViewBuilder
    private var optionalDetails: some View {
        Section {
            TextField(
                "Example: Apt 1A",
                text: Binding(
                    get: { draft?.addressLine2 ?? "" },
                    set: { draft?.addressLine2 = $0 }
                )
            )
            .textContentType(.fullStreetAddress)
            .textInputAutocapitalization(.words)
        } header: {
            Text("Apartment, Unit, or Floor")
        } footer: {
            Text("Optional. This appears with the event location.")
        }

        Section {
            TextField(
                "Example: Jordan’s Parents’ House",
                text: Binding(
                    get: { draft?.locationName ?? "" },
                    set: { draft?.locationName = $0 }
                )
            )
            .textInputAutocapitalization(.words)
        } header: {
            Text("Location Name")
        } footer: {
            Text("Optional. Use a familiar name people will recognize.")
        }
    }

    private func choose(_ completion: MKLocalSearchCompletion) {
        isResolvingSelection = true
        Task {
            defer { isResolvingSelection = false }
            if let resolvedLocation = await searchModel.resolve(completion) {
                draft = resolvedLocation
                searchModel.query = ""
                dismissSearch()
            }
        }
    }
}

@MainActor
private final class CurrentLocationModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var resolvedLocation: EventLocation?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLocating = false

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() {
        errorMessage = nil
        isLocating = true
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            isLocating = false
            errorMessage = "Your current location couldn’t be determined. Try again or search instead."
            return
        }

        Task {
            await resolve(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        isLocating = false

        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            errorMessage = "Location access is off. Search for the event location instead, or allow access in Settings."
        } else {
            errorMessage = "Your current location couldn’t be determined. Try again or search instead."
        }
    }

    private func resolve(_ location: CLLocation) async {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            isLocating = false
            errorMessage = "This location couldn’t be matched to an address. Search for it instead."
            return
        }

        do {
            let items = try await request.mapItems
            guard let item = items.first else {
                isLocating = false
                errorMessage = "This location couldn’t be matched to an address. Search for it instead."
                return
            }

            let address = item.address?.fullAddress ?? ""
            let shortAddress = item.address?.shortAddress ?? ""
            let coordinate = item.location.coordinate

            resolvedLocation = EventLocation(
                address: address.isEmpty ? shortAddress : address,
                shortAddress: shortAddress,
                placeName: item.name ?? "Current Location",
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                mapItemIdentifier: item.identifier?.rawValue
            )
            isLocating = false
        } catch {
            isLocating = false
            errorMessage = "This location couldn’t be matched to an address. Search for it instead."
        }
    }
}

@MainActor
private final class LocationSearchModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" {
        didSet {
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            errorMessage = nil
            if trimmedQuery.isEmpty {
                completer.cancel()
                completions = []
                isSearching = false
            } else {
                isSearching = true
                completer.queryFragment = trimmedQuery
            }
        }
    }

    @Published private(set) var completions: [MKLocalSearchCompletion] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSearching = false

    private let completer: MKLocalSearchCompleter

    override init() {
        let completer = MKLocalSearchCompleter()
        completer.resultTypes = [.address, .pointOfInterest]
        completer.regionPriority = .default
        self.completer = completer
        super.init()
        completer.delegate = self
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = completer.results
        errorMessage = nil
        isSearching = false
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        completions = []
        errorMessage = "Check your connection and try again."
        isSearching = false
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> EventLocation? {
        do {
            let request = MKLocalSearch.Request(completion: completion)
            request.resultTypes = [.address, .pointOfInterest]
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else {
                errorMessage = "No matching location was found."
                return nil
            }

            let address = item.address?.fullAddress ?? completion.subtitle
            let shortAddress = item.address?.shortAddress ?? completion.title
            let coordinate = item.location.coordinate

            return EventLocation(
                address: address.isEmpty ? completion.title : address,
                shortAddress: shortAddress,
                placeName: item.name ?? completion.title,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                mapItemIdentifier: item.identifier?.rawValue
            )
        } catch {
            errorMessage = "This location couldn’t be loaded. Try another result."
            return nil
        }
    }
}

#Preview {
    EventLocationEditorView(location: nil) { _ in }
}
