import SwiftUI

struct RegistryView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @State private var isAddingItem = false
    @State private var selectedCollection = RegistryCollection.available
    @State private var selectedItemID: UUID?
    @Namespace private var registryTransition

    private var availableItems: [RegistryItem] {
        workspace.registry.filter { !$0.isFulfilled }
    }

    private var reservedItems: [RegistryItem] {
        workspace.registry.filter(\.isFulfilled)
    }

    private var visibleItems: [RegistryItem] {
        switch selectedCollection {
        case .available:
            availableItems
        case .reserved:
            reservedItems
        }
    }

    var body: some View {
        @Bindable var workspace = workspace

        List {
            Section {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
                    Image(systemName: "gift.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(.black, in: Circle())

                    Text("Gifts for what comes next")
                        .font(AppTheme.Typography.sectionTitle)

                    Text("Collect meaningful things and experiences now, then let guests reserve one when you’re ready.")
                        .font(.subheadline)
                        .foregroundStyle(.black.opacity(0.62))

                    Toggle("Open to guests", isOn: $workspace.isRegistryShared)
                        .font(.headline)
                        .tint(.black)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard(
                    background: AppTheme.ColorToken.lilac,
                    foreground: .black,
                    padding: AppTheme.Spacing.spacious,
                    border: false
                )
                .listRowInsets(AppTheme.Layout.featuredRowInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                Picker("Registry status", selection: $selectedCollection) {
                    ForEach(RegistryCollection.allCases) { collection in
                        Text(collection.title)
                            .tag(collection)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityHint("Filters gifts by reservation status")
                .listRowInsets(AppTheme.Layout.featuredRowInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                if visibleItems.isEmpty {
                    ContentUnavailableView(
                        selectedCollection.emptyTitle,
                        systemImage: selectedCollection.symbol,
                        description: Text(selectedCollection.emptyDescription)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.section)
                    .listRowInsets(AppTheme.Layout.featuredRowInsets)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(visibleItems) { item in
                        Button {
                            selectedItemID = item.id
                        } label: {
                            RegistryItemRow(
                                item: item,
                                transitionNamespace: registryTransition
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens gift details")
                        .listRowInsets(AppTheme.Layout.listRowInsets)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            } header: {
                HStack {
                    Label(selectedCollection.title, systemImage: selectedCollection.symbol)

                    Spacer()

                    Text(visibleItems.count == 1 ? "1 gift" : "\(visibleItems.count) gifts")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .editorialEyebrow()
            }
        }
        .listStyle(.plain)
        .contentMargins(.top, AppTheme.Layout.screenTop, for: .scrollContent)
        .contentMargins(.bottom, AppTheme.Layout.screenBottom, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Registry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Add gift", systemImage: "plus") {
                    isAddingItem = true
                }
                .labelStyle(.iconOnly)

                AccountToolbarButton()
            }
        }
        .sheet(isPresented: $isAddingItem) {
            NavigationStack {
                RegistryItemEditorView()
            }
        }
        .navigationDestination(item: $selectedItemID) { itemID in
            RegistryItemDetailView(
                itemID: itemID,
                transitionNamespace: registryTransition
            )
        }
    }
}

private enum RegistryCollection: String, CaseIterable, Identifiable {
    case available
    case reserved

    var id: Self { self }

    var title: String {
        switch self {
        case .available: "Available"
        case .reserved: "Reserved"
        }
    }

    var symbol: String {
        switch self {
        case .available: "gift.fill"
        case .reserved: "checkmark.circle.fill"
        }
    }

    var emptyTitle: String {
        switch self {
        case .available: "No available gifts"
        case .reserved: "No reserved gifts"
        }
    }

    var emptyDescription: String {
        switch self {
        case .available: "Add a gift or wait for a reserved gift to become available again."
        case .reserved: "Gifts appear here after guests reserve every available quantity."
        }
    }
}

private struct RegistryItemRow: View {
    let item: RegistryItem
    var transitionNamespace: Namespace.ID?

    var body: some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            artwork

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                Text(item.price, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    .font(.subheadline)
                    .foregroundStyle(.black.opacity(0.62))

                Text(item.isFulfilled ? "Reserved" : "\(item.remainingCount) of \(item.quantity) available")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.black)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(
            background: item.category.tint,
            foreground: .black,
            padding: AppTheme.Spacing.standard,
            border: false
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var artwork: some View {
        if let transitionNamespace {
            RegistryArtworkThumbnail(item: item)
                .matchedTransitionSource(id: item.id, in: transitionNamespace)
        } else {
            RegistryArtworkThumbnail(item: item)
        }
    }
}

private struct RegistryArtworkThumbnail: View {
    let item: RegistryItem

    var body: some View {
        MediaArtwork(
            imageData: item.imageData,
            symbol: item.category.symbol,
            colors: item.category.artworkColors,
            accent: item.category.artworkAccent,
            ambientBlurRadius: 4,
            progressiveBlurRadius: 0,
            blurStart: 1
        )
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

private struct RegistryItemDetailView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @State private var isEditingItem = false
    let itemID: UUID
    let transitionNamespace: Namespace.ID

    private var item: RegistryItem? {
        workspace.registry.first { $0.id == itemID }
    }

    var body: some View {
        Group {
            if let item {
                RegistryItemDetailScreen(
                    item: item,
                    isRegistryShared: workspace.isRegistryShared
                )
            } else {
                ContentUnavailableView("Gift unavailable", systemImage: "gift.slash")
            }
        }
        .navigationTitle("Gift details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if let item {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Edit gift", systemImage: "pencil") {
                        isEditingItem = true
                    }
                    .labelStyle(.iconOnly)

                    Button {
                        withAnimation(.snappy) {
                            workspace.commitToRegistryItem(item)
                        }
                    } label: {
                        Text(item.isFulfilled ? "Reserved" : "Reserve")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!workspace.isRegistryShared || item.isFulfilled)
                }
            }
        }
        .sheet(isPresented: $isEditingItem) {
            if let item {
                NavigationStack {
                    RegistryItemEditorView(item: item)
                }
            }
        }
        .navigationTransition(.zoom(sourceID: itemID, in: transitionNamespace))
    }
}

private struct RegistryItemDetailScreen: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let item: RegistryItem
    let isRegistryShared: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                backgroundArtwork
                readingScrim

                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
                        Spacer(minLength: max(proxy.size.height * 0.42, 260))

                        giftIdentity
                        metrics

                        if !isRegistryShared {
                            Label("The couple hasn’t opened this registry to guests yet.", systemImage: "lock.fill")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.84))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(AppTheme.Spacing.standard)
                                .background(.black.opacity(reduceTransparency ? 0.72 : 0.24), in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
                        }
                    }
                    .padding(.horizontal, AppTheme.Layout.screenHorizontal)
                    .padding(.bottom, AppTheme.Layout.screenBottom)
                    .frame(minHeight: proxy.size.height, alignment: .bottom)
                }
                .scrollIndicators(.hidden)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(.black)
    }

    private var backgroundArtwork: some View {
        MediaArtwork(
            imageData: item.imageData,
            symbol: item.category.symbol,
            colors: item.category.artworkColors,
            accent: item.category.artworkAccent,
            ambientBlurRadius: 10,
            progressiveBlurRadius: reduceTransparency ? 0 : 22,
            blurStart: 0.44
        )
        .ignoresSafeArea()
    }

    private var readingScrim: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.30),
                .init(color: .black.opacity(0.05), location: 0.48),
                .init(color: .black.opacity(reduceTransparency ? 0.56 : 0.22), location: 0.65),
                .init(color: .black.opacity(reduceTransparency ? 0.78 : 0.46), location: 0.82),
                .init(color: .black.opacity(reduceTransparency ? 0.88 : 0.60), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var giftIdentity: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: AppTheme.Spacing.compact) {
                Label(item.category.title, systemImage: item.category.symbol)
                    .font(.caption.weight(.semibold))

                Spacer(minLength: AppTheme.Spacing.compact)

                Label(
                    item.isFulfilled ? "Reserved" : "Available",
                    systemImage: item.isFulfilled ? "checkmark.circle.fill" : "gift.fill"
                )
                .font(.caption.weight(.semibold))
            }

            Text(item.title)
                .font(.largeTitle.bold())
                .tracking(-0.7)
                .fixedSize(horizontal: false, vertical: true)

            Text(item.note)
                .font(.body)
                .foregroundStyle(.white.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var metrics: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: AppTheme.Spacing.compact) {
                metricViews
            }
        } else {
            HStack(spacing: AppTheme.Spacing.compact) {
                metricViews
            }
        }
    }

    @ViewBuilder
    private var metricViews: some View {
        RegistryMetric(
            title: "Price",
            value: item.price.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")),
            symbol: "tag.fill",
            reduceTransparency: reduceTransparency
        )
        RegistryMetric(
            title: "Available",
            value: "\(item.remainingCount) of \(item.quantity)",
            symbol: "shippingbox.fill",
            reduceTransparency: reduceTransparency
        )
    }

}

