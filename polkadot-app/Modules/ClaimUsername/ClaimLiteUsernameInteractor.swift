import UIKit
import SubstrateSdk
import Operation_iOS
import Combine
import KeyDerivation

struct ClaimLiteUsernameDependency {
    let walletSetupManagerFactory: () -> WalletSetupManaging
    let registrationParamsFactory: (
        _ mainWallet: WalletManaging
    ) throws -> LitePersonParamsFactoryProtocol
    let usernameOperationFactory: () -> UsernameOperationFactoryProtocol
    let usernameStorage: () -> UsernameStoring
    let operationQueue: () -> OperationQueue
    let mainWallet: WalletManaging
}

final class ClaimLiteUsernameInteractor {
    weak var presenter: ClaimUsernameInteractorOutputProtocol?

    private var walletCreated: Bool
    let dependencies: ClaimLiteUsernameDependency

    lazy var usernameOperationFactory = dependencies.usernameOperationFactory()
    lazy var usernameStorage = dependencies.usernameStorage()
    lazy var operationQueue = dependencies.operationQueue()

    let logger: LoggerProtocol

    init(
        walletCreated: Bool,
        dependencies: ClaimLiteUsernameDependency,
        logger: LoggerProtocol
    ) {
        self.walletCreated = walletCreated
        self.dependencies = dependencies
        self.logger = logger
    }
}

extension ClaimLiteUsernameInteractor: ClaimUsernameInteractorInputProtocol {
    var metadata: UsernameMetadata {
        .default
    }

    func claim(username: Username) -> AnyPublisher<Username, Error> {
        if walletCreated {
            claimWithPersistedWallet(username)
        } else {
            createWalletsThenClaimUsername(username)
        }
    }

    func check(username: Username) -> AnyPublisher<UsernameAvailableType, any Error> {
        usernameOperationFactory.availableUsernameWrapper(for: username.value)
            .publisher(in: operationQueue)
            .delayAtLeast(for: 0.3)
            .eraseToAnyPublisher()
    }

    func save(username: Username) {
        usernameStorage.username = username
        presenter?.didSaveUsername()
    }
}

private extension ClaimLiteUsernameInteractor {
    enum FlowError: Error {
        case internalError
    }

    func registrationFactory() throws -> LitePersonParamsFactoryProtocol {
        try dependencies.registrationParamsFactory(dependencies.mainWallet)
    }

    func claimWithPersistedWallet(_ username: Username) -> AnyPublisher<Username, Error> {
        do {
            let factory = try registrationFactory()
            return performClaim(username: username, registrationFactory: factory)
        } catch {
            return Fail(error: error).eraseToAnyPublisher()
        }
    }

    func performClaim(
        username: Username,
        registrationFactory: LitePersonParamsFactoryProtocol
    ) -> AnyPublisher<Username, Error> {
        usernameOperationFactory.attester()
            .publisher(in: operationQueue)
            .tryMap { $0.attester }
            .flatMap { accountId in
                Result {
                    try registrationFactory.deriveLitePersonParams(
                        for: username.partialUsername,
                        verifier: accountId
                    )
                }
                .publisher
            }
            .tryMap {
                try RegisterUsernameParameters(
                    username: username.partialUsername,
                    preferredDigits: username.digits,
                    candidateAccountId: $0.accountId.toAddress(using: .substrate(42)),
                    candidateSignature: $0.accountIdProofSignature,
                    ringVrfKey: $0.personMemberKey,
                    proofOfOwnership: $0.membershipProofSignature,
                    identifierKey: $0.chatPublicKey,
                    consumerRegistrationSignature: $0.resourcesSignature
                )
            }
            .flatMap { [usernameOperationFactory, operationQueue] in
                usernameOperationFactory.claimUsername(
                    using: $0
                )
                .publisher(in: operationQueue)
            }
            .map { Username(value: $0.username) }
            .eraseToAnyPublisher()
    }

    func createWalletsThenClaimUsername(_ username: Username) -> AnyPublisher<Username, Error> {
        presenter?.didChangeAccountCreation(inProgress: true)

        return authorizeUser()
            .flatMap { [dependencies] _ -> AnyPublisher<Void, Error> in
                Result {
                    let walletSetupManager = dependencies.walletSetupManagerFactory()
                    try walletSetupManager.createWallets(with: nil)
                }
                .publisher
                .eraseToAnyPublisher()
            }
            .flatMap { [weak self] _ -> AnyPublisher<Username, Error> in
                guard let self else {
                    return Fail(error: FlowError.internalError).eraseToAnyPublisher()
                }

                walletCreated = true
                return claimWithPersistedWallet(username)
            }
            .handleEvents(
                receiveCompletion: { [weak self] _ in
                    self?.presenter?.didChangeAccountCreation(inProgress: false)
                },
                receiveCancel: { [weak self] in
                    self?.presenter?.didChangeAccountCreation(inProgress: false)
                }
            )
            .eraseToAnyPublisher()
    }

    func authorizeUser() -> AnyPublisher<Void, Error> {
        Future { [presenter] promise in
            guard let presenter else {
                promise(.failure(FlowError.internalError))
                return
            }

            presenter.authorizeUser { authorized in
                if authorized {
                    promise(.success(()))
                } else {
                    promise(.failure(FlowError.internalError))
                }
            }
        }
        .eraseToAnyPublisher()
    }
}
