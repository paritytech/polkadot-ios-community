import Coinage
import Foundation
import SubstrateSdk

/// Same rule as the transfer preview: spend at no privacy cost when possible, otherwise widen to the
/// gaining-privacy funds the strategy releases behind a confirmation. `nil` means the amount is not
/// reachable on any terms the strategy allows.
enum PaymentSpendScopeResolver {
    static func resolve(balance: CoinageBalance, amount: Balance) -> SpendScope? {
        if balance.availablePrivate >= amount {
            return .spendable
        }

        if balance.available >= amount {
            return .withConfirmation
        }

        return nil
    }
}
