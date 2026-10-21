import Foundation
import Testing
@testable import Gatherory

@MainActor
struct SessionPreparationCoordinatorTests {
    @Test("Account preparation opens invitations before enabling notification callbacks")
    func accountOrder() async {
        let coordinator = SessionPreparationCoordinator()
        let request = accountRequest("account-a")
        let services = PreparationTestServices()
        services.onBind = { #expect(coordinator.isReady(for: request.identity)) }

        await coordinator.prepare(request, using: services, isCurrent: { true })

        #expect(services.calls == ["detach", "planning", "finish", "invitations", "bind"])
        #expect(coordinator.phase == .ready(request.identity))
    }

    @Test("Guest attendance prepares its guest namespace without activating account invitations")
    func guestOrder() async {
        let coordinator = SessionPreparationCoordinator()
        let request = SessionPreparationRequest(account: nil, guestProfile: LocalGuestProfile(displayName: "Morgan"))
        let services = PreparationTestServices()

        await coordinator.prepare(request, using: services, isCurrent: { true })

        #expect(services.calls == ["detach", "planning", "finish", "guest", "bind"])
        #expect(coordinator.phase == .ready(request.identity))
    }

    @Test("Signing in transfers guest data before account invitations and notification binding")
    func guestTransferOrder() async {
        let coordinator = SessionPreparationCoordinator()
        let request = accountRequest("account-a", guest: LocalGuestProfile(displayName: "Morgan"))
        let services = PreparationTestServices()

        await coordinator.prepare(request, using: services, isCurrent: { true })

        #expect(services.calls == ["detach", "planning", "finish", "transfer", "cleanup", "invitations", "bind"])
        #expect(services.didCleanUpGuest)
        #expect(coordinator.phase == .ready(request.identity))
    }

    @Test("A failed planning activation never exposes ready state or binds notifications")
    func planningFailure() async {
        let coordinator = SessionPreparationCoordinator()
        let request = accountRequest("account-a")
        let services = PreparationTestServices()
        services.finishFailure = PreparationTestFailure.unavailable

        await coordinator.prepare(request, using: services, isCurrent: { true })

        #expect(services.calls == ["detach", "planning", "finish"])
        #expect(coordinator.phase == .recovery(request.identity, .retry))
        #expect(!coordinator.isReady(for: request.identity))
    }

    @Test("A guest import receipt for another account requires the original account")
    func wrongAccountGuestTransfer() async {
        let coordinator = SessionPreparationCoordinator()
        let request = accountRequest("wrong-account", guest: LocalGuestProfile(displayName: "Morgan"))
        let services = PreparationTestServices()
        services.guestFailure = LocalGuestWorkspacePersistenceError.guestAlreadyImportedIntoDifferentAccount

        await coordinator.prepare(request, using: services, isCurrent: { true })

        #expect(services.calls == ["detach", "planning", "finish", "transfer"])
        #expect(coordinator.recovery(for: request.identity) == .originalAccountRequired)
        #expect(coordinator.recovery(for: .account("different-account")) == nil)
        #expect(!services.didCleanUpGuest)
        #expect(!coordinator.isReady(for: request.identity))
    }

    @Test("A retained guest source already imported into an account cannot resume editing")
    func partialGuestTransferRequiresOriginalAccount() async {
        let coordinator = SessionPreparationCoordinator()
        let request = SessionPreparationRequest(account: nil, guestProfile: LocalGuestProfile(displayName: "Morgan"))
        let services = PreparationTestServices()
        services.guestFailure = LocalGuestWorkspacePersistenceError.guestAlreadyImportedIntoDifferentAccount

        await coordinator.prepare(request, using: services, isCurrent: { true })

        #expect(services.calls == ["detach", "planning", "finish", "guest"])
        #expect(coordinator.phase == .recovery(request.identity, .originalAccountRequired))
    }

    @Test("Cancellation during notification detachment stops before changing the planning scope")
    func cancelledDuringDetach() async {
        let coordinator = SessionPreparationCoordinator()
        let services = PreparationTestServices()
        let gate = PreparationTestGate()
        services.detachGate = gate
        let request = accountRequest("account-a")
        let preparation = Task {
            await coordinator.prepare(request, using: services, isCurrent: { true })
        }
        await gate.waitUntilSuspended()
        preparation.cancel()
        gate.resume()
        await preparation.value

        #expect(services.calls == ["detach"])
        #expect(coordinator.phase == .idle)
    }

    @Test("Returning from an old A invitation activation cannot overwrite a newer A after A to B to A")
    func staleInvitationCompletionAcrossAccountRoundTrip() async {
        let coordinator = SessionPreparationCoordinator()
        let firstA = PreparationTestServices()
        let gate = PreparationTestGate()
        firstA.invitationGate = gate
        let requestA = accountRequest("account-a")
        let requestB = accountRequest("account-b")
        let oldPreparation = Task {
            await coordinator.prepare(requestA, using: firstA, isCurrent: { true })
        }
        await gate.waitUntilSuspended()

        let servicesB = PreparationTestServices()
        await coordinator.prepare(requestB, using: servicesB, isCurrent: { true })
        let newestA = PreparationTestServices()
        await coordinator.prepare(requestA, using: newestA, isCurrent: { true })
        #expect(coordinator.phase == .ready(requestA.identity))

        gate.resume()
        await oldPreparation.value

        #expect(firstA.calls == ["detach", "planning", "finish", "invitations"])
        #expect(newestA.calls.last == "bind")
        #expect(coordinator.phase == .ready(requestA.identity))
    }

    @Test("Cancellation after a durable guest copy preserves the source before cleanup")
    func transferValidationPreventsCancelledCleanup() async {
        let coordinator = SessionPreparationCoordinator()
        let services = PreparationTestServices()
        let gate = PreparationTestGate()
        services.transferGate = gate
        let request = accountRequest("account-a", guest: LocalGuestProfile(displayName: "Morgan"))
        let preparation = Task {
            await coordinator.prepare(request, using: services, isCurrent: { true })
        }
        await gate.waitUntilSuspended()
        preparation.cancel()
        gate.resume()
        await preparation.value

        #expect(services.calls == ["detach", "planning", "finish", "transfer"])
        #expect(services.didCopyGuest)
        #expect(!services.didCleanUpGuest)
        #expect(coordinator.phase == .idle)
    }

    @Test("A changed identity stops a durable guest transfer even before another preparation starts")
    func transferValidationChecksCurrentIdentity() async {
        let coordinator = SessionPreparationCoordinator()
        let services = PreparationTestServices()
        let gate = PreparationTestGate()
        services.transferGate = gate
        let request = accountRequest("account-a", guest: LocalGuestProfile(displayName: "Morgan"))
        var current = true
        let preparation = Task {
            await coordinator.prepare(request, using: services, isCurrent: { current })
        }
        await gate.waitUntilSuspended()
        current = false
        gate.resume()
        await preparation.value

        #expect(services.didCopyGuest)
        #expect(!services.didCleanUpGuest)
        #expect(!services.calls.contains("bind"))
        #expect(coordinator.phase == .idle)
    }

    private func accountRequest(_ id: String, guest: LocalGuestProfile? = nil) -> SessionPreparationRequest {
        SessionPreparationRequest(account: UserAccount(
            id: id,
            email: "\(id)@example.test",
            displayName: id,
            role: .planner,
            authenticationProvider: .password,
            createdAt: Date(timeIntervalSince1970: 0)
        ), guestProfile: guest)
    }
}

private enum PreparationTestFailure: Error { case unavailable }

@MainActor
private final class PreparationTestServices: SessionPreparationServices {
    var calls: [String] = []
    var finishFailure: (any Error)?
    var guestFailure: (any Error)?
    var detachGate: PreparationTestGate?
    var invitationGate: PreparationTestGate?
    var transferGate: PreparationTestGate?
    var onBind: (() -> Void)?
    var didCopyGuest = false
    var didCleanUpGuest = false

