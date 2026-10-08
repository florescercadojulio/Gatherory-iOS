import SwiftUI

struct RegistryView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @State private var isAddingItem = false

    private var availableItems: [RegistryItem] {
        workspace.registry.filter { !$0.isFulfilled }
    }

    private var fulfilledItems: [RegistryItem] {
        workspace.registry.filter(\.isFulfilled)
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
                ForEach(availableItems) { item in
                    NavigationLink {
                        RegistryItemDetailView(itemID: item.id)
                    } label: {
                        RegistryItemRow(item: item)
                    }
                    .listRowInsets(AppTheme.Layout.listRowInsets)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } header: {
                Text("Available gifts")
                    .editorialEyebrow()
            }

            if !fulfilledItems.isEmpty {
                Section {
                    ForEach(fulfilledItems) { item in
                        RegistryItemRow(item: item)
                            .listRowInsets(AppTheme.Layout.listRowInsets)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } header: {
                    Text("Reserved")
                        .editorialEyebrow()
                }
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
                AddRegistryItemView()
            }
        }
    }
}

private struct RegistryItemRow: View {
    let item: RegistryItem

    var body: some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            Image(systemName: item.category.symbol)
                .font(.title3)
                .foregroundStyle(.black)
                .frame(width: 48, height: 48)
                .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.Radius.control))

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
}

private struct RegistryItemDetailView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    let itemID: UUID

    private var item: RegistryItem? {
        workspace.registry.first { $0.id == itemID }
    }

    var body: some View {
        ScrollView {
            if let item {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.spacious) {
                    Image(systemName: item.category.symbol)
                        .font(.system(size: 72, weight: .light))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 220)
                        .background(item.category.tint, in: RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous))

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
                        Text(item.category.title)
                            .editorialEyebrow()
                            .foregroundStyle(.secondary)

                        Text(item.title)
                            .font(AppTheme.Typography.display)

                        Text(item.note)
                            .foregroundStyle(.secondary)

                        LabeledContent("Price") {
                            Text(item.price, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        }

                        LabeledContent("Available", value: "\(item.remainingCount) of \(item.quantity)")
                    }

                    Button {
                        withAnimation {
                            workspace.commitToRegistryItem(item)
                        }
                    } label: {
                        Label(item.isFulfilled ? "Reserved" : "Reserve this gift", systemImage: item.isFulfilled ? "checkmark" : "gift")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .tint(AppTheme.ColorToken.accent)
                    .disabled(!workspace.isRegistryShared || item.isFulfilled)

                    if !workspace.isRegistryShared {
                        Label("The couple hasn’t opened this registry to guests yet.", systemImage: "lock.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, AppTheme.Layout.screenHorizontal)
                .padding(.top, AppTheme.Layout.screenTop)
                .padding(.bottom, AppTheme.Layout.screenBottom)
            }
        }
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Gift details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AddRegistryItemView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var note = ""
    @State private var category = RegistryCategory.home
    @State private var price = ""
    @State private var quantity = 1

    private var parsedPrice: Decimal? {
        Decimal(string: price)
    }

    var body: some View {
        Form {
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
                Stepper("Quantity: \(quantity)", value: $quantity, in: 1...20)
            }
        }
        .navigationTitle("Add to registry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    guard let parsedPrice else { return }
                    workspace.addRegistryItem(
                        RegistryItem(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                            category: category,
                            price: parsedPrice,
                            quantity: quantity
                        )
                    )
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parsedPrice == nil)
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
