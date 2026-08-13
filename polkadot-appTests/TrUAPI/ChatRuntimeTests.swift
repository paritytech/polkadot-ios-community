import Foundation
import Testing
import Products
@testable import polkadot_app

// MARK: - Helpers

private func makeNativeRuntime(executor: ProductsScriptExecutorProtocol) -> ChatNativeRuntime {
    ChatNativeRuntime(
        productId: "test.dot",
        scriptExecutor: executor,
        nativeApiFactory: MockNativeApiFactory(),
        routers: ProductRoutersFacade.chatExtension()
    )
}

private func makeRustRuntime(
    execution: MockProductExecution = MockProductExecution(),
    chainConnections: MockChainConnections = MockChainConnections(),
    engine: MockJSEngine
) -> ChatRustRuntime {
    ChatRustRuntime(
        productUrl: URL(string: "product://test.dot/index.js")!,
        executionModel: makeExecutionModel(execution: execution, chainConnections: chainConnections),
        routers: ProductRoutersFacade.chatExtension(),
        engineFactory: { engine }
    )
}

// MARK: - Tests

struct ChatRuntimeTests {
    @Test func nativeRuntimeStartInitializesAndStartsBot() async throws {
        let executor = MockScriptExecutor()
        let runtime = makeNativeRuntime(executor: executor)

        try await runtime.start(messagingSupport: .init(bot: nil, context: nil))

        #expect(executor.calls == [.initializeBot, .onBotStarted])
    }

    @Test func nativeRuntimeForwardsUserMessage() async throws {
        let executor = MockScriptExecutor()
        let runtime = makeNativeRuntime(executor: executor)

        try await runtime.onUserMessage(text: "hi", roomId: "r1")

        #expect(executor.lastUserMessage?.text == "hi")
        #expect(executor.lastUserMessage?.roomId == "r1")
    }

    @Test func nativeRuntimeDisposeDelegates() async {
        let executor = MockScriptExecutor()
        let runtime = makeNativeRuntime(executor: executor)

        await runtime.dispose()

        #expect(executor.calls.contains(.dispose))
    }

    @Test func rustRuntimeDisposeTearsDownExecutionOnce() async {
        let execution = MockProductExecution()
        let chainConnections = MockChainConnections()
        let runtime = makeRustRuntime(
            execution: execution,
            chainConnections: chainConnections,
            engine: MockJSEngine()
        )

        await runtime.dispose()
        await runtime.dispose()

        #expect(execution.stopWsBridgeCallCount == 1)
        #expect(execution.closeCallCount == 1)
        #expect(chainConnections.closeAllCallCount == 1)
    }

    @Test func rustRuntimeChatSeamsSurfaceCleanErrors() async {
        let runtime = makeRustRuntime(engine: MockJSEngine())

        await #expect(throws: (any Error).self) {
            try await runtime.onUserMessage(text: "hi", roomId: nil)
        }
    }

    @Test func rustRuntimeStartsBridgeAndEvaluatesBootstrapBeforeContainer() async throws {
        let execution = MockProductExecution()
        let engine = MockJSEngine()
        let runtime = makeRustRuntime(execution: execution, engine: engine)

        try await runtime.start(messagingSupport: .init(bot: nil, context: nil))

        #expect(execution.startWsBridgeCallCount == 1)

        // "truapi-native-ready" marks the bootstrap; "freezeAndDelete" the container.
        let bootstrapIndex = try #require(
            engine.evaluatedScripts.firstIndex { $0.contains("truapi-native-ready") }
        )
        let containerIndex = try #require(
            engine.evaluatedScripts.firstIndex { $0.contains("freezeAndDelete") }
        )
        #expect(bootstrapIndex < containerIndex)

        await runtime.dispose()
    }

    @Test func chatScriptsFactoryOrdersBootstrapBeforeContainer() throws {
        let factory = ChatRustRuntimeScriptsFactory(bootstrapScript: "/*bootstrap*/")

        let scripts = try factory.makeScripts()

        #expect(scripts.count == 2)
        #expect(scripts[0] == "/*bootstrap*/")
        #expect(scripts[1].contains("__truapi_localhost"))
    }
}
