import Observation
import SwiftUI

@Observable
public class RecoverPendingTransactionsViewModel {
    public enum BannerStyle {
        case success
        case error
    }

    public var bannerText: String?
    public var bannerStyle: BannerStyle = .success
    public var headlineText: String = ""
    public var descriptionText: String = ""
    public var noteText: String = ""
    public var buttonTitle: String = ""
    public var recoveringText: String = ""
    public var isLoading: Bool = false
    public var onTap: (() -> Void)?

    public init() {}
}
