import Foundation
import Combine

final class ClaimFullUsernameInteractor {
    weak var presenter: ClaimUsernameInteractorOutputProtocol?

    private let registeredData: People.RegisteredData
    private let claimService: FullUsernameClaimServicing
    private let availabilityValidator: FullUsernameAvailabilityValidating
    private let usernameStorage: UsernameStoring
    private let eventCenter: EventCenterProtocol
    private let logger: LoggerProtocol

    private var availability: FullUsernameAvailability?

    init(
        registeredData: People.RegisteredData,
        claimService: FullUsernameClaimServicing,
        availabilityValidator: FullUsernameAvailabilityValidating = FullUsernameAvailabilityValidator(),
        usernameStorage: UsernameStoring = UsernameStorage(),
        eventCenter: EventCenterProtocol = EventCenter.shared,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.registeredData = registeredData
        self.claimService = claimService
        self.availabilityValidator = availabilityValidator
        self.usernameStorage = usernameStorage
        self.eventCenter = eventCenter
        self.logger = logger
    }
}

extension ClaimFullUsernameInteractor: ClaimUsernameInteractorInputProtocol {
    var metadata: UsernameMetadata {
        .default
    }

    func claim(username: Username) -> AnyPublisher<Username, Error> {
        performClaim(for: username)
    }

    func check(username: Username) -> AnyPublisher<UsernameAvailableType, Error> {
        performCheckAvailability(for: username)
            .delayAtLeast(for: 0.3)
            .handleEvents(receiveOutput: { [weak self] in
                self?.updateAvailability($0)
            })
            .map(\.toAvailableType)
            .eraseToAnyPublisher()
    }

    func save(username: Username) {
        usernameStorage.username = username
        presenter?.didSaveUsername()
    }
}

private extension ClaimFullUsernameInteractor {
    enum InteractorError: Error {
        case missingAvailability
    }

    func performCheckAvailability(for username: Username) -> AnyPublisher<FullUsernameAvailability, Error> {
        let validator = availabilityValidator

        return Deferred {
            Future { promise in
                Task {
                    do {
                        let value = try await validator.checkAvailability(for: username)
                        promise(.success(value))
                    } catch {
                        promise(.failure(error))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

    func updateAvailability(_ availability: FullUsernameAvailability) {
        DispatchQueue.main.async { [weak self] in
            self?.availability = availability
        }
    }

    func performClaim(for username: Username) -> AnyPublisher<Username, Error> {
        guard let availability else {
            logger.error("Missing availability")
            return Fail(error: InteractorError.missingAvailability).eraseToAnyPublisher()
        }

        let service = claimService

        return Deferred {
            Future<Void, Error> { promise in
                Task {
                    do {
                        try await service.claimUsername(username, with: availability)
                        promise(.success(()))
                    } catch {
                        promise(.failure(error))
                    }
                }
            }
        }
        .map { username }
        .handleEvents(receiveOutput: { [eventCenter, registeredData] in
            eventCenter.notify(with: FullUsernameClaimed(
                liteUsername: registeredData.liteUsername,
                fullUsername: $0,
                source: .init(registeredData.source)
            ))
        })
        .eraseToAnyPublisher()
    }
}

private extension FullUsernameAvailability {
    var toAvailableType: UsernameAvailableType {
        switch self {
        case .free,
             .reservedByUs,
             .reclaimExpiredReservation:
            .available(digits: [])
        case .notAvailable:
            .taken
        }
    }
}
