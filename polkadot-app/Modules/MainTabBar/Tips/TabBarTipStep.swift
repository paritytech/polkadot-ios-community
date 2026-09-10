import TipKit
import UIKit

struct TabBarTipStep {
    let tip: AnyTip
    let slot: TabBarSlot

    init(tip: some Tip, slot: TabBarSlot) {
        self.tip = AnyTip(tip)
        self.slot = slot
    }
}
