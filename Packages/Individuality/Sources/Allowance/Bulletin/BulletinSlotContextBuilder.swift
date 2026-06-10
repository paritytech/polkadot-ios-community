import Foundation

public enum BulletinSlotContextBuilder {
    /// Construct the context for a long-term storage claim at the given
    /// `period` and `counter`.
    ///
    /// Layout: `"pop:polkadot.net/rsc-lts" (24 bytes) <period (4 bytes BE)> <counter (1 byte)>` padded to 32 bytes.
    public static func context(period: UInt32, counter: UInt8) -> Data {
        var ctx = Data("pop:polkadot.net/rsc-lts".utf8)
        ctx.append(contentsOf: period.bigEndianBytes)
        ctx.append(counter)
        ctx.append(Data(repeating: 0, count: 32))
        return ctx.prefix(32)
    }
}
