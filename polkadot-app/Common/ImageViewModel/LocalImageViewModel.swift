import UIKit
import PolkadotUI
import Kingfisher

final class LocalImageViewModel {
    private let imageProvider: ImageDataProvider
    private let optionsFactory: ImageProcessingOptionsProducing

    init(
        provider: ImageDataProvider,
        optionsFactory: ImageProcessingOptionsProducing = ImageProcessingOptionsFactory()
    ) {
        imageProvider = provider
        self.optionsFactory = optionsFactory
    }
}

extension LocalImageViewModel: @preconcurrency ChatMessageMediaPreviewProviding {
    var identifier: String {
        imageProvider.cacheKey
    }

    @MainActor
    func providePreview(for imageView: UIImageView, size: CGSize?) {
        let settings = ImageViewModelSettings(targetSize: size)
        loadImage(on: imageView, settings: settings, animated: true, completion: nil)
    }
}

extension LocalImageViewModel: @preconcurrency ImageViewModelProtocol {
    @MainActor
    func loadImage(
        on imageView: UIImageView,
        settings: ImageViewModelSettings,
        animated: Bool,
        completion: ((Bool) -> Void)?
    ) {
        let options = optionsFactory.options(for: settings, animated: animated)
        imageView.kf.setImage(with: imageProvider, options: options) { result in
            switch result {
            case .success:
                completion?(true)
            case .failure:
                completion?(false)
            }
        }
    }

    @MainActor
    func cancel(on imageView: UIImageView) {
        imageView.kf.cancelDownloadTask()
        imageView.image = nil
    }
}
