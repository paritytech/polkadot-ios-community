#if TESTNET_FEATURE
    import UIKit
    import UIKitExt

    protocol AppFactoryResetViewProtocol: ControllerBackedProtocol {}

    protocol AppFactoryResetPresenterProtocol: AnyObject {
        func actionStartOver()
        func actionDismiss()
    }

    protocol AppFactoryResetInteractorInputProtocol: AnyObject {
        func performReset()
    }

    protocol AppFactoryResetInteractorOutputProtocol: AnyObject {
        func didCompleteReset()
    }

    protocol AppFactoryResetWireframeProtocol: AnyObject {
        func navigateToFreshStart()
        func dismiss(from view: AppFactoryResetViewProtocol?)
    }
#endif
