import UIKit

protocol RootViewModelMaking {
    func makeInitial() -> RootViewLayout.ViewModel
    func makeLoadingHint() -> RootViewLayout.ViewModel
    func makeFailure() -> RootViewLayout.ViewModel
}

final class RootViewModelFactory: RootViewModelMaking {
    func makeInitial() -> RootViewLayout.ViewModel {
        .loading(hint: nil)
    }

    func makeLoadingHint() -> RootViewLayout.ViewModel {
        .loading(hint: String(localized: .rootInitLoadingHint))
    }

    func makeFailure() -> RootViewLayout.ViewModel {
        .failed(
            RootViewLayout.ViewModel.Issue(
                title: String(localized: .rootInitFailureTitle),
                subtitle: String(localized: .rootInitFailureSubtitle)
            )
        )
    }
}
