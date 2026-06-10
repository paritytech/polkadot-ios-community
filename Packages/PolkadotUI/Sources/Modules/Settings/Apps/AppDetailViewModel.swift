import Observation
import SwiftUI

@Observable
public final class AppDetailViewModel {
    public var name: String = ""
    public var onPermissionsTap: (() -> Void)?

    public init() {}
}