private struct RegistryMetric: View {
    let title: String
    let value: String
    let symbol: String
    let reduceTransparency: Bool

    var body: some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            Image(systemName: symbol)
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                Text(value)
                    .font(.headline)
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(.black.opacity(reduceTransparency ? 0.72 : 0.24), in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RegistryItemEditorView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss

    private let item: RegistryItem?

    @State private var title: String
    @State private var note: String
    @State private var category: RegistryCategory
    @State private var price: String
    @State private var quantity: Int
    @State private var imageData: Data?

    init(item: RegistryItem? = nil) {
        self.item = item
        _title = State(initialValue: item?.title ?? "")
        _note = State(initialValue: item?.note ?? "")
        _category = State(initialValue: item?.category ?? .home)
        _price = State(initialValue: item.map { NSDecimalNumber(decimal: $0.price).stringValue } ?? "")
        _quantity = State(initialValue: item?.quantity ?? 1)
        _imageData = State(initialValue: item?.imageData)
    }

    private var parsedPrice: Decimal? {
        Decimal(string: price)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var minimumQuantity: Int {
        max(item?.committedCount ?? 0, 1)
    }

    var body: some View {
        Form {
            Section("Photo") {
                PhotoAttachmentPicker(
                    imageData: $imageData,
                    emptySymbol: category.symbol
                )
            }

            Section("Gift") {
                TextField("Name", text: $title)
                TextField("Why it matters", text: $note, axis: .vertical)
                    .lineLimit(2...5)
                Picker("Category", selection: $category) {
                    ForEach(RegistryCategory.allCases) { category in
                        Label(category.title, systemImage: category.symbol)
                            .tag(category)
                    }
                }
            }

            Section("Details") {
                TextField("Price", text: $price)
                    .keyboardType(.decimalPad)
                Stepper("Quantity: \(quantity)", value: $quantity, in: minimumQuantity...20)

                if minimumQuantity > 1 {
                    Text("Quantity can’t be lower than the number already reserved.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(item == nil ? "Add to registry" : "Edit gift")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(item == nil ? "Add" : "Save") {
                    guard let parsedPrice else { return }

                    let updatedItem = RegistryItem(
                        id: item?.id ?? UUID(),
                        title: trimmedTitle,
                        note: trimmedNote,
                        category: category,
                        price: parsedPrice,
                        quantity: quantity,
                        committedCount: min(item?.committedCount ?? 0, quantity),
                        imageData: imageData
                    )

                    if item == nil {
                        workspace.addRegistryItem(updatedItem)
                    } else {
                        workspace.updateRegistryItem(updatedItem)
                    }

                    dismiss()
                }
                .disabled(trimmedTitle.isEmpty || trimmedNote.isEmpty || parsedPrice == nil)
            }
        }
    }
}

#Preview {
    NavigationStack {
        RegistryView()
            .environment(WeddingWorkspace.sample)
    }
}
