import UIKit

struct TabBarChromeContext {
    let tabController: UIViewController?
    let contentController: UIViewController?
    let isTabRoot: Bool
    let stackFolds: Bool
    let screen: UIViewController?
}

extension TabBarChromeContext {
    static func spa(_ controller: UIViewController) -> TabBarChromeContext {
        TabBarChromeContext(
            tabController: controller,
            contentController: controller,
            isTabRoot: false,
            stackFolds: true,
            screen: controller
        )
    }
}
