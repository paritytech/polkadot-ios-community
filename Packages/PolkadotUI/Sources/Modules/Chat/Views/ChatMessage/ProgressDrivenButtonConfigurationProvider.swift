import UIKit

public final class ProgressDrivenButtonConfigurationProvider: ChatMessageMediaButtonConfigurationProviding {
    private let progressViewModel: any LoadingProgressViewModelProtocol
    private let successConfiguration: ChatMessageMediaViewConfiguration.ButtonConfiguration?
    private let failureConfiguration: ChatMessageMediaViewConfiguration.ButtonConfiguration?
    private let emitProgressOnSubscription: Bool
    public init(
        progressViewModel: any LoadingProgressViewModelProtocol,
        successConfiguration: ChatMessageMediaViewConfiguration.ButtonConfiguration?,
        failureConfiguration: ChatMessageMediaViewConfiguration.ButtonConfiguration? = .init(style: .retry),
        emitProgressOnSubscription: Bool
    ) {
        self.progressViewModel = progressViewModel
        self.successConfiguration = successConfiguration
        self.failureConfiguration = failureConfiguration
        self.emitProgressOnSubscription = emitProgressOnSubscription
    }

    public func startUpdate(
        onUpdate: @escaping (ChatMessageMediaViewConfiguration.ButtonConfiguration?) -> Void
    ) {
        if emitProgressOnSubscription {
            onUpdate(.init(style: .loading(cancelable: false)))
        }

        progressViewModel.startProgressUpdate(
            onProgress: { _ in onUpdate(.init(style: .loading(cancelable: false))) },
            onSuccess: { [weak self] in onUpdate(self?.successConfiguration) },
            onFailure: { [weak self] in onUpdate(self?.failureConfiguration) }
        )
    }

    public func stopUpdate() {
        progressViewModel.stopProgressUpdate()
    }
}
