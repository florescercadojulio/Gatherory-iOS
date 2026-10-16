import Foundation

enum AlbumDeletionPolicy {
    static func permitsDeletion(
        moment: EventMoment,
        eventID: UUID,
        viewerUserID: String?,
        hasGalleryUploadPermission: Bool,
        legacyMainEventID: UUID? = nil
    ) -> Bool {
        guard hasGalleryUploadPermission,
              let viewerUserID,
              moment.addedByUserID == viewerUserID else { return false }
        return (moment.eventID ?? legacyMainEventID) == eventID
    }
}
