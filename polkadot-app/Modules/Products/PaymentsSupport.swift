import Coinage

final class PaymentsSupport {
    let coinageService: CoinageServicing
    let incomingPaymentService: IncomingPaymentServicing

    var externalPaymentService: ExternalPaymentServicing {
        coinageService.externalPaymentService
    }

    init(coinageService: CoinageServicing, incomingPaymentService: IncomingPaymentServicing) {
        self.coinageService = coinageService
        self.incomingPaymentService = incomingPaymentService
    }
}
