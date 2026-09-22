import UIKit

protocol RootViewModelMaking {
    func makeInitial() -> RootViewLayout.ViewModel
    func makeLoadingHint() -> RootViewLayout.ViewModel
    func makeFailure(kind: RootSetupFailureKind) -> RootViewLayout.ViewModel
}

final class RootViewModelFactory: RootViewModelMaking {
    func makeInitial() -> RootViewLayout.ViewModel {
        .loading(hint: nil)
    }

    func makeLoadingHint() -> RootViewLayout.ViewModel {
        .loading(hint: String(localized: .rootInitLoadingHint))
    }

    func makeFailure(kind: RootSetupFailureKind) -> RootViewLayout.ViewModel {
        switch kind {
        case .connectivity:
            makeConnectivityIssue()
        case .unknown:
            makeUnknownIssue()
        }
    }
}

private extension RootViewModelFactory {
    func makeConnectivityIssue() -> RootViewLayout.ViewModel {
        .failed(
            RootViewLayout.ViewModel.Issue(
                title: String(localized: .rootInitFailureConnectivityTitle),
                subtitle: String(localized: .rootInitFailureConnectivitySubtitle),
                actionTitle: nil
            )
        )
    }

    func makeUnknownIssue() -> RootViewLayout.ViewModel {
        .failed(
            RootViewLayout.ViewModel.Issue(
                title: String(localized: .rootInitFailureUnknownTitle),
                subtitle: String(localized: .rootInitFailureUnknownSubtitle),
                actionTitle: String(localized: .rootInitFailureAction)
            )
        )
    }
}
