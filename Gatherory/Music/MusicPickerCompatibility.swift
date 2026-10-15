import MusicKit
import SwiftUI

extension View {
    func musicPickerCompatible(
        isPresented: Binding<Bool>,
        title: Text,
        selection: Binding<[Song]>,
        onLegacySelection: @escaping (MusicTrack) -> Void
    ) -> some View {
        modifier(
            MusicPickerCompatibilityModifier(
                isPresented: isPresented,
                title: title,
                selection: selection,
                onLegacySelection: onLegacySelection
            )
        )
    }
}

private struct MusicPickerCompatibilityModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: Text
    @Binding var selection: [Song]
    let onLegacySelection: (MusicTrack) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 27.0, *) {
            content.musicPicker(
                isPresented: $isPresented,
                title: title,
                selection: $selection
            )
        } else {
            content.sheet(isPresented: $isPresented) {
                NavigationStack {
                    MusicSearchView { track in
                        onLegacySelection(track)
                    }
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            title
                                .font(.headline)
                                .lineLimit(1)
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                isPresented = false
                            }
                        }
                    }
                }
            }
        }
    }
}
