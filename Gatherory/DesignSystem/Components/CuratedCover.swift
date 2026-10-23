import Foundation
import UIKit

/// A small set of bundled, offline-ready cover photos for an event.
enum CuratedCover: String, CaseIterable, Identifiable {
    case gardenWedding
    case birthday
    case cottage
    case coast
    case gathering
    case dinner
    case travel
    case garden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gardenWedding: CoverImageCopy.gardenWedding
        case .birthday: CoverImageCopy.birthday
        case .cottage: CoverImageCopy.cottage
        case .coast: CoverImageCopy.coast
        case .gathering: CoverImageCopy.gathering
        case .dinner: CoverImageCopy.dinner
        case .travel: CoverImageCopy.travel
        case .garden: CoverImageCopy.garden
        }
    }

    var assetName: String {
        switch self {
        case .gardenWedding: "CuratedCoverGardenWedding"
        case .birthday: "CuratedCoverBirthday"
        case .cottage: "CuratedCoverCottage"
        case .coast: "CuratedCoverCoast"
        case .gathering: "CuratedCoverGathering"
        case .dinner: "CuratedCoverDinner"
        case .travel: "CuratedCoverTravel"
        case .garden: "CuratedCoverGarden"
        }
    }

    /// JPEG bytes decoded from the bundled asset catalog for image preparation.
    var imageData: Data? {
        UIImage(named: assetName)?.jpegData(compressionQuality: 0.9)
    }
}
