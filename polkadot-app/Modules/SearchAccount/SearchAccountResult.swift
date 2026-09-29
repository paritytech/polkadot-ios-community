import Foundation
import SubstrateSdk

struct SearchAccountResult {
    struct Contact {
        let username: String?
        let address: AccountAddress
    }

    let recent: [RecentContactModelWithUsername]
    let contacts: [Contact]
    let global: [Contact]
    let globalOutcome: AccountSearchGlobalOutcome

    init(
        recent: [RecentContactModelWithUsername],
        contacts: [Contact],
        global: [Contact],
        globalOutcome: AccountSearchGlobalOutcome = .loaded
    ) {
        self.recent = recent
        self.contacts = contacts
        self.global = global
        self.globalOutcome = globalOutcome
    }
}
