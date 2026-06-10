#if TESTNET_FEATURE
    import Combine
    import Foundation
    import KeyDerivation

    final class AppFactoryResetChecker {
        private let storage: UsernameStoring
        private let wallet: WalletManaging
        private let identityService: IdentityServiceProtocol
        private var cancellable: AnyCancellable?

        init(
            storage: UsernameStoring,
            wallet: WalletManaging,
            identityService: IdentityServiceProtocol
        ) {
            self.storage = storage
            self.wallet = wallet
            self.identityService = identityService
        }

        func checkIfResetNeeded(completion: @escaping (Bool) -> Void) {
            guard storage.usernameClaimed else {
                completion(false)
                return
            }

            guard let accountId = try? wallet.getRawPublicKey() else {
                completion(false)
                return
            }

            cancellable = identityService.username(for: accountId)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { result in
                        if case .failure = result {
                            completion(false)
                        }
                    },
                    receiveValue: { username in
                        completion(username == nil)
                    }
                )
        }
    }
#endif
