import NovaCrypto
import UIKitExt

protocol SecretPhraseMnemonicViewProtocol: ControllerBackedProtocol {
    func updateViewModel(_ viewModel: SecretPhraseMnemonicViewModel)
    func showMnemonic(_ show: Bool)
}

protocol SecretPhraseMnemonicPresenterProtocol: AnyObject {
    func setup()
    func copyDataInBuffer(_ data: String)
    func onShowMnemonic()
    func onHideMnemonic()
}

protocol SecretPhraseMnemonicInteractorInputProtocol: AnyObject {
    func requestMnemonicData()
}

protocol SecretPhraseMnemonicInteractorOutputProtocol: AnyObject {
    func didReceiveMnemonic(_ mnemonic: IRMnemonicProtocol)
}

protocol SecretPhraseMnemonicWireframeProtocol: CommonCopyPresentable {}
