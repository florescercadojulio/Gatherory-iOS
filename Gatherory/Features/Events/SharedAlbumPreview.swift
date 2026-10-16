import SwiftUI
import UIKit

/// A small window into the event's shared moments, using the same cards as the album.
struct SharedAlbumPreview<Actions: View>: View {
    let moments: [EventMoment]
    let open: () -> Void
    var openPhoto: ((EventMoment) -> Void)? = nil
    var avatar: (EventMoment) -> WorkspaceMember? = { _ in nil }
    @ViewBuilder let actions: Actions
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var availableWidth: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            if moments.isEmpty {
                Text(AlbumCopy.empty)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                MasonryLayout(
                    columnCount: AlbumPresentation.columnCount(isPad: UIDevice.current.userInterfaceIdiom == .pad, availableWidth: availableWidth - 24),
                    spacing: 10, layoutDirection: layoutDirection
                ) {
                    ForEach(Array(moments.prefix(4))) { moment in
                        SharedAlbumPhotoCard(moment: moment, member: avatar(moment)) {
                            if let openPhoto { openPhoto(moment) } else { open() }
                        }
                    }
                }
                .padding(12)
            }

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            layout {
                VStack(alignment: .leading, spacing: 3) {
                    Text(AlbumCopy.title).font(.headline)
                    if !moments.isEmpty {
                        Text(AlbumCopy.photoCount(moments.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) { actions }
                    .font(.body.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    }
}
