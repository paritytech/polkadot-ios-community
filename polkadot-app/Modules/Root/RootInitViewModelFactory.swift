import UIKit

protocol RootInitViewModelMaking {
    func makeInitial() -> RootInitViewLayout.ViewModel
    func makeWaitingForNetwork() -> RootInitViewLayout.ViewModel
    func makeFailure() -> RootInitViewLayout.ViewModel
}

final class RootInitViewModelFactory: RootInitViewModelMaking {
    func makeInitial() -> RootInitViewLayout.ViewModel {
        .loading(hint: nil)
    }

    func makeWaitingForNetwork() -> RootInitViewLayout.ViewModel {
        .loading(hint: String(localized: .rootInitWaitingSubtitle))
    }

    func makeFailure() -> RootInitViewLayout.ViewModel {
        .failed(
            RootInitViewLayout.ViewModel.Issue(
                title: String(localized: .rootInitFailureTitle),
                subtitle: String(localized: .rootInitFailureSubtitle)
            )
        )
    }
}
