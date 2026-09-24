import DesignSystem
import Operation_iOS
import Products
import SwiftUI
import UIKit
import UIKitExt

final class DebugSettingsWireframe: DebugSettingsWireframeProtocol {
    private let flowStateProvider: any SPAFlowStateProviding

    init(flowStateProvider: any SPAFlowStateProviding) {
        self.flowStateProvider = flowStateProvider
    }

    func showProducts(from view: ControllerBackedProtocol?) {
        let factory = ProductRepositoryFactory()

        let viewModel = DebugProductsViewModel(
            productRepository: factory.createRepository(),
            chatRepositoryFactory: ChatRepositoryFactory()
        )

        let productsView = DebugProductsListView(viewModel: viewModel)
        let hostingController = UIHostingController(rootView: productsView)

        view?.controller.navigationController?.pushViewController(hostingController, animated: true)
    }

    func showThemeSelection(from view: ControllerBackedProtocol?) {
        let themeView = DebugThemeSelectionView(
            themeManager: ThemeManager.shared,
            typographyManager: TypographyManager.shared
        )
        let hostingController = UIHostingController(rootView: themeView)
        hostingController.title = "Theme Selection"

        view?.controller.navigationController?.pushViewController(hostingController, animated: true)
    }

    func showTrUAPIPlayground(from view: ControllerBackedProtocol?) {
        #if DEBUG
            guard let playgroundView = TrUAPIPlaygroundViewFactory.createView(
                flowStateProvider: flowStateProvider
            ) else {
                return
            }

            let navigationController = AppNavigationController(
                rootViewController: playgroundView.controller
            )
            navigationController.modalPresentationStyle = .fullScreen

            view?.controller.present(navigationController, animated: true)
        #endif
    }

    func showDotNsBrowser(from view: ControllerBackedProtocol?) {
        let alert = UIAlertController(
            title: "Open SPA",
            message: "Enter a dotns name to open",
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.placeholder = "browse.dot"
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Open", style: .default) { [weak view, weak self] _ in
            guard
                let input = alert.textFields?.first?.text,
                let self
            else {
                return
            }

            let flowState = flowStateProvider.flowState()

            Task {
                guard
                    let productHost = try? await flowState.hostProvider.resolveHost(rawString: input),
                    let spaView = SPAViewFactory.createView(
                        page: ProductPage(host: productHost),
                        flowState: flowState
                    )
                else {
                    return
                }

                await MainActor.run {
                    view?.controller.navigationController?.pushViewController(
                        spaView.controller,
                        animated: true
                    )
                }
            }
        })

        view?.controller.present(alert, animated: true)
    }

    func showDevServer(from view: ControllerBackedProtocol?) {
        let alert = UIAlertController(
            title: "Open dev server",
            message: "Enter the address of a local development server",
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.placeholder = "localhost:3000"
            textField.keyboardType = .URL
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Open", style: .default) { [weak view, weak self] _ in
            guard
                let input = alert.textFields?.first?.text,
                let self
            else {
                return
            }

            // Rejecting here keeps a mistyped public address from ever reaching the host API.
            guard
                let origin = LocalDevOrigin.parseOrigin(input),
                let url = URL(string: origin)
            else {
                present(
                    message: "Not a local development address: \(input)",
                    title: "Cannot open",
                    closeAction: "Close",
                    from: view
                )
                return
            }

            let flowState = flowStateProvider.flowState()
            let label = LocalDevOrigin.productLabel(forOrigin: origin)

            Task {
                guard
                    let productHost = try? await flowState.hostProvider.resolveHost(label: label),
                    let spaView = SPAViewFactory.createView(
                        configuration: SPAConfiguration(
                            title: origin,
                            isRootScreen: false,
                            showMoreButton: true,
                            page: ProductPage(host: productHost),
                            contentSource: .directURL(url)
                        ),
                        flowState: flowState
                    )
                else {
                    return
                }

                await MainActor.run {
                    view?.controller.navigationController?.pushViewController(
                        spaView.controller,
                        animated: true
                    )
                }
            }
        })

        view?.controller.present(alert, animated: true)
    }
}
