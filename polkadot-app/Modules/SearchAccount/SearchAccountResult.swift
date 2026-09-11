import Foundation
import SubstrateSdk

struct SearchAccountResult {
    struct Contact {
        let username: String?
        let address: AccountAddress
    }

    enum LoaderChange {
        case unchanged
        case start
        case stop
    }

    let query: String?
    let loader: LoaderChange
    let recent: [RecentContactModelWithUsername]
    let contacts: [Contact]
    let global: [Contact]
}
