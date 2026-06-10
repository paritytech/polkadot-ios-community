import UIKitExt

protocol SelectTokenViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModels: [SelectTokenCellViewModel])
}

protocol SelectTokenPresenterProtocol: AnyObject {
    func setup()
    func select(viewModel: SelectTokenCellViewModel)
}

protocol SelectTokenInteractorInputProtocol: TokensInputProtocol {}

protocol SelectTokenInteractorOutputProtocol: TokensOutputProtocol {}

protocol SelectTokenWireframeProtocol: AnyObject {
    func proceed(from view: SelectTokenViewProtocol?, chainAsset: ChainAsset)
    func proceedToFiatOnRamp(from view: SelectTokenViewProtocol?)
}
