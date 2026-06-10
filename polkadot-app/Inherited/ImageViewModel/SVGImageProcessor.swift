import Kingfisher
import SVGKit

final class SVGImageProcessor: ImageProcessor {
    let identifier: String

    let serializer: RemoteImageSerializer

    init() {
        identifier = "io.papp.kf.svg.processor"
        serializer = RemoteImageSerializer.shared
    }

    func process(item: ImageProcessItem, options: KingfisherParsedOptionsInfo) -> KFCrossPlatformImage? {
        switch item {
        case let .image(image):
            image
        case let .data(data):
            serializer.image(with: data, options: options)
        }
    }
}

final class RemoteImageSerializer: CacheSerializer {
    static let shared = RemoteImageSerializer()

    private lazy var internalCache = FormatIndicatedCacheSerializer.png

    func data(with image: KFCrossPlatformImage, original: Data?) -> Data? {
        internalCache.data(with: image, original: original)
    }

    func image(with data: Data, options: KingfisherParsedOptionsInfo) -> KFCrossPlatformImage? {
        if let uiImage = internalCache.image(with: data, options: options) {
            return uiImage
        } else {
            let imsvg = SVGKImage(data: data)
            return imsvg?.uiImage ?? UIImage()
        }
    }
}
