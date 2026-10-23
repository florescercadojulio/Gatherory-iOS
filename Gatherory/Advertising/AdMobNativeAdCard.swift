import GoogleMobileAds
import SwiftUI
import UIKit

/// Explore card backed by a Google registered native-ad view. The card loads
/// only while mounted in an active Explore feed and owns one unique slot.
struct AdMobNativeAdCard: View {
    let slotID: String
    @Bindable var session: ExploreAdSession
    @State private var ownerID = UUID()
    @State private var ownsSlot = false

    init(slotID: String, session: ExploreAdSession) {
        self.slotID = slotID
        self.session = session
    }

    /// Measures the full native asset stack at the width and Dynamic Type
    /// category used by its host card. The temporary view is never laid out
    /// with bounds, so its NativeAd remains pending and unregistered.
    @MainActor
    static func measuredHeight(
        for nativeAd: NativeAd,
        width: CGFloat,
        contentSizeCategory: UIContentSizeCategory
    ) -> CGFloat {
        guard width.isFinite, width > 24 else { return 0 }

        let nativeView = RegisteredNativeAdView()
        nativeView.configureForMeasurement(nativeAd, contentSizeCategory: contentSizeCategory)
        let contentHeight = nativeView.fittingSize(forWidth: width - 24).height
        guard contentHeight.isFinite, contentHeight > 0 else { return 0 }
        return ceil(max(contentHeight, 44) + 24)
    }

    private var taskID: String {
        "\(session.scopeID):\(session.lifecycleGeneration):\(session.isPrepared)"
    }

    var body: some View {
        Group {
            if let nativeAd = session.ad(forSlotID: slotID) {
                NativeAdContentView(
                    nativeAd: nativeAd,
                    accent: AppTheme.ColorToken.accent,
                    accessibilityIdentifier: "explore.ad.\(slotID)"
                )
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(AppTheme.ColorToken.surface)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                            .stroke(AppTheme.ColorToken.cardBorder, lineWidth: 0.5)
                    }
                    .accessibilityElement(children: .contain)
            }
        }
        .task(id: taskID) {
            ownsSlot = session.claim(slotID: slotID, ownerID: ownerID)
            if ownsSlot { session.load(slotID: slotID) }
        }
        .onDisappear {
            if ownsSlot { session.release(slotID: slotID, ownerID: ownerID) }
            ownsSlot = false
        }
    }
}

/// A zero-size lifecycle hook for a scheduled slot. Attach it to the organic
/// feed card at the insertion point so an unloaded ad does not reserve a grid
/// cell. The mounted owner is reclaimed whenever the session resets.
struct ExploreAdSlotLoader: View {
    let slotID: String
    @Bindable var session: ExploreAdSession
    @State private var ownerID = UUID()
    @State private var ownsSlot = false

    private var taskID: String {
        "\(session.scopeID):\(session.lifecycleGeneration):\(session.isPrepared)"
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task(id: taskID) {
                ownsSlot = session.claim(slotID: slotID, ownerID: ownerID)
                if ownsSlot { session.load(slotID: slotID) }
            }
            .onDisappear {
                if ownsSlot { session.release(slotID: slotID, ownerID: ownerID) }
                ownsSlot = false
            }
    }
}

private struct NativeAdContentView: UIViewRepresentable {
    let nativeAd: NativeAd?
    let accent: Color
    let accessibilityIdentifier: String?
    var isPreviewSample = false

    init(
        nativeAd: NativeAd?,
        accent: Color,
        accessibilityIdentifier: String? = nil,
        isPreviewSample: Bool = false
    ) {
        self.nativeAd = nativeAd
        self.accent = accent
        self.accessibilityIdentifier = accessibilityIdentifier
        self.isPreviewSample = isPreviewSample
    }

    func makeUIView(context: Context) -> RegisteredNativeAdView {
        RegisteredNativeAdView()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: RegisteredNativeAdView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }

        let fittedSize = uiView.fittingSize(forWidth: width)
        guard fittedSize.height.isFinite, fittedSize.height > 0 else { return nil }
        return CGSize(
            width: width,
            height: ceil(max(fittedSize.height, 44))
        )
    }

    func updateUIView(_ view: RegisteredNativeAdView, context: Context) {
        view.tintColor = UIColor(accent)
        view.accessibilityIdentifier = accessibilityIdentifier
        view.populate(with: nativeAd, isPreviewSample: isPreviewSample)
    }
}

