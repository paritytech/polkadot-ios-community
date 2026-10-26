import Foundation
import Foundation_iOS
import MessageExchangeKit

protocol DeviceSyncPeerComponentMaking: Sendable {
    func makeSignalingSession(
        delegate: AnyPeerSessionDelegate<Data>,
        offerIdHandler: @escaping @Sendable (String) async throws -> Void
    ) async throws -> DeviceSyncSignalingSession

    func makeConnectionFlow(
        session: DeviceSyncSignalingSession
    ) -> any DevicePeerConnectionFlowing

    func makeExchange(
        flow: any DevicePeerConnectionFlowing,
        failureHandler: @escaping @Sendable (DeviceSyncConnectionFailure) async -> Void
    ) async throws -> any DeviceSyncExchanging
}

final class DeviceSyncPeerComponentFactory: DeviceSyncPeerComponentMaking, Sendable {
    typealias SessionFactory = @Sendable (
        AnyPeerSessionDelegate<Data>,
        @escaping @Sendable (String) async throws -> Void
    ) async throws -> DeviceSyncSignalingSession
    typealias FlowFactory = @Sendable (DeviceSyncSignalingSession) -> any DevicePeerConnectionFlowing
    typealias ExchangeFactory = @Sendable (
        any DevicePeerConnectionFlowing,
        @escaping @Sendable (DeviceSyncConnectionFailure) async -> Void
    ) async throws -> any DeviceSyncExchanging

    private let sessionFactory: SessionFactory
    private let flowFactory: FlowFactory
    private let exchangeFactory: ExchangeFactory

    init(
        sessionFactory: @escaping SessionFactory,
        flowFactory: @escaping FlowFactory,
        exchangeFactory: @escaping ExchangeFactory
    ) {
        self.sessionFactory = sessionFactory
        self.flowFactory = flowFactory
        self.exchangeFactory = exchangeFactory
    }

    func makeSignalingSession(
        delegate: AnyPeerSessionDelegate<Data>,
        offerIdHandler: @escaping @Sendable (String) async throws -> Void
    ) async throws -> DeviceSyncSignalingSession {
        try await sessionFactory(delegate, offerIdHandler)
    }

    func makeConnectionFlow(
        session: DeviceSyncSignalingSession
    ) -> any DevicePeerConnectionFlowing {
        flowFactory(session)
    }

    func makeExchange(
        flow: any DevicePeerConnectionFlowing,
        failureHandler: @escaping @Sendable (DeviceSyncConnectionFailure) async -> Void
    ) async throws -> any DeviceSyncExchanging {
        try await exchangeFactory(flow, failureHandler)
    }
}
