import Foundation

enum BlueprintCopy {
    static var includeTodos: String { String(localized: "blueprint.includeTodos", defaultValue: "Include To-dos") }
    static var todoCopyExplanation: String { String(localized: "blueprint.todoCopyExplanation", defaultValue: "Copies start unfinished. Dates and people aren't included.") }
    static var creatorNameLabel: String { String(localized: "blueprint.creator.name", defaultValue: "Creator name") }
    static var creatorNameExplanation: String { String(localized: "blueprint.creator.publicNameExplanation", defaultValue: "This name will appear with your blueprint in Search and shared previews.") }
    static var statusLinkActive: String { String(localized: "blueprint.status.linkActive", defaultValue: "Link active") }
    static var statusInSearch: String { String(localized: "blueprint.status.inSearch", defaultValue: "In Search") }
    static var statusPrivate: String { String(localized: "blueprint.status.private", defaultValue: "Private") }
    static var creatorNameInvalid: String { String(localized: "blueprint.creatorName.invalid", defaultValue: "Enter a name up to 80 characters.") }
    static var publishingToSearch: String { String(localized: "blueprint.publishingToSearch", defaultValue: "Publishing…") }
    static func creatorByline(_ name: String) -> String {
        String.localizedStringWithFormat(String(localized: "blueprint.creator.byline", defaultValue: "By %@"), name)
    }
    static var omittedUnselectedContent: String { String(localized: "blueprint.omittedUnselectedContent", defaultValue: "Content for events you didn’t choose isn’t included.") }
    static var omittedUnsupportedContent: String { String(localized: "blueprint.omittedUnsupportedContent", defaultValue: "Some optional content isn’t supported in this version of Gatherory.") }
    static var previewSuggestedScheduleFormat: String { String(localized: "blueprint.previewSuggestedScheduleFormat", defaultValue: "Suggested · %@") }
    static var savedLinkUnavailable: String { String(localized: "blueprint.savedLinkUnavailable", defaultValue: "This link isn’t saved on this device. Use the menu to create a replacement.") }
    static var reviewEvents: String { String(localized: "blueprint.reviewEvents", defaultValue: "Events") }
    static var reviewGuidance: String { String(localized: "blueprint.reviewGuidance", defaultValue: "Tips & Instructions") }
    static var reviewSharingSummary: String { String(localized: "blueprint.reviewSharingSummary", defaultValue: "Share a reusable copy of this plan by link. It won’t appear in Search.") }
    static var reviewPrivateSummary: String { String(localized: "blueprint.reviewPrivateSummary", defaultValue: "Save a reusable copy of this plan. Your event stays unchanged.") }
    static var reviewPersonalTextWarning: String { String(localized: "blueprint.reviewPersonalTextWarning", defaultValue: "Check the included text for personal details. Guest lists, chats, and photos aren’t included.") }
    static var viewIncludedContent: String { String(localized: "blueprint.viewIncludedContent", defaultValue: "View Included Content") }
    static var editIncludedContent: String { String(localized: "blueprint.editIncludedContent", defaultValue: "Edit Content") }
    static var reviewSameDayFormat: String { String(localized: "blueprint.reviewSameDayFormat", defaultValue: "Same day · %@") }
    static var reviewDayBeforeFormat: String { String(localized: "blueprint.reviewDayBeforeFormat", defaultValue: "The day before · %@") }
    static var reviewDayAfterFormat: String { String(localized: "blueprint.reviewDayAfterFormat", defaultValue: "The next day · %@") }
    static var reviewDaysBeforeFormat: String { String(localized: "blueprint.reviewDaysBeforeFormat", defaultValue: "%lld days before · %@") }
    static var reviewDaysAfterFormat: String { String(localized: "blueprint.reviewDaysAfterFormat", defaultValue: "%lld days after · %@") }
    static var deletePersonalBlueprintMessage: String { String(localized: "blueprint.deletePersonalMessage", defaultValue: "This removes your blueprint from search and revokes its sharing links. Other people's completed copies and existing events stay unchanged.") }
    static var saveBlueprint: String { String(localized: "blueprint.saveToLibrary", defaultValue: "Save Blueprint") }
    static var blueprintSavedExplanation: String { String(localized: "blueprint.savedToLibrary", defaultValue: "Saved in Blueprints. Your event remains independent.") }
    static var previewInstall: String { String(localized: "blueprint.preview.install", defaultValue: "Use Blueprint") }
    static var confirmInstallTitle: String { String(localized: "blueprint.preview.confirmInstall", defaultValue: "Use This Blueprint?") }
    static var confirmInstallMessage: String { String(localized: "blueprint.preview.confirmInstallMessage", defaultValue: "Continue with these choices? You’ll choose dates before creating your event.") }
    static var previewNoIdeas: String { String(localized: "blueprint.preview.noIdeas", defaultValue: "There are no ideas to decide on in this preview.") }
    static var previewChoicesExplanation: String { String(localized: "blueprint.preview.choicesExplanation", defaultValue: "Choose the ideas you like. Save Draft to continue later.") }
    static var saveDraft: String { String(localized: "blueprint.preview.saveDraft", defaultValue: "Save Draft") }
    static var previewUnsavedTitle: String { String(localized: "blueprint.preview.unsaved", defaultValue: "Save your blueprint choices?") }
    static var discardPreviewChanges: String { String(localized: "blueprint.preview.discard", defaultValue: "Discard Changes") }
    static var previewSaveBeforeCustomize: String { String(localized: "blueprint.preview.saveBeforeCustomize", defaultValue: "Save your choices before customizing?") }
    static var saveAndCustomize: String { String(localized: "blueprint.preview.saveAndCustomize", defaultValue: "Save & Customize") }
    static var discardAndCustomize: String { String(localized: "blueprint.preview.discardAndCustomize", defaultValue: "Discard & Customize") }
    static var previewSaveFailed: String { String(localized: "blueprint.preview.saveFailed", defaultValue: "Couldn’t save your changes. Finish any pending event, or reopen your saved blueprint and try again.") }
    static var returnToTemplates: String { String(localized: "blueprint.preview.return", defaultValue: "Returns to blueprints") }
    static var libraryTitle: String { String(localized: "blueprint.library.title", defaultValue: "Blueprints") }
    static var libraryDrafts: String { String(localized: "blueprint.library.drafts", defaultValue: "Drafts") }
    static var libraryUsed: String { String(localized: "blueprint.library.used", defaultValue: "Blueprints") }
    static var libraryDraftsEmpty: String { String(localized: "blueprint.library.draftsEmpty", defaultValue: "Save a draft to continue working on it here later.") }
    static var libraryUsedEmpty: String { String(localized: "blueprint.library.usedEmpty", defaultValue: "Save a blueprint or choose one in Explore to get started.") }
    static var libraryLocalReadFailed: String { String(localized: "blueprint.library.localReadFailed", defaultValue: "Some saved blueprints couldn’t be opened. Try again.") }
    static var libraryRefreshFailed: String { String(localized: "blueprint.library.refreshFailed", defaultValue: "Couldn’t refresh your blueprints. Your saved copies are still on this device.") }
    static var libraryWorkspaceUnavailable: String { String(localized: "blueprint.library.workspaceUnavailable", defaultValue: "Event isn’t available on this device.") }
    static var libraryOpenWorkspace: String { String(localized: "blueprint.library.openWorkspace", defaultValue: "Open Event") }
    static func libraryUsedFor(_ name: String) -> String {
        String.localizedStringWithFormat(String(localized: "blueprint.library.usedFor", defaultValue: "Used for %@"), name)
    }
    static func libraryVersion(_ revision: Int) -> String {
        String.localizedStringWithFormat(String(localized: "blueprint.library.version", defaultValue: "Version %lld"), Int64(revision))
    }
    static var customizationInvalid: String { String(localized: "blueprint.customizationInvalid", defaultValue: "Couldn’t save your changes. Check your choices and try again.") }
    static var customize: String { String(localized: "blueprint.customize", defaultValue: "Customize") }
    static var allIdeas: String { String(localized: "All Ideas") }
    static func previewPosition(_ position: Int, total: Int) -> String {
        String.localizedStringWithFormat(String(localized: "blueprint.previewPosition", defaultValue: "%lld / %lld"), Int64(position), Int64(total))
    }
    static func previewPositionLabel(_ position: Int, total: Int) -> String {
        String.localizedStringWithFormat(String(localized: "blueprint.previewPositionLabel", defaultValue: "Idea %lld of %lld"), Int64(position), Int64(total))
    }
    static var savedPreviewExplanation: String { String(localized: "blueprint.savedPreviewExplanation", defaultValue: "Showing your saved copy. Connect to create an event.") }
    static var previewTitle: String { String(localized: "blueprint.previewTitle", defaultValue: "Blueprint Preview") }
    static var previewExplanation: String { String(localized: "blueprint.previewExplanation", defaultValue: "Choose what you want to use. Your event will be a separate copy.") }
    static var previewDatesExplanation: String { String(localized: "blueprint.previewDatesExplanation", defaultValue: "Choose dates when you create your event.") }
    static var sharedLinkUnavailable: String { String(localized: "blueprint.sharedLinkUnavailable", defaultValue: "This link is no longer available. Ask the sender for a new one.") }
    static var saveAsTemplate: String { String(localized: "blueprint.saveAsTemplate", defaultValue: "Save as Blueprint") }
    static var shareTemplate: String { String(localized: "blueprint.shareTemplate", defaultValue: "Share Blueprint") }
    static var shareLink: String { String(localized: "blueprint.shareLink", defaultValue: "Share Link") }
    static var manageSharing: String { String(localized: "blueprint.manageSharing", defaultValue: "Manage Sharing") }
    static var manageTemplateLinks: String { String(localized: "blueprint.manageTemplateLinks", defaultValue: "Manage Sharing") }
    static var templateLinksUnavailable: String { String(localized: "blueprint.templateLinksUnavailable", defaultValue: "Blueprint Links Unavailable") }
    static var lostTemplatePermission: String { String(localized: "blueprint.lostTemplatePermission", defaultValue: "You no longer have permission to manage blueprints for this event.") }
    static var templateLinkSignIn: String { String(localized: "blueprint.templateLinkSignIn", defaultValue: "Sign in to manage blueprint links.") }
    static var shareTemplateExplanation: String { String(localized: "blueprint.shareTemplateExplanation", defaultValue: "Anyone with this link can preview and save their own copy.") }
    static var unlistedSharingExplanation: String { String(localized: "blueprint.unlistedSharingExplanation", defaultValue: "Anyone with the link can preview and save a copy. This blueprint won’t appear in Search unless you publish it there.") }
    static var noCapturedTemplates: String { String(localized: "blueprint.noCapturedTemplates", defaultValue: "No blueprints have been captured from this event yet.") }
    static var captureBeforeSharing: String { String(localized: "blueprint.captureBeforeSharing", defaultValue: "Create a reusable blueprint from this event. Your event stays private.") }
    static var createTemplateTitle: String { String(localized: "blueprint.createTemplateTitle", defaultValue: "Create Blueprint") }
    static var templateCaptureExplanation: String { String(localized: "blueprint.templateCaptureExplanation", defaultValue: "Choose the event details to reuse. Nothing is created until you review and share.") }
    static var sourceEvent: String { String(localized: "blueprint.sourceEvent", defaultValue: "Source Event") }
    static var templateName: String { String(localized: "blueprint.templateName", defaultValue: "Blueprint name") }
    static var templateDetails: String { String(localized: "blueprint.templateDetails", defaultValue: "Blueprint Details") }
    static var captureChildren: String { String(localized: "blueprint.captureChildren", defaultValue: "Sub-events") }
    static var captureIdeas: String { String(localized: "blueprint.captureIdeas", defaultValue: "Ideas") }
    static var captureGuidance: String { String(localized: "blueprint.captureGuidance", defaultValue: "Guidance") }
    static var includeIdeaNotes: String { String(localized: "blueprint.includeIdeaNotes", defaultValue: "Include idea notes") }
    static var sourceDatesNotCopied: String { String(localized: "blueprint.sourceDatesNotCopied", defaultValue: "Dates from the source event aren’t copied.") }
    static var scheduleProposalExplanation: String { String(localized: "blueprint.scheduleProposalExplanation", defaultValue: "Suggested time %@ · %lld days from the main event") }
    static var templatePrivacyExplanation: String { String(localized: "blueprint.templatePrivacyExplanation", defaultValue: "Only the selected text is copied. Guest lists, RSVPs, chats, expenses, photos, and music aren’t included.") }
    static var searchPublication: String { String(localized: "blueprint.searchPublication", defaultValue: "Search Publication") }
    static var templateSearchPublicationExplanation: String { String(localized: "blueprint.templateSearchPublicationExplanation", defaultValue: "Publishing adds this blueprint to Search, where people can find it and install independent copies. The source event stays private; only the content you selected is published.") }
    static var reviewTemplate: String { String(localized: "blueprint.reviewTemplate", defaultValue: "Review") }
    static var editTemplate: String { String(localized: "blueprint.editTemplate", defaultValue: "Edit") }
    static var preparingTemplateReview: String { String(localized: "blueprint.preparingTemplateReview", defaultValue: "Getting blueprint ready…") }
    static var templateCreationLoadFailed: String { String(localized: "blueprint.templateCreationLoadFailed", defaultValue: "Couldn’t load event details. Check your connection and try again.") }
    static var templateCreationReviewFailed: String { String(localized: "blueprint.templateCreationReviewFailed", defaultValue: "Couldn’t prepare the blueprint. Try again.") }
    static var templateCreationUncertain: String { String(localized: "blueprint.templateCreationUncertain", defaultValue: "The blueprint may already have been created. Retry to recover the same blueprint.") }
    static var templateCreationLinkUncertain: String { String(localized: "blueprint.templateCreationLinkUncertain", defaultValue: "Your blueprint is ready, but the link may have been created. Refresh links before trying again.") }
    static var templateCreationPermissionLost: String { String(localized: "blueprint.templateCreationPermissionLost", defaultValue: "You no longer have permission to create a blueprint from this event.") }
    static var templateCreationInvalidResponse: String { String(localized: "blueprint.templateCreationInvalidResponse", defaultValue: "The server returned an unexpected blueprint response. Try refreshing the event.") }
    static var templateCreationSourceChanged: String { String(localized: "blueprint.templateCreationSourceChanged", defaultValue: "This event changed. Reload it before saving or sharing.") }
    static var reloadEvent: String { String(localized: "blueprint.reloadEvent", defaultValue: "Reload Event") }
    static var publishToSearch: String { String(localized: "blueprint.publishToSearch", defaultValue: "Publish to Search") }
    static var creatingTemplate: String { String(localized: "blueprint.creatingTemplate", defaultValue: "Creating blueprint…") }
    static var templateReady: String { String(localized: "blueprint.templateReady", defaultValue: "Blueprint Ready") }
    static var templateListedExplanation: String { String(localized: "blueprint.templateListedExplanation", defaultValue: "This blueprint is published in Search. People can find it and install independent copies.") }
    static var independentTemplateCopies: String { String(localized: "blueprint.independentTemplateCopies", defaultValue: "Each person gets an independent copy. Sharing the link doesn’t invite anyone to the source event.") }
    static var beforeYouShare: String { String(localized: "blueprint.beforeYouShare", defaultValue: "Before You Share") }
    static var guidanceAudience: String { String(localized: "blueprint.guidanceAudience", defaultValue: "For %@") }
    static var audienceEventParticipants: String { String(localized: "blueprint.audienceEventParticipants", defaultValue: "For event participants") }
    static var audiencePlanningOnly: String { String(localized: "blueprint.audiencePlanningOnly", defaultValue: "For planners only") }
    static var selectedTextMayBePersonal: String { String(localized: "blueprint.selectedTextMayBePersonal", defaultValue: "Selected text may include personal details. Review it before sharing.") }
    static var refreshLinks: String { String(localized: "blueprint.refreshLinks", defaultValue: "Refresh Links") }
    static var retryCreateShareLink: String { String(localized: "blueprint.retryCreateShareLink", defaultValue: "Create a New Share Link") }
    static var createdLinks: String { String(localized: "blueprint.createdLinks", defaultValue: "Created Links") }
    static var noPublishedTemplate: String { String(localized: "blueprint.noPublishedTemplate", defaultValue: "This blueprint is not ready to share yet.") }
    static var chooseTemplateHint: String { String(localized: "blueprint.chooseTemplateHint", defaultValue: "Choose one of the blueprints captured from this event.") }
    static var chooseTemplate: String { String(localized: "blueprint.chooseTemplate", defaultValue: "Blueprint") }
    static var publishedRevision: String { String(localized: "blueprint.publishedRevision", defaultValue: "Published version %lld") }
    static var retiredTemplate: String { String(localized: "blueprint.retiredTemplate", defaultValue: "Retired") }
    static var draftTemplate: String { String(localized: "blueprint.draftTemplate", defaultValue: "Draft · Not published") }
    static var retiredCannotShare: String { String(localized: "blueprint.retiredCannotShare", defaultValue: "This blueprint is no longer available to share. You can still revoke its links in the menu.") }
    static var replaceShareLink: String { String(localized: "blueprint.replaceShareLink", defaultValue: "Create Replacement Link") }
    static var confirmReplaceShareLinkTitle: String { String(localized: "blueprint.confirmReplaceShareLinkTitle", defaultValue: "Create a Replacement Link?") }
    static var confirmReplaceShareLinkMessage: String { String(localized: "blueprint.confirmReplaceShareLinkMessage", defaultValue: "This creates a new link and QR code. Existing links stay active until you revoke them.") }
    static var shareLinkStorageFailed: String { String(localized: "blueprint.shareLinkStorageFailed", defaultValue: "Couldn’t update this device’s saved link. Try again.") }
    static var shareLinkSaveFailed: String { String(localized: "blueprint.shareLinkSaveFailed", defaultValue: "This link couldn’t be saved on this device. Share it now or retry saving.") }
    static var shareLinkRestoreFailed: String { String(localized: "blueprint.shareLinkRestoreFailed", defaultValue: "Couldn’t reopen the saved link. Try again.") }
    static var retrySavingShareLink: String { String(localized: "blueprint.retrySavingShareLink", defaultValue: "Retry Saving Link") }
    static var createShareLink: String { String(localized: "blueprint.createShareLink", defaultValue: "Create Share Link") }
    static var creatingShareLink: String { String(localized: "blueprint.creatingShareLink", defaultValue: "Creating link…") }
    static var shareNewLink: String { String(localized: "blueprint.shareNewLink", defaultValue: "Share New Link") }
    static var showShareQRCode: String { String(localized: "blueprint.showShareQRCode", defaultValue: "Show QR Code") }
    static var shareQRCodeTitle: String { String(localized: "blueprint.shareQRCodeTitle", defaultValue: "Share QR Code") }
    static var shareQRCodeScanGuidance: String { String(localized: "blueprint.shareQRCodeScanGuidance", defaultValue: "Scanning opens a preview of this blueprint. The person scanning chooses whether to save and create an independent copy.") }
    static var shareQRCodeImageWarning: String { String(localized: "blueprint.shareQRCodeImageWarning", defaultValue: "The QR image contains this access link and can be forwarded. Revoking the link stops future access through it, but cannot remove copies already saved.") }
    static var shareQRCodeAccessibilityLabel: String { String(localized: "blueprint.shareQRCodeAccessibilityLabel", defaultValue: "QR code for the blueprint sharing link") }
    static var shareQRCodeAccessibilityHint: String { String(localized: "blueprint.shareQRCodeAccessibilityHint", defaultValue: "Scan to preview this blueprint. Saving and creating a copy are separate steps.") }
    static var shareQRCodeRenderFailed: String { String(localized: "blueprint.shareQRCodeRenderFailed", defaultValue: "This QR code couldn’t be prepared. Try again or share the link instead.") }
    static var newLinkReady: String { String(localized: "blueprint.newLinkReady", defaultValue: "This new link is shown only while this screen is open. Share or save it now.") }
    static var noLinksCreated: String { String(localized: "blueprint.noLinksCreated", defaultValue: "No links have been created for this blueprint.") }
    static var noLinksCreatedHint: String { String(localized: "blueprint.noLinksCreatedHint", defaultValue: "Create a link when you’re ready to share this published version.") }
    static var existingLinksCannotBeRecovered: String { String(localized: "blueprint.existingLinksCannotBeRecovered", defaultValue: "Only links saved on this device can be reopened here. Create a replacement if needed.") }
    static var activeShareLink: String { String(localized: "blueprint.activeShareLink", defaultValue: "Active") }
    static var revokedShareLink: String { String(localized: "blueprint.revokedShareLink", defaultValue: "Revoked") }
    static var revokeShareLink: String { String(localized: "blueprint.revokeShareLink", defaultValue: "Revoke Link") }
    static var confirmRevokeTitle: String { String(localized: "blueprint.confirmRevokeTitle", defaultValue: "Revoke This Link?") }
    static var confirmRevokeMessage: String { String(localized: "blueprint.confirmRevokeMessage", defaultValue: "People can no longer use this link to save the blueprint. Existing copies are not affected.") }
    static var revoke: String { String(localized: "blueprint.revoke", defaultValue: "Revoke") }
    static var shareLinksLoadFailed: String { String(localized: "blueprint.shareLinksLoadFailed", defaultValue: "Couldn’t load blueprint links. Check your connection and try again.") }
    static var shareLinkChangeFailed: String { String(localized: "blueprint.shareLinkChangeFailed", defaultValue: "The link could not be changed. Check your connection and try again.") }
    static var shareLinkCreationUncertain: String { String(localized: "blueprint.shareLinkCreationUncertain", defaultValue: "The link may have been created. Refresh links before trying again.") }
    static var shareLinkOffline: String { String(localized: "blueprint.shareLinkOffline", defaultValue: "Creating and revoking links requires a connection. No change was queued.") }
    static var listedInSearch: String { String(localized: "blueprint.listedInSearch", defaultValue: "Listed in Search") }
    static var notListedInSearch: String { String(localized: "blueprint.notListedInSearch", defaultValue: "Not listed in Search") }
    static var listInSearch: String { String(localized: "blueprint.listInSearch", defaultValue: "List in Search") }
    static var removeFromSearch: String { String(localized: "blueprint.removeFromSearch", defaultValue: "Remove from Search") }
    static var confirmListInSearchTitle: String { String(localized: "blueprint.confirmListInSearchTitle", defaultValue: "List This Blueprint in Search?") }
    static var confirmListInSearchMessage: String { String(localized: "blueprint.confirmListInSearchMessage", defaultValue: "People will be able to find this blueprint and make their own copies.") }
    static var confirmRemoveFromSearchTitle: String { String(localized: "blueprint.confirmRemoveFromSearchTitle", defaultValue: "Remove This Blueprint from Search?") }
    static var confirmRemoveFromSearchMessage: String { String(localized: "blueprint.confirmRemoveFromSearchMessage", defaultValue: "This hides the blueprint from Search. Share links and saved copies stay unchanged.") }
    static var listingDoesNotChangeLinks: String { String(localized: "blueprint.listingDoesNotChangeLinks", defaultValue: "Search visibility is separate from share links. Revoking a link doesn’t remove this blueprint from Search, and removing it from Search doesn’t revoke links or affect existing copies.") }
    static var retry: String { String(localized: "blueprint.retry", defaultValue: "Try Again") }
    static var resumeSetup: String { String(localized: "blueprint.resumeSetup", defaultValue: "Resume setup") }
    static var startOver: String { String(localized: "blueprint.startOver", defaultValue: "Start over") }
    static var startOverConfirmation: String { String(localized: "blueprint.startOverConfirmation", defaultValue: "Discard this saved setup and start again with the latest blueprint?") }
    static var draftSaveFailed: String { String(localized: "blueprint.draftSaveFailed", defaultValue: "Couldn’t save your setup on this device. Try again before closing.") }
    static var draftLoadFailed: String { String(localized: "blueprint.draftLoadFailed", defaultValue: "Couldn’t open saved setups on this device. Try refreshing.") }
    static var suggestionConfirmation: String { String(localized: "blueprint.suggestionConfirmation", defaultValue: "Confirm a date for each event you include.") }
    static var datesKept: String { String(localized: "blueprint.datesKept", defaultValue: "Your confirmed dates are unchanged.") }
    static var loadingDates: String { String(localized: "blueprint.loadingDates", defaultValue: "Finding suggested dates…") }
    static var datesUnavailable: String { String(localized: "blueprint.datesUnavailable", defaultValue: "Suggested dates aren’t available. You can still choose dates manually.") }
    static var confirmedDate: String { String(localized: "blueprint.confirmedDate", defaultValue: "Confirmed date") }
    static var confirmDate: String { String(localized: "blueprint.confirmDate", defaultValue: "Confirm date") }
    static var useSuggestedDate: String { String(localized: "blueprint.useSuggestedDate", defaultValue: "Use suggested date") }
    static var repeatedTime: String { String(localized: "blueprint.repeatedTime", defaultValue: "This time occurs twice when the clocks change. Choose which occurrence you mean.") }
    static var nonexistentTime: String { String(localized: "blueprint.nonexistentTime", defaultValue: "The suggested local time doesn’t exist because the clocks change. Choose another time.") }
    static var starter: String { String(localized: "blueprint.starter", defaultValue: "Use Blueprint") }
    static var title: String { String(localized: "blueprint.title", defaultValue: "Wedding") }
    static func defaultEventName(for name: String) -> String {
        String(format: String(localized: "blueprint.defaultEventName", defaultValue: "%@’s wedding"), name)
    }
    static var description: String {
        String(localized: "blueprint.description", defaultValue: "Start with a plan you can shape over time.")
    }
    static var mainEvent: String { String(localized: "blueprint.mainEvent", defaultValue: "Main event") }
    static var children: String { String(localized: "blueprint.children", defaultValue: "Events to Include") }
    static var ideas: String { String(localized: "blueprint.ideas", defaultValue: "Starter ideas") }
    static var review: String { String(localized: "blueprint.review", defaultValue: "Your Plan") }
    static var reviewing: String { String(localized: "blueprint.reviewing", defaultValue: "Getting blueprint ready…") }
    static var install: String { String(localized: "blueprint.install", defaultValue: "Create Event") }
    static var installing: String { String(localized: "blueprint.installing", defaultValue: "Creating…") }
    static var omitted: String { String(localized: "blueprint.omitted", defaultValue: "Not included") }
    static var childDateRequired: String {
        String(localized: "blueprint.childDateRequired", defaultValue: "Choose a date and time to include this event.")
    }
    static var chooseDate: String { String(localized: "blueprint.chooseDate", defaultValue: "Choose date and time") }
    static var dateTime: String { String(localized: "blueprint.dateTime", defaultValue: "Date and time") }
    static var timeZone: String { String(localized: "blueprint.timeZone", defaultValue: "Time zone") }
    static var useDeviceTimeZone: String { String(localized: "blueprint.useDeviceTimeZone", defaultValue: "Use Device Time Zone") }
    static var deviceTimeZoneHint: String { String(localized: "blueprint.deviceTimeZoneHint", defaultValue: "Starts with your device’s time zone. Choose another if the event is elsewhere. Location access isn’t needed.") }
    static var eventName: String { String(localized: "blueprint.eventName", defaultValue: "Event name") }
    static var eventType: String { String(localized: "blueprint.eventType", defaultValue: "Event type") }
    static var eventPurpose: String { String(localized: "blueprint.eventPurpose", defaultValue: "Purpose") }
    static var parentEvent: String { String(localized: "blueprint.parentEvent", defaultValue: "Parent event") }
    static var category: String { String(localized: "blueprint.category", defaultValue: "Category") }
    static var status: String { String(localized: "blueprint.status", defaultValue: "Status") }
    static var target: String { String(localized: "blueprint.target", defaultValue: "For") }
    static var configuration: String { String(localized: "blueprint.configuration", defaultValue: "Settings") }
    static var experienceType: String { String(localized: "blueprint.experienceType", defaultValue: "Experience type") }
    static var categoryOrder: String { String(localized: "blueprint.categoryOrder", defaultValue: "Category order") }
    static var planningSetup: String { String(localized: "blueprint.planningSetup", defaultValue: "Planning setup") }
    static var loadFailed: String { String(localized: "blueprint.loadFailed", defaultValue: "This blueprint isn’t available right now.") }
    static var clientUpgradeRequired: String {
        String(localized: "blueprint.clientUpgradeRequired", defaultValue: "Update Gatherory to continue. Your saved changes will be kept.")
    }
    static var workspaceNotInBootstrap: String {
        String(localized: "blueprint.workspaceNotInBootstrap", defaultValue: "Your event hasn’t finished loading. Try again.")
    }
    static var signInRequired: String { String(localized: "blueprint.signInRequired", defaultValue: "Sign in to use blueprints.") }
    static var retryInstall: String { String(localized: "blueprint.retryInstall", defaultValue: "Continue Creating Event") }
    static var retrySameRequest: String {
        String(localized: "blueprint.retrySameRequest", defaultValue: "Try Again")
    }
    static var pendingInstall: String { String(localized: "blueprint.pendingInstall", defaultValue: "Finish Creating Your Event") }
    static var finishPreviousInstall: String {
        String(localized: "blueprint.finishPreviousInstall", defaultValue: "Finish this event before starting another.")
    }
    static var nothingCreatedYet: String {
        String(localized: "blueprint.nothingCreatedYet", defaultValue: "Your event is created only when you choose Create Event.")
    }
    static var omissionReason: String { String(localized: "blueprint.omissionReason", defaultValue: "Reason") }
}
