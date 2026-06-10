import Kingfisher
import UIKit
import Operation_iOS

enum ProceduralTattooImageProviderError: Error {
    case failedToLoadImageData
}

final class ProceduralTattooImageProvider: ImageDataProvider {
    private let renderer: ProceduralTattooRenderer
    private let input: ProceduralTattooInput
    private let logger: LoggerProtocol

    init(
        renderer: ProceduralTattooRenderer,
        input: ProceduralTattooInput,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.renderer = renderer
        self.input = input
        self.logger = logger
        cacheKey = "\(input.generationScriptUrl.absoluteString)_\(input.scriptInput)"
    }

    var cacheKey: String

    func data(handler: @escaping (Result<Data, Error>) -> Void) {
        logger.debug("No cached image data found for key: \(cacheKey), loading from web view")
        renderer.render(input: input) { data in
            guard let data else {
                handler(.failure(ProceduralTattooImageProviderError.failedToLoadImageData))
                return
            }
            handler(.success(data))
        }
    }
}
