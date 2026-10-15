import Foundation

enum BlueprintCopy {
    static var sharedLinkUnavailable: String { String(localized: "blueprint.sharedLinkUnavailable", defaultValue: "This template link is no longer available. Ask the person who shared it for a new link.") }
    static var saveAsTemplate: String { String(localized: "blueprint.saveAsTemplate", defaultValue: "Save as Template") }
    static var captureOnWebHint: String { String(localized: "blueprint.captureOnWebHint", defaultValue: "Choose what to reuse and publish on the web.") }
    static var shareTemplate: String { String(localized: "blueprint.shareTemplate", defaultValue: "Share Template") }
    static var manageTemplateLinks: String { String(localized: "blueprint.manageTemplateLinks", defaultValue: "Manage Links") }
    static var templateLinksUnavailable: String { String(localized: "blueprint.templateLinksUnavailable", defaultValue: "Template Links Unavailable") }
    static var lostTemplatePermission: String { String(localized: "blueprint.lostTemplatePermission", defaultValue: "You no longer have permission to manage templates for this event.") }
    static var templateLinkSignIn: String { String(localized: "blueprint.templateLinkSignIn", defaultValue: "Sign in to manage template links.") }
    static var shareTemplateExplanation: String { String(localized: "blueprint.shareTemplateExplanation", defaultValue: "Anyone with this link can install an independent copy of the template. It does not invite them to this event.") }
    static var noCapturedTemplates: String { String(localized: "blueprint.noCapturedTemplates", defaultValue: "No templates have been captured from this event yet.") }
    static var captureBeforeSharing: String { String(localized: "blueprint.captureBeforeSharing", defaultValue: "Create a template from this event here, or open the web editor for advanced authoring.") }
    static var createTemplateTitle: String { String(localized: "blueprint.createTemplateTitle", defaultValue: "Create Template") }
    static var templateCaptureExplanation: String { String(localized: "blueprint.templateCaptureExplanation", defaultValue: "Choose the event details to reuse. Nothing is created until you review and share.") }
    static var sourceEvent: String { String(localized: "blueprint.sourceEvent", defaultValue: "Source Event") }
    static var templateName: String { String(localized: "blueprint.templateName", defaultValue: "Template name") }
    static var templateDetails: String { String(localized: "blueprint.templateDetails", defaultValue: "Template Details") }
    static var captureChildren: String { String(localized: "blueprint.captureChildren", defaultValue: "Sub-events") }
    static var captureIdeas: String { String(localized: "blueprint.captureIdeas", defaultValue: "Ideas") }
    static var captureGuidance: String { String(localized: "blueprint.captureGuidance", defaultValue: "Guidance") }
    static var includeIdeaNotes: String { String(localized: "blueprint.includeIdeaNotes", defaultValue: "Include idea notes") }
    static var sourceDatesNotCopied: String { String(localized: "blueprint.sourceDatesNotCopied", defaultValue: "Dates from the source event aren’t copied.") }
    static var scheduleProposalExplanation: String { String(localized: "blueprint.scheduleProposalExplanation", defaultValue: "Suggested time %@ · %lld days from the main event") }
    static var templatePrivacyExplanation: String { String(localized: "blueprint.templatePrivacyExplanation", defaultValue: "Only the selected text is copied. Guest lists, RSVPs, chats, expenses, photos, and music aren’t included.") }
    static var searchPublication: String { String(localized: "blueprint.searchPublication", defaultValue: "Search Publication") }
    static var templateSearchPublicationExplanation: String { String(localized: "blueprint.templateSearchPublicationExplanation", defaultValue: "Publishing adds this template to Search, where people can find it and install independent copies. The source event stays private; only the content you selected is published.") }
    static var reviewTemplate: String { String(localized: "blueprint.reviewTemplate", defaultValue: "Review") }
    static var editTemplate: String { String(localized: "blueprint.editTemplate", defaultValue: "Edit") }
    static var preparingTemplateReview: String { String(localized: "blueprint.preparingTemplateReview", defaultValue: "Preparing review…") }
    static var templateCreationLoadFailed: String { String(localized: "blueprint.templateCreationLoadFailed", defaultValue: "Couldn’t load event details. Check your connection and try again.") }
    static var templateCreationReviewFailed: String { String(localized: "blueprint.templateCreationReviewFailed", defaultValue: "Couldn’t prepare the template review. Try again.") }
    static var templateCreationUncertain: String { String(localized: "blueprint.templateCreationUncertain", defaultValue: "The template may already have been created. Retry to recover the same template.") }
    static var templateCreationLinkUncertain: String { String(localized: "blueprint.templateCreationLinkUncertain", defaultValue: "Your template is ready, but the link may have been created. Refresh links before trying again.") }
    static var templateCreationPermissionLost: String { String(localized: "blueprint.templateCreationPermissionLost", defaultValue: "You no longer have permission to create a template from this event.") }
    static var templateCreationInvalidResponse: String { String(localized: "blueprint.templateCreationInvalidResponse", defaultValue: "The server returned an unexpected template response. Try refreshing the event.") }
    static var templateCreationSourceChanged: String { String(localized: "blueprint.templateCreationSourceChanged", defaultValue: "This event changed. Reload it and review your selections again.") }
    static var reloadEvent: String { String(localized: "blueprint.reloadEvent", defaultValue: "Reload Event") }
    static var publishToSearch: String { String(localized: "blueprint.publishToSearch", defaultValue: "Publish to Search") }
    static var creatingTemplate: String { String(localized: "blueprint.creatingTemplate", defaultValue: "Creating template…") }
    static var templateReady: String { String(localized: "blueprint.templateReady", defaultValue: "Template Ready") }
    static var templateListedExplanation: String { String(localized: "blueprint.templateListedExplanation", defaultValue: "This template is published in Search. People can find it and install independent copies.") }
    static var independentTemplateCopies: String { String(localized: "blueprint.independentTemplateCopies", defaultValue: "Each person gets an independent copy. Sharing the link doesn’t invite anyone to the source event.") }
    static var beforeYouShare: String { String(localized: "blueprint.beforeYouShare", defaultValue: "Before You Share") }
    static var guidanceAudience: String { String(localized: "blueprint.guidanceAudience", defaultValue: "For %@") }
    static var audienceEventParticipants: String { String(localized: "blueprint.audienceEventParticipants", defaultValue: "For event participants") }
    static var audiencePlanningOnly: String { String(localized: "blueprint.audiencePlanningOnly", defaultValue: "For planners only") }
    static var selectedTextMayBePersonal: String { String(localized: "blueprint.selectedTextMayBePersonal", defaultValue: "Selected text may include personal details. Review it before sharing.") }
    static var refreshLinks: String { String(localized: "blueprint.refreshLinks", defaultValue: "Refresh Links") }
    static var retryCreateShareLink: String { String(localized: "blueprint.retryCreateShareLink", defaultValue: "Create a New Share Link") }
    static var createdLinks: String { String(localized: "blueprint.createdLinks", defaultValue: "Created Links") }
    static var noPublishedTemplate: String { String(localized: "blueprint.noPublishedTemplate", defaultValue: "This template is not published yet. Open the web editor to review and publish it.") }
    static var chooseTemplateHint: String { String(localized: "blueprint.chooseTemplateHint", defaultValue: "Choose one of the templates captured from this event.") }
    static var openTemplateEditor: String { String(localized: "blueprint.openTemplateEditor", defaultValue: "Open Web Editor") }
    static var chooseTemplate: String { String(localized: "blueprint.chooseTemplate", defaultValue: "Template") }
    static var publishedRevision: String { String(localized: "blueprint.publishedRevision", defaultValue: "Published version %lld") }
    static var retiredTemplate: String { String(localized: "blueprint.retiredTemplate", defaultValue: "Retired") }
    static var draftTemplate: String { String(localized: "blueprint.draftTemplate", defaultValue: "Draft · Not published") }
    static var retiredCannotShare: String { String(localized: "blueprint.retiredCannotShare", defaultValue: "This template is retired. Existing links can still be reviewed and revoked in Manage Links.") }
    static var createShareLink: String { String(localized: "blueprint.createShareLink", defaultValue: "Create Share Link") }
    static var creatingShareLink: String { String(localized: "blueprint.creatingShareLink", defaultValue: "Creating link…") }
    static var shareNewLink: String { String(localized: "blueprint.shareNewLink", defaultValue: "Share New Link") }
    static var newLinkReady: String { String(localized: "blueprint.newLinkReady", defaultValue: "This new link is shown only while this screen is open. Share or save it now.") }
    static var noLinksCreated: String { String(localized: "blueprint.noLinksCreated", defaultValue: "No links have been created for this template.") }
    static var noLinksCreatedHint: String { String(localized: "blueprint.noLinksCreatedHint", defaultValue: "Create a link when you’re ready to share this published version.") }
    static var existingLinksCannotBeRecovered: String { String(localized: "blueprint.existingLinksCannotBeRecovered", defaultValue: "Previously created URLs can’t be recovered. Create a replacement link if you no longer have one.") }
    static var activeShareLink: String { String(localized: "blueprint.activeShareLink", defaultValue: "Active") }
    static var revokedShareLink: String { String(localized: "blueprint.revokedShareLink", defaultValue: "Revoked") }
    static var revokeShareLink: String { String(localized: "blueprint.revokeShareLink", defaultValue: "Revoke Link") }
    static var confirmRevokeTitle: String { String(localized: "blueprint.confirmRevokeTitle", defaultValue: "Revoke This Link?") }
    static var confirmRevokeMessage: String { String(localized: "blueprint.confirmRevokeMessage", defaultValue: "People can no longer use this link to install the template. Existing copies are not affected.") }
    static var revoke: String { String(localized: "blueprint.revoke", defaultValue: "Revoke") }
    static var shareLinksLoadFailed: String { String(localized: "blueprint.shareLinksLoadFailed", defaultValue: "Couldn’t load template links. Check your connection and try again.") }
    static var shareLinkChangeFailed: String { String(localized: "blueprint.shareLinkChangeFailed", defaultValue: "The link could not be changed. Check your connection and try again.") }
    static var shareLinkCreationUncertain: String { String(localized: "blueprint.shareLinkCreationUncertain", defaultValue: "The request may have created a link, but its one-time URL wasn’t received. Refresh the list before trying again.") }
    static var shareLinkOffline: String { String(localized: "blueprint.shareLinkOffline", defaultValue: "Creating and revoking links requires a connection. No change was queued.") }
    static var listedInSearch: String { String(localized: "blueprint.listedInSearch", defaultValue: "Listed in Search") }
    static var notListedInSearch: String { String(localized: "blueprint.notListedInSearch", defaultValue: "Not listed in Search") }
    static var listInSearch: String { String(localized: "blueprint.listInSearch", defaultValue: "List in Search") }
    static var removeFromSearch: String { String(localized: "blueprint.removeFromSearch", defaultValue: "Remove from Search") }
    static var confirmListInSearchTitle: String { String(localized: "blueprint.confirmListInSearchTitle", defaultValue: "List This Template in Search?") }
    static var confirmListInSearchMessage: String { String(localized: "blueprint.confirmListInSearchMessage", defaultValue: "People will be able to find this published version and install independent copies.") }
    static var confirmRemoveFromSearchTitle: String { String(localized: "blueprint.confirmRemoveFromSearchTitle", defaultValue: "Remove This Template from Search?") }
    static var confirmRemoveFromSearchMessage: String { String(localized: "blueprint.confirmRemoveFromSearchMessage", defaultValue: "This hides the template from Search. Existing share links stay active, and installed copies are unchanged.") }
    static var listingDoesNotChangeLinks: String { String(localized: "blueprint.listingDoesNotChangeLinks", defaultValue: "Search visibility is separate from share links. Revoking a link doesn’t remove this template from Search, and removing it from Search doesn’t revoke links or affect existing copies.") }
    static var retry: String { String(localized: "blueprint.retry", defaultValue: "Try Again") }
    static var resumeSetup: String { String(localized: "blueprint.resumeSetup", defaultValue: "Resume setup") }
    static var startOver: String { String(localized: "blueprint.startOver", defaultValue: "Start over") }
    static var startOverConfirmation: String { String(localized: "blueprint.startOverConfirmation", defaultValue: "Discard this saved setup and start again with the latest template?") }
    static var draftSaveFailed: String { String(localized: "blueprint.draftSaveFailed", defaultValue: "Couldn’t save your setup on this device. Try again before closing.") }
    static var draftLoadFailed: String { String(localized: "blueprint.draftLoadFailed", defaultValue: "Couldn’t open saved setups on this device. Try refreshing.") }
    static var suggestionConfirmation: String { String(localized: "blueprint.suggestionConfirmation", defaultValue: "Suggested dates use the main event’s calendar date and time zone. Confirm each date before including a sub-event.") }
    static var datesKept: String { String(localized: "blueprint.datesKept", defaultValue: "Your confirmed dates have been kept. Changing the time zone changes how they are displayed, not when they happen.") }
    static var loadingDates: String { String(localized: "blueprint.loadingDates", defaultValue: "Finding suggested dates…") }
    static var datesUnavailable: String { String(localized: "blueprint.datesUnavailable", defaultValue: "Suggested dates aren’t available. You can still choose dates manually.") }
    static var confirmedDate: String { String(localized: "blueprint.confirmedDate", defaultValue: "Confirmed date") }
    static var confirmDate: String { String(localized: "blueprint.confirmDate", defaultValue: "Confirm date") }
    static var useSuggestedDate: String { String(localized: "blueprint.useSuggestedDate", defaultValue: "Use suggested date") }
    static var repeatedTime: String { String(localized: "blueprint.repeatedTime", defaultValue: "This time occurs twice when the clocks change. Choose which occurrence you mean.") }
    static var nonexistentTime: String { String(localized: "blueprint.nonexistentTime", defaultValue: "The suggested local time doesn’t exist because the clocks change. Choose another time.") }
    static var starter: String { String(localized: "blueprint.starter", defaultValue: "Use Template") }
    static var title: String { String(localized: "blueprint.title", defaultValue: "Wedding") }
    static func defaultEventName(for name: String) -> String {
        String(format: String(localized: "blueprint.defaultEventName", defaultValue: "%@’s wedding"), name)
    }
    static var description: String {
        String(localized: "blueprint.description", defaultValue: "Start with a plan you can shape over time.")
    }
    static var mainEvent: String { String(localized: "blueprint.mainEvent", defaultValue: "Main event") }
    static var children: String { String(localized: "blueprint.children", defaultValue: "Optional sub-events") }
    static var ideas: String { String(localized: "blueprint.ideas", defaultValue: "Starter ideas") }
    static var review: String { String(localized: "blueprint.review", defaultValue: "Review plan") }
    static var reviewing: String { String(localized: "blueprint.reviewing", defaultValue: "Preparing review…") }
    static var install: String { String(localized: "blueprint.install", defaultValue: "Create event plan") }
    static var installing: String { String(localized: "blueprint.installing", defaultValue: "Creating…") }
    static var omitted: String { String(localized: "blueprint.omitted", defaultValue: "Not included") }
    static var childDateRequired: String {
        String(localized: "blueprint.childDateRequired", defaultValue: "Choose a date and time to include this sub-event.")
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
    static var configuration: String { String(localized: "blueprint.configuration", defaultValue: "Configuration") }
    static var experienceType: String { String(localized: "blueprint.experienceType", defaultValue: "Experience type") }
    static var categoryOrder: String { String(localized: "blueprint.categoryOrder", defaultValue: "Category order") }
    static var planningSetup: String { String(localized: "blueprint.planningSetup", defaultValue: "Planning setup") }
    static var loadFailed: String { String(localized: "blueprint.loadFailed", defaultValue: "This blueprint isn’t available right now.") }
    static var clientUpgradeRequired: String {
        String(localized: "blueprint.clientUpgradeRequired", defaultValue: "Update Gatherory to sync this blueprint. Your pending changes remain saved and will retry after updating.")
    }
    static var workspaceNotInBootstrap: String {
        String(localized: "blueprint.workspaceNotInBootstrap", defaultValue: "The installed event is still being prepared. Retry to finish syncing it to this device.")
    }
    static var signInRequired: String { String(localized: "blueprint.signInRequired", defaultValue: "Sign in to use blueprints.") }
    static var retryInstall: String { String(localized: "blueprint.retryInstall", defaultValue: "Resume installation") }
    static var retrySameRequest: String {
        String(localized: "blueprint.retrySameRequest", defaultValue: "Retry this exact request")
    }
    static var pendingInstall: String { String(localized: "blueprint.pendingInstall", defaultValue: "An installation is waiting to finish") }
    static var finishPreviousInstall: String {
        String(localized: "blueprint.finishPreviousInstall", defaultValue: "Finish the previous creation before starting another. Its request is kept for a safe retry.")
    }
    static var nothingCreatedYet: String {
        String(localized: "blueprint.nothingCreatedYet", defaultValue: "Review is only a preview. Nothing is created or approved until you install the plan.")
    }
    static var omissionReason: String { String(localized: "blueprint.omissionReason", defaultValue: "Reason") }
}
