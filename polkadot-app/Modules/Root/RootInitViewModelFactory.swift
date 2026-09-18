import UIKit

protocol RootInitViewModelMaking {
    func makeInitial() -> RootInitViewLayout.ViewModel
    func makeLoadingHint() -> RootInitViewLayout.ViewModel
    func makeFailure() -> RootInitViewLayout.ViewModel
}

final class RootInitViewModelFactory: RootInitViewModelMaking {
    func makeInitial() -> RootInitViewLayout.ViewModel {
        .loading(hint: nil)
    }

    func makeLoadingHint() -> RootInitViewLayout.ViewModel {
        .loading(hint: String(localized: .rootInitLoadingHint))
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
