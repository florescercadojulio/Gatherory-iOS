import Foundation

/// Copy shared by the event and idea image picker source flow.
enum CoverImageCopy {
    static var title: String { String(localized: "coverImage.title", defaultValue: "Cover Image") }
    static var addImage: String { String(localized: "coverImage.add", defaultValue: "Add Image") }
    static var changeImage: String { String(localized: "coverImage.change", defaultValue: "Change Image") }
    static var openChoices: String { String(localized: "coverImage.openChoices", defaultValue: "Opens image choices") }
    static var chooseImage: String { String(localized: "coverImage.choose", defaultValue: "Choose Image") }
    static var currentImage: String { String(localized: "coverImage.current", defaultValue: "Current Image") }
    static var chooseSource: String { String(localized: "coverImage.source", defaultValue: "Choose a Source") }
    static var chooseFromPhotos: String { String(localized: "coverImage.photos", defaultValue: "Choose from Photos") }
    static var photosDetail: String { String(localized: "coverImage.photosDetail", defaultValue: "Select an image from your photo library.") }
    static var reviewBeforeUse: String { String(localized: "coverImage.reviewBeforeUse", defaultValue: "Your image is prepared securely before it’s added.") }
    static var emptyPrompt: String { String(localized: "coverImage.emptyPrompt", defaultValue: "Choose or create artwork that helps everyone recognize it.") }
    static var browseFiles: String { String(localized: "coverImage.files", defaultValue: "Browse Files") }
    static var filesDetail: String { String(localized: "coverImage.filesDetail", defaultValue: "Choose a JPEG, PNG, HEIC, or other image file.") }
    static var takePhoto: String { String(localized: "coverImage.camera", defaultValue: "Take Photo") }
    static var cameraDetail: String { String(localized: "coverImage.cameraDetail", defaultValue: "Use the camera to create a new image.") }
    static var cameraUnavailable: String { String(localized: "coverImage.cameraUnavailable", defaultValue: "Camera isn’t available on this device.") }
    static var playground: String { String(localized: "coverImage.playground", defaultValue: "Create with Image Playground") }
    static var playgroundDetail: String { String(localized: "coverImage.playgroundDetail", defaultValue: "Generate original artwork using Apple’s experience.") }
    static var playgroundUnavailable: String { String(localized: "coverImage.playgroundUnavailable", defaultValue: "Image Playground isn’t available on this device.") }
    static var curated: String { String(localized: "coverImage.curated", defaultValue: "Curated Covers") }
    static var currentPreview: String { String(localized: "coverImage.currentPreview", defaultValue: "Current image") }
    static var defaultArtwork: String { String(localized: "coverImage.defaultArtwork", defaultValue: "Default artwork") }
    static var selectedImage: String { String(localized: "coverImage.selected", defaultValue: "Selected image") }
    static var useDefault: String { String(localized: "coverImage.useDefault", defaultValue: "Use Default Artwork") }
    static var removeImage: String { String(localized: "coverImage.remove", defaultValue: "Remove Image") }
    static var close: String { String(localized: "coverImage.close", defaultValue: "Close") }
    static var loading: String { String(localized: "coverImage.loading", defaultValue: "Loading image…") }
    static var loadFailed: String { String(localized: "coverImage.loadFailed", defaultValue: "This image couldn’t be opened. Choose another image and try again.") }
    static var tooLarge: String { String(localized: "coverImage.tooLarge", defaultValue: "This image is larger than 20 MB. Choose a smaller image.") }
    static var generatedFailed: String { String(localized: "coverImage.generatedFailed", defaultValue: "The generated image couldn’t be saved. Try creating it again.") }
    static var prepareFailed: String { String(localized: "coverImage.prepareFailed", defaultValue: "The photo couldn’t be prepared. Choose another image and try again.") }

    static var gardenWedding: String { String(localized: "coverImage.cover.gardenWedding", defaultValue: "Garden Wedding") }
    static var birthday: String { String(localized: "coverImage.cover.birthday", defaultValue: "Birthday") }
    static var cottage: String { String(localized: "coverImage.cover.cottage", defaultValue: "Cottage") }
    static var coast: String { String(localized: "coverImage.cover.coast", defaultValue: "Coast") }
    static var gathering: String { String(localized: "coverImage.cover.gathering", defaultValue: "Gathering") }
    static var dinner: String { String(localized: "coverImage.cover.dinner", defaultValue: "Dinner") }
    static var travel: String { String(localized: "coverImage.cover.travel", defaultValue: "Travel") }
    static var garden: String { String(localized: "coverImage.cover.garden", defaultValue: "Garden") }
}
