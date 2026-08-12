/// Confirm-only signing context: the review needed to render the sheet plus a
/// one-shot Bool decision. There is no reply channel and no wallet resolution —
/// the rust core performs the signing after approval.
protocol ProductsSignConfirmContextProtocol: AnyObject {
    var requester: PolkadotSigningRequester { get }
    var input: ProductsSignConfirmInput { get }

    @MainActor func deliver(_ approved: Bool)
}

protocol ProductsSignConfirmInteractorInputProtocol: AnyObject {
    func setup()
    func confirm()
    func reject()
}

@MainActor
protocol ProductsSignConfirmInteractorOutputProtocol: AnyObject {
    func didStartParsingRequest()
    func didFinishParsingRequest(with model: ProductsSignConfirmModel)
    func didFailToParseRequest(with error: Error)

    func didConfirm()
    func didReject()
}
