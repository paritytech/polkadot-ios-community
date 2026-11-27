import SubstrateSdk

/// Records the amounts an auto-approval confirmation hook receives.
actor MockAutoApprovalConfirmation {
    private(set) var amounts: [Balance] = []

    func record(_ amount: Balance) {
        amounts.append(amount)
    }
}
