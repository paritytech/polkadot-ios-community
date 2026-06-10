import UIKitExt

protocol TattooConfirmViewProtocol: ControllerBackedProtocol {}

protocol TattooConfirmPresenterProtocol: AnyObject {
    func cancel()
    func confirm()
}

protocol TattooConfirmWireframeProtocol: AnyObject {
    func close(view: TattooConfirmViewProtocol?, completion: (() -> Void)?)
}
