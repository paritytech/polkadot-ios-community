import Kingfisher
import PolkadotUI
import UIKit

final class ProductLinkIconImageViewModel {
    private let provider: ImageDataProvider

    init(provider: ImageDataProvider) {
        self.provider = provider
    }
}

extension ProductLinkIconImageViewModel: @preconcurrency ImageViewModelProtocol {
    @MainActor
    func loadImage(
        on imageView: UIImageView,
        settings _: ImageViewModelSettings,
        animated: Bool,
        completion: ((Bool) -> Void)?
    ) {
        let options: KingfisherOptionsInfo = [
            .processor(SVGImageProcessor()),
            .transition(animated ? .fade(0.2) : .none),
            .cacheOriginalImage
        ]
        imageView.kf.setImage(with: provider, options: options) { result in
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
    }
}