/// All ad assets are descendants of NativeAdView and registered with its
/// asset properties so the SDK can process clicks, impressions and AdChoices.
private final class RegisteredNativeAdView: NativeAdView {
    private let attributionLabel = UILabel()
    private let advertiserLabel = UILabel()
    private let headlineLabel = UILabel()
    private let bodyLabel = UILabel()
    private let iconImageView = UIImageView()
    private let mediaAssetView = MediaView()
    private let callToActionButton = UIButton(type: .system)
    private let choicesAssetView = AdChoicesView()
    private let sampleMediaPlaceholder = UIImageView(image: UIImage(systemName: "photo"))
    private var pendingNativeAd: NativeAd?
    private var measuredWidth: CGFloat = 0
    private var requestedHostSize: CGSize?

    private struct AssetLayout {
        var frames: [(UIView, CGRect)]
        var size: CGSize
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    // The fitting pass and layoutSubviews use the same width and measurements.
    // A UIStackView fitting pass could report a one-line height before its
    // multiline labels had received their final narrow column width.
    func fittingSize(forWidth width: CGFloat) -> CGSize {
        measuredWidth = width
        return assetLayout(forWidth: width).size
    }

    func configureForMeasurement(_ nativeAd: NativeAd, contentSizeCategory: UIContentSizeCategory) {
        traitOverrides.preferredContentSizeCategory = contentSizeCategory
        updateTypography()
        populate(with: nativeAd, isPreviewSample: false)
    }

    override var intrinsicContentSize: CGSize {
        guard measuredWidth > 0 else { return super.intrinsicContentSize }
        return CGSize(width: UIView.noIntrinsicMetric,
                      height: assetLayout(forWidth: measuredWidth).size.height)
    }

    func populate(with ad: NativeAd?, isPreviewSample: Bool) {
        if (pendingNativeAd ?? nativeAd) !== ad {
            nativeAd = nil
            pendingNativeAd = ad
        }
        attributionLabel.text = String(localized: "explore.ads.attribution", defaultValue: "Ad")
        advertiserLabel.text = ad?.advertiser ?? (isPreviewSample ? String(localized: "explore.ads.sample.advertiser", defaultValue: "Gatherory sample") : nil)
        advertiserLabel.isHidden = advertiserLabel.text == nil
        headlineLabel.text = ad?.headline ?? (isPreviewSample ? String(localized: "explore.ads.sample.headline", defaultValue: "Ideas for a memorable gathering") : nil)
        bodyLabel.text = ad?.body ?? (isPreviewSample ? String(localized: "explore.ads.sample.body", defaultValue: "This static sample shows the Explore advertising card layout.") : nil)
        bodyLabel.isHidden = bodyLabel.text == nil
        iconImageView.image = ad?.icon?.image
        iconImageView.isHidden = iconImageView.image == nil
        mediaAssetView.mediaContent = ad?.mediaContent
        sampleMediaPlaceholder.isHidden = !isPreviewSample

        var configuration = UIButton.Configuration.plain()
        configuration.title = ad?.callToAction ?? (isPreviewSample ? String(localized: "explore.ads.sample.action", defaultValue: "Sample call to action") : nil)
        configuration.titleAlignment = .leading
        configuration.titleLineBreakMode = .byWordWrapping
        configuration.baseForegroundColor = tintColor
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 0, bottom: 0, trailing: 0)
        callToActionButton.configuration = configuration
        updateActionTypography()
        callToActionButton.isHidden = configuration.title == nil
        callToActionButton.titleLabel?.numberOfLines = 0
        callToActionButton.titleLabel?.lineBreakMode = .byWordWrapping
        // Google handles the registered call-to-action's touch events.
        callToActionButton.isUserInteractionEnabled = false
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0 else { return }

