import Foundation

enum BlueprintCoverCopy {
    static var title: String { String(localized: "blueprintCover.title", defaultValue: "Cover Image") }
    static var add: String { String(localized: "blueprintCover.add", defaultValue: "Add Cover Image") }
    static var save: String { String(localized: "blueprintCover.save", defaultValue: "Save Cover") }
    static var cancel: String { String(localized: "blueprintCover.cancel", defaultValue: "Cancel") }
    static var loading: String { String(localized: "blueprintCover.loading", defaultValue: "Preparing cover image…") }
    static var uploading: String { String(localized: "blueprintCover.uploading", defaultValue: "Uploading cover image…") }
    static var retry: String { String(localized: "blueprintCover.retry", defaultValue: "Retry Upload") }
    static var discardPending: String { String(localized: "blueprintCover.discardPending", defaultValue: "Discard Pending Image") }
    static var remove: String { String(localized: "blueprintCover.remove", defaultValue: "Remove Image") }
    static var uploadFailed: String { String(localized: "blueprintCover.uploadFailed", defaultValue: "The cover image couldn’t be uploaded. Check your connection and retry.") }
    static var requestFailed: String { String(localized: "blueprintCover.requestFailed", defaultValue: "The cover image request couldn’t be completed. Try again.") }
    static var loadFailed: String { String(localized: "blueprintCover.loadFailed", defaultValue: "The cover image couldn’t be loaded.") }
    static var invalidResponse: String { String(localized: "blueprintCover.invalidResponse", defaultValue: "The cover image service returned an unexpected response.") }
    static var signInRequired: String { String(localized: "blueprintCover.signInRequired", defaultValue: "Sign in again to upload a cover image.") }
    static var placeholder: String { String(localized: "blueprintCover.placeholder", defaultValue: "Choose a cover that sets the tone.") }
}
