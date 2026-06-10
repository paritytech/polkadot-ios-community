import Foundation

struct SelectedCurrencyChanged: EventProtocol {
    func accept(visitor: EventVisitorProtocol) {
        visitor.processSelectedCurrencyChanged(event: self)
    }
}
