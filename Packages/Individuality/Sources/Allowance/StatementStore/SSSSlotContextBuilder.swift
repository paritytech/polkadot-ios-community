import Foundation
import FoundationExt

public enum SSSSlotContextBuilder {
    /// Context for a statement store slot claim at the given
    /// `period` and `seq`.
    ///
    /// Layout: `SSS_SLOT:<period (4 bytes BE)><seq (4 bytes BE)>` padded to 32 bytes with whitespace.
    public static func context(period: UInt32, seq: UInt32) -> Data {
        var ctx = Data("SSS_SLOT:".utf8)
        ctx.append(contentsOf: period.bigEndianBytes)
        ctx.append(contentsOf: seq.bigEndianBytes)

        let padding = Data(repeating: UInt8(ascii: " "), count: 32)
        ctx.append(contentsOf: padding)
        return ctx.prefix(32)
    }
}