        let layout = assetLayout(forWidth: bounds.width)
        // Dynamic Type or a column resize can require a new host height. Keep
        // the object pending until SwiftUI supplies that height; don't spin a
        // layout loop, clip advertiser assets, or register an overflowing view.
        if layout.size.height > bounds.height + 0.5, let displayedAd = nativeAd {
            pendingNativeAd = displayedAd
            nativeAd = nil
        }
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        for (view, frame) in layout.frames {
            view.frame = isRightToLeft
                ? CGRect(x: bounds.width - frame.maxX, y: frame.minY, width: frame.width, height: frame.height)
                : frame
        }
        sampleMediaPlaceholder.frame = mediaAssetView.bounds

        guard layout.size.height <= bounds.height + 0.5 else {
            measuredWidth = bounds.width
            if requestedHostSize != layout.size {
                requestedHostSize = layout.size
                invalidateIntrinsicContentSize()
            }
            return
        }
        requestedHostSize = nil
        let permittedBounds = bounds.insetBy(dx: -0.5, dy: -0.5)
        guard layout.frames.filter({ !$0.0.isHidden }).allSatisfy({ permittedBounds.contains($0.1) }) else { return }
        if let pendingNativeAd {
            self.pendingNativeAd = nil
            nativeAd = pendingNativeAd
        }
    }

