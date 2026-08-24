import Foundation
import Coinage

extension AppConfig {
    enum Coinage {
        /// Instance 0 is created by the runtime at genesis for the external asset, so it is
        /// the correct fallback when remote config has not published a key.
        static var instanceId: CoinageInstanceId {
            AppConfigProvider.shared.getRemoteConfig()?.coinageInstanceId ?? 0
        }
    }
}