    func detachNotifications() async {
        calls.append("detach")
        await detachGate?.suspend()
    }

    func activatePlanning(for request: SessionPreparationRequest) async { calls.append("planning") }

    func finishPlanningActivation(for request: SessionPreparationRequest) throws {
        calls.append("finish")
        if let finishFailure { throw finishFailure }
    }

    func activateGuest(_ profile: LocalGuestProfile) async throws {
        calls.append("guest")
        if let guestFailure { throw guestFailure }
    }

    func transferGuest(_ profile: LocalGuestProfile, into account: UserAccount,
                       validate: @MainActor () throws -> Void) async throws {
        calls.append("transfer")
        try validate()
        if let guestFailure { throw guestFailure }
        didCopyGuest = true
        await transferGate?.suspend()
        try validate()
        calls.append("cleanup")
        didCleanUpGuest = true
    }

    func activateAccountInvitations(_ account: UserAccount?) async {
        calls.append("invitations")
        await invitationGate?.suspend()
    }

    func bindNotifications() async {
        calls.append("bind")
        onBind?()
    }
}

@MainActor
private final class PreparationTestGate {
    private var suspended = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func suspend() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            suspended = true
            started?.resume()
            started = nil
        }
    }

    func waitUntilSuspended() async {
        guard !suspended else { return }
        await withCheckedContinuation { started = $0 }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
