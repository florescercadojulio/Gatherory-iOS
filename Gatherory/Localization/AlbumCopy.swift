import Foundation

/// Event album controls, feedback, and accessibility copy.
enum AlbumCopy {
    static var title: String { String(localized: "album.title", defaultValue: "Shared Album") }
    static var viewAll: String { String(localized: "album.viewAll", defaultValue: "View Album") }
    static var close: String { String(localized: "album.close", defaultValue: "Close Album") }
    static var closePhoto: String { String(localized: "album.closePhoto", defaultValue: "Close Photo") }
    static var deletePhoto: String { String(localized: "album.delete", defaultValue: "Delete Photo") }
    static var actions: String { String(localized: "album.actions", defaultValue: "Photo actions") }
    static var confirmDeleteTitle: String { String(localized: "album.delete.confirmTitle", defaultValue: "Delete This Photo?") }
    static var confirmDeleteMessage: String { String(localized: "album.delete.confirmMessage", defaultValue: "This removes the photo from the shared album for everyone.") }
    static var empty: String { String(localized: "album.empty", defaultValue: "Photos shared during the event will gather here.") }
    static var select: String { String(localized: "album.select", defaultValue: "Select") }
    static var selectAll: String { String(localized: "album.selectAll", defaultValue: "Select All") }
    static var deselectAll: String { String(localized: "album.deselectAll", defaultValue: "Deselect All") }
    static var selected: String { String(localized: "album.selected", defaultValue: "Selected") }
    static var notSelected: String { String(localized: "album.notSelected", defaultValue: "Not selected") }
    static var browseHint: String { String(localized: "album.browseHint", defaultValue: "The event, through everyone’s eyes. Tap a photo to take a closer look.") }
    static var selectionHint: String { String(localized: "album.selectionHint", defaultValue: "Choose the photos you’d like to keep in Photos.") }
    static var openPhotoHint: String { String(localized: "album.openPhotoHint", defaultValue: "Opens the full photo.") }
    static var toggleSelectionHint: String { String(localized: "album.toggleSelectionHint", defaultValue: "Toggles selection for saving to Photos.") }
    static var savePhoto: String { String(localized: "album.savePhoto", defaultValue: "Save Photo") }
    static var saving: String { String(localized: "album.saving", defaultValue: "Saving…") }
    static var savePermissionDenied: String { String(localized: "album.savePermissionDenied", defaultValue: "Allow Gatherory to add photos in Settings, then try saving again.") }
    static var saveInvalidImage: String { String(localized: "album.saveInvalidImage", defaultValue: "One of these photos couldn’t be opened. Nothing was saved. Try another selection.") }
    static var saveFailed: String { String(localized: "album.saveFailed", defaultValue: "Photos couldn’t be saved. Try again.") }
    static var openSettings: String { String(localized: "album.openSettings", defaultValue: "Open Settings") }
    static var photoUnavailable: String { String(localized: "album.photoUnavailable", defaultValue: "Photo Unavailable") }
    static var photoUnavailableDescription: String { String(localized: "album.photoUnavailableDescription", defaultValue: "This photo couldn’t be opened. Try another photo.") }
    static var zoomPhotoHint: String { String(localized: "album.zoomPhotoHint", defaultValue: "Pinch or double-tap to zoom. Swipe to see the next photo.") }
    static var zoomIn: String { String(localized: "album.zoomIn", defaultValue: "Zoom In") }
    static var zoomOut: String { String(localized: "album.zoomOut", defaultValue: "Zoom Out") }
    static var previousPhoto: String { String(localized: "album.previousPhoto", defaultValue: "Previous Photo") }
    static var nextPhoto: String { String(localized: "album.nextPhoto", defaultValue: "Next Photo") }
    static var deleteFailed: String { String(localized: "album.deleteFailed", defaultValue: "This photo couldn’t be deleted. Please try again.") }
    static var savedSinglePhoto: String { String(localized: "album.savedSinglePhoto", defaultValue: "Photo saved to Photos.") }
    static func selectedCount(_ count: Int) -> String {
        count == 1 ? String(localized: "album.singleSelected", defaultValue: "1 selected") : String(localized: "album.selectedCount", defaultValue: "\(count) selected")
    }
    static func saveSelection(_ count: Int) -> String {
        String(localized: "album.saveSelection", defaultValue: "Save to Photos (\(count))")
    }
    static func savedPhotos(_ count: Int) -> String {
        count == 1 ? savedSinglePhoto : String(localized: "album.savedPhotos", defaultValue: "\(count) photos saved to Photos.")
    }
    static func photoCount(_ count: Int) -> String {
        count == 1
            ? String(localized: "album.singlePhoto", defaultValue: "1 photo")
            : String(localized: "album.photoCount", defaultValue: "\(count) photos")
    }
    static func photoBy(_ name: String) -> String {
        String(localized: "album.photoBy", defaultValue: "Photo added by \(name)")
    }
    static func photoPosition(_ index: Int, total: Int) -> String {
        String(localized: "album.photoPosition", defaultValue: "\(index) / \(total)")
    }
}
