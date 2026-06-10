import Foundation

public enum PGASSlotContextBuilder {
    /// Construct the context for a PGAS claim at the given `day` and `slotIndex`.
    ///
    /// Layout: `pop:gas:<day (4 bytes LE)><slotIndex (4 bytes LE)>` padded to 32 bytes.
    public static func context(day: UInt32, slotIndex: UInt32) -> Data {
        var ctx = Data("pop:gas:".utf8)
        ctx.append(contentsOf: day.littleEndianBytes)
        ctx.append(contentsOf: slotIndex.littleEndianBytes)
        ctx.append(Data(repeating: 0, count: 32))
        return ctx.prefix(32)
    }
}
