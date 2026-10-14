import Foundation

/// Pure allocation rules. The workspace owns account lookup, permissions, and
/// synchronous application of these outcomes; no budget state is retained here.
nonisolated struct WorkspaceBudgetRules {
    enum CapChange: Equatable {
        case disable
        case start(Decimal)
        case resize(Decimal)
    }

    struct InitialFunding: Equatable {
        let poolContribution: Decimal
        let mainContribution: Decimal
    }

    struct Transfer: Equatable {
        let sourceBalance: Decimal
        let destinationBalance: Decimal
    }

    static func normalizedCurrencyCode(_ code: String) -> String {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.count == 3 ? normalized : "USD"
    }

    static func initialMainAllocation(
        explicitAllocation: Decimal?,
        workspaceCap: Decimal?,
        childAllocations: [Decimal?]
    ) -> Decimal? {
        if let explicitAllocation { return explicitAllocation }
        return workspaceCap.map {
            max(.zero, $0 - childAllocations.compactMap { $0 }.reduce(Decimal.zero, +))
        }
    }

    static func allocatedTotal(mainAllocation: Decimal?, childAllocations: [Decimal?]) -> Decimal {
        (mainAllocation ?? .zero) + childAllocations.compactMap { $0 }.reduce(Decimal.zero, +)
    }

    static func remaining(cap: Decimal?, cost: Decimal) -> Decimal? {
        cap.map { $0 - cost }
    }

    static func freePool(workspaceCap: Decimal?, allocatedTotal: Decimal) -> Decimal {
        guard let workspaceCap else { return .zero }
        return max(.zero, workspaceCap - allocatedTotal)
    }

    static func capChange(
        to newCap: Decimal?,
        currentCap: Decimal?,
        allocatedTotal: Decimal
    ) -> CapChange? {
        guard let newCap else { return .disable }
        guard newCap >= .zero else { return nil }
        guard currentCap != nil else { return .start(newCap) }
        guard newCap >= allocatedTotal else { return nil }
        return .resize(newCap)
    }

    /// Editors can opt into/out of budgeting, but allocation changes must use
    /// transfers. New events pass nil for their previous allocation.
    static func childAllocation(
        workspaceCap: Decimal?,
        previousAllocation: Decimal?,
        requestedAllocation: Decimal?
    ) -> Decimal? {
        guard workspaceCap != nil, requestedAllocation != nil else { return nil }
        return previousAllocation ?? .zero
    }

    static func initialFunding(
        amount: Decimal?,
        freePool: Decimal,
        mainAllocation: Decimal?
    ) -> InitialFunding? {
        guard let amount, amount > .zero else { return nil }
        let poolContribution = min(freePool, amount)
        let mainContribution = amount - poolContribution
        guard (mainAllocation ?? .zero) >= mainContribution else { return nil }
        return InitialFunding(poolContribution: poolContribution, mainContribution: mainContribution)
    }

    /// Callers resolve distinct, enabled accounts before applying a transfer.
    static func transfer(
        amount: Decimal,
        sourceBalance: Decimal?,
        destinationBalance: Decimal?
    ) -> Transfer? {
        guard amount > .zero,
              let sourceBalance, sourceBalance >= amount,
              let destinationBalance else { return nil }
        return Transfer(sourceBalance: sourceBalance - amount, destinationBalance: destinationBalance + amount)
    }
}
