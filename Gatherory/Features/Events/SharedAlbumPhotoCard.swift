import Glur
import ImageIO
import SwiftUI
import UIKit

/// The collage uses lazy columns so offscreen photos don't all decode at once.
struct SharedAlbumCollage: View {
    @State private var columns: [[EventMoment]] = []
    @State private var aspectRatios: [UUID: CGFloat] = [:]
    @State private var readingOrder: [UUID: Double] = [:]
    let moments: [EventMoment]
    let availableWidth: CGFloat
    var isSelecting = false
    var selectedIDs: Set<UUID> = []
    var avatar: (EventMoment) -> WorkspaceMember? = { _ in nil }
    let open: (EventMoment) -> Void

    var body: some View {
        let count = AlbumPresentation.columnCount(isPad: UIDevice.current.userInterfaceIdiom == .pad, availableWidth: availableWidth)
        let width = max((availableWidth - CGFloat(count - 1) * 12) / CGFloat(count), 0)
        HStack(alignment: .top, spacing: 12) {
            ForEach(columns.indices, id: \.self) { index in
                LazyVStack(spacing: 12) {
                    ForEach(columns[index]) { moment in
                        SharedAlbumPhotoCard(
                            moment: moment, member: avatar(moment),
                            isSelecting: isSelecting, isSelected: selectedIDs.contains(moment.id),
                            aspectRatio: aspectRatios[moment.id]
                        ) { open(moment) }
                        .accessibilitySortPriority(readingOrder[moment.id] ?? 0)
                    }
                }
                .frame(width: width)
            }
        }
        .onChange(of: CollageInput(moments: moments, width: width, count: count), initial: true) { _, input in
            // Selection updates don't reread every original's metadata.
            columns = AlbumPresentation.columns(moments: input.moments, count: input.count, columnWidth: input.width)
            aspectRatios = Dictionary(input.moments.map { ($0.id, AlbumPresentation.aspectRatio(imageData: $0.imageData)) }, uniquingKeysWith: { first, _ in first })
            readingOrder = Dictionary(input.moments.enumerated().map { ($0.element.id, Double(input.moments.count - $0.offset)) }, uniquingKeysWith: { first, _ in first })
        }
    }

    private struct CollageInput: Equatable {
        let moments: [EventMoment]
        let width: CGFloat
        let count: Int
    }
}

struct SharedAlbumPhotoCard: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let moment: EventMoment
    let member: WorkspaceMember?
    var isSelecting = false
    var isSelected = false
    var aspectRatio: CGFloat? = nil
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            SharedAlbumThumbnail(moment: moment)
                .aspectRatio(aspectRatio ?? AlbumPresentation.aspectRatio(imageData: moment.imageData), contentMode: .fit)
                .overlay(alignment: .bottom) {
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 100)
                            .accessibilityHidden(true)
                        SharedAlbumContributor(moment: moment, member: member)
                            .foregroundStyle(.white)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(alignment: .bottom) {
                                if reduceTransparency { Color.black }
                            }
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isSelecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 24, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(isSelected ? Color.accentColor : .white, .white)
                            .padding(10)
                            .background(.black.opacity(0.65), in: Circle())
                            .padding(8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                }
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(false)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(AlbumCopy.photoBy(moment.addedBy))
        .accessibilityValue(isSelecting ? (isSelected ? AlbumCopy.selected : AlbumCopy.notSelected) : moment.addedAt.formatted(date: .abbreviated, time: .omitted))
        .accessibilityHint(isSelecting ? AlbumCopy.toggleSelectionHint : AlbumCopy.openPhotoHint)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("album.photo.\(moment.id.uuidString)")
        .accessibilityAction { open() }
    }
}

struct SharedAlbumContributor: View {
    let moment: EventMoment
    let member: WorkspaceMember?
    var showsDate = false

    var body: some View {
        HStack(spacing: 8) {
            if let member {
                ParticipantAvatarView(member: member, size: showsDate ? 36 : 26)
            } else {
                Text(initials)
                    .font(.system(size: showsDate ? 14 : 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: showsDate ? 36 : 26, height: showsDate ? 36 : 26)
                    .background(.black.opacity(0.7), in: Circle())
                    .overlay { Circle().stroke(.white.opacity(0.6), lineWidth: 0.5) }
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(moment.addedBy)
                    .font(showsDate ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showsDate {
                    Text(moment.addedAt, format: .dateTime.month(.abbreviated).day().year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AlbumCopy.photoBy(moment.addedBy))
        .accessibilityValue(showsDate ? moment.addedAt.formatted(date: .abbreviated, time: .omitted) : "")
    }

    private var initials: String {
        let parts = moment.addedBy.split(whereSeparator: \.isWhitespace)
        return parts.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

/// Only display-sized, orientation-correct thumbnails are decoded for the collage.
struct SharedAlbumThumbnail: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var image: UIImage?
    let moment: EventMoment

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppTheme.ColorToken.surface)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .glur(radius: reduceTransparency ? 0 : 8, mask: .linear(stops: [
                .init(intensity: 0, location: 0.65),
                .init(intensity: 1, location: 1)
            ], startPoint: .top, endPoint: .bottom))
            .clipped()
            .task(id: ThumbnailRequest(data: moment.imageData, pixels: Int(max(proxy.size.width, proxy.size.height) * displayScale))) {
                let data = moment.imageData
                let pixels = max(1, Int(max(proxy.size.width, proxy.size.height) * displayScale))
                let decoded = await Task.detached(priority: .userInitiated) {
                    guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                          let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: min(pixels, 1600),
                            kCGImageSourceShouldCacheImmediately: true
                          ] as CFDictionary) else { return nil as UIImage? }
                    return UIImage(cgImage: thumbnail)
                }.value
                guard !Task.isCancelled else { return }
                image = decoded
            }
        }
    }

    private struct ThumbnailRequest: Equatable {
        let data: Data
        let pixels: Int
    }
}