    private func assetLayout(forWidth proposedWidth: CGFloat) -> AssetLayout {
        let width = proposedWidth.isFinite ? max(proposedWidth, 0) : 0
        guard width > 0 else { return AssetLayout(frames: [], size: .zero) }
        let gap: CGFloat = 8
        let choicesSize: CGFloat = min(44, width)
        let badgeWidth = min(width, max(18, ceil(attributionLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).width) + 8))
        let badgeHeight = max(18, labelHeight(attributionLabel, width: badgeWidth))
        let advertiserX = badgeWidth + gap
        let advertiserWidth = max(0, width - advertiserX - choicesSize - gap)
        let advertiserHeight = advertiserLabel.isHidden ? 0 : labelHeight(advertiserLabel, width: advertiserWidth)
        let publisherHeight = max(44, max(badgeHeight, advertiserHeight))
        var frames: [(UIView, CGRect)] = [
            (attributionLabel, CGRect(x: 0, y: (publisherHeight - badgeHeight) / 2, width: badgeWidth, height: badgeHeight)),
            (advertiserLabel, CGRect(x: min(advertiserX, width), y: 0, width: advertiserWidth, height: advertiserHeight)),
            (choicesAssetView, CGRect(x: width - choicesSize, y: 0, width: choicesSize, height: choicesSize))
        ]
        var y = publisherHeight + gap
        let iconSize: CGFloat = iconImageView.isHidden ? 0 : min(40, width)
        let titleX = iconSize > 0 ? min(iconSize + 10, width) : 0
        let titleWidth = max(0, width - titleX)
        let headlineHeight = labelHeight(headlineLabel, width: titleWidth)
        let titleHeight = max(iconSize, headlineHeight)
        frames.append((iconImageView, CGRect(x: 0, y: y + (titleHeight - iconSize) / 2, width: iconSize, height: iconSize)))
        frames.append((headlineLabel, CGRect(x: titleX, y: y + (titleHeight - headlineHeight) / 2, width: titleWidth, height: headlineHeight)))
        y += titleHeight
        if bodyLabel.isHidden {
            frames.append((bodyLabel, .zero))
        } else {
            y += gap
            let height = labelHeight(bodyLabel, width: width)
            frames.append((bodyLabel, CGRect(x: 0, y: y, width: width, height: height)))
            y += height
        }
        y += gap
        frames.append((mediaAssetView, CGRect(x: 0, y: y, width: width, height: 160)))
        y += 160
        if callToActionButton.isHidden {
            frames.append((callToActionButton, .zero))
        } else {
            y += gap
            let font = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traitCollection).withTraits(.traitBold)
            let text = callToActionButton.configuration?.title ?? ""
            let textBounds = (text as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font], context: nil)
            let height = max(44, ceil(textBounds.height) + 6)
            frames.append((callToActionButton, CGRect(x: 0, y: y, width: width, height: height)))
            y += height
        }
        return AssetLayout(frames: frames, size: CGSize(width: width, height: ceil(y)))
    }

    private func updateActionTypography() {
        let font = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traitCollection).withTraits(.traitBold)
        var configuration = callToActionButton.configuration ?? .plain()
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = font
            return attributes
        }
        callToActionButton.configuration = configuration
    }

    private func labelHeight(_ label: UILabel, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return ceil(label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
    }

    private func buildViewHierarchy() {
        backgroundColor = .clear
        attributionLabel.font = .preferredFont(forTextStyle: .caption2).withTraits(.traitBold)
        attributionLabel.adjustsFontForContentSizeCategory = true
        attributionLabel.textColor = .secondaryLabel
        attributionLabel.textAlignment = .center
        attributionLabel.backgroundColor = .secondarySystemBackground
        attributionLabel.layer.cornerRadius = 4
        attributionLabel.clipsToBounds = true
        attributionLabel.accessibilityLabel = String(localized: "explore.ads.advertisement", defaultValue: "Advertisement")
        advertiserLabel.font = .preferredFont(forTextStyle: .caption1)
        advertiserLabel.adjustsFontForContentSizeCategory = true
        advertiserLabel.textColor = .secondaryLabel
        advertiserLabel.numberOfLines = 0
        headlineLabel.font = .preferredFont(forTextStyle: .headline)
        headlineLabel.adjustsFontForContentSizeCategory = true
        headlineLabel.textColor = .label
        headlineLabel.numberOfLines = 0
        bodyLabel.font = .preferredFont(forTextStyle: .subheadline)
        bodyLabel.adjustsFontForContentSizeCategory = true
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 0
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.clipsToBounds = true
        iconImageView.layer.cornerRadius = 8
        mediaAssetView.contentMode = .scaleAspectFit
        mediaAssetView.clipsToBounds = true
        mediaAssetView.layer.cornerRadius = 10
        sampleMediaPlaceholder.contentMode = .center
        sampleMediaPlaceholder.tintColor = .tertiaryLabel
        sampleMediaPlaceholder.backgroundColor = .quaternarySystemFill
        sampleMediaPlaceholder.isHidden = true
        sampleMediaPlaceholder.isAccessibilityElement = true
        sampleMediaPlaceholder.accessibilityLabel = String(localized: "explore.ads.sample.mediaPlaceholder", defaultValue: "Sample media placeholder")
        mediaAssetView.addSubview(sampleMediaPlaceholder)
        for view in [attributionLabel, advertiserLabel, headlineLabel, bodyLabel, iconImageView, mediaAssetView, callToActionButton, choicesAssetView] {
            addSubview(view)
        }
        headlineView = headlineLabel
        bodyView = bodyLabel
        advertiserView = advertiserLabel
        iconView = iconImageView
        mediaView = mediaAssetView
        callToActionView = callToActionButton
        adChoicesView = choicesAssetView
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: RegisteredNativeAdView, _: UITraitCollection) in
            view.updateTypography()
            view.requestedHostSize = nil
            view.invalidateIntrinsicContentSize()
            view.setNeedsLayout()
        }
    }

    private func updateTypography() {
        attributionLabel.font = UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: traitCollection)
            .withTraits(.traitBold)
        advertiserLabel.font = .preferredFont(forTextStyle: .caption1, compatibleWith: traitCollection)
        headlineLabel.font = .preferredFont(forTextStyle: .headline, compatibleWith: traitCollection)
        bodyLabel.font = .preferredFont(forTextStyle: .subheadline, compatibleWith: traitCollection)
        updateActionTypography()
    }
}

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        let descriptor = fontDescriptor.withSymbolicTraits(traits) ?? fontDescriptor
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

#if DEBUG
/// A static visual fixture for Canvas. It contains sample copy only and never
/// creates an ad session, initializes the SDK or sends a request.
struct ExploreNativeAdPreviewFixture: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "explore.ads.previewFixture", defaultValue: "Preview fixture only"))
                .font(.caption)
                .foregroundStyle(.secondary)
            NativeAdContentView(
                nativeAd: nil,
                accent: AppTheme.ColorToken.accent,
                isPreviewSample: true
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.ColorToken.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(AppTheme.ColorToken.cardBorder, lineWidth: 0.5)
        }
    }
}

#endif
