import SwiftUI

struct BlockedPeopleView: View {
    @Environment(ImageSafetyStore.self) private var safety
    @State private var busyUserID: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Text(AppCopy.Safety.blockExplanation)
            }
            if safety.blockedUserIDs.isEmpty { Text(AppCopy.Safety.noBlockedPeople).foregroundStyle(.secondary) }
            ForEach(safety.blockedUserIDs.sorted(), id: \.self) { userID in
                VStack(alignment: .leading, spacing: 8) {
                    Text(safety.blockedNames[userID] ?? AppCopy.Safety.blockedPerson)
                    if safety.pendingBlockIDs.contains(userID) { Text(AppCopy.Safety.blockWaiting).font(.footnote).foregroundStyle(.secondary) }
                    HStack {
                        Button(AppCopy.Safety.unblock) { Task { await perform(userID, unblock: true) } }
                        if safety.pendingBlockIDs.contains(userID) {
                            Button(AppCopy.Common.retry) { Task { await perform(userID, unblock: false) } }
                        }
                        if busyUserID == userID { ProgressView() }
                    }.disabled(busyUserID != nil)
                }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(AppTheme.ColorToken.warning) }
        }
        .navigationTitle(AppCopy.Safety.blockedPeople)
        .task { await safety.refresh() }
    }
    @MainActor private func perform(_ userID: String, unblock: Bool) async {
        busyUserID = userID; errorMessage = nil
        defer { busyUserID = nil }
        do {
            if unblock { try await safety.unblock(userID) }
            else { try await safety.block(userID, name: safety.blockedNames[userID] ?? AppCopy.Safety.blockedPerson) }
        } catch { errorMessage = error.localizedDescription }
    }
}
