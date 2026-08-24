import Foundation

/// Pure validation of registration invariants — no IO, no CoreData.
public enum RegistrationValidator {
    /// Validates the four registration invariants in order:
    /// 1. Non-empty entry (inputs or outputs)
    /// 2. Fresh outputs (not minted elsewhere, not received-coin keys)
    /// 3. Unique consumer (inputs not claimed by non-failure entries)
    /// 4. Blocked handoff (inputs not carrying handoff marks)
    ///
    /// - Parameters:
    ///   - entry: The entry being registered.
    ///   - claimedInputs: Identifiers already claimed as inputs by non-failure entries.
    ///   - mintedOutputs: Identifiers already minted as outputs by any entry.
    ///   - receivedInputs: Identifiers already claimed as received-coin inputs by any entry.
    ///   - marks: Identifiers carrying handoff marks.
    public static func validate(
        _ entry: DurabilityEntry,
        claimedInputs: Set<String>,
        mintedOutputs: Set<String>,
        receivedInputs: Set<String>,
        marks: Set<String>
    ) throws {
        // 1. Non-empty entry
        guard !entry.inputs.isEmpty || !entry.outputs.isEmpty else {
            throw DurabilityError.emptyEntry
        }

        // 2. Fresh outputs
        for output in entry.outputs {
            guard !mintedOutputs.contains(output.identifier),
                  !receivedInputs.contains(output.identifier)
            else {
                throw DurabilityError.outputNotFresh(output.identifier)
            }
        }

        // 3. Unique consumer
        for input in entry.inputs {
            guard !claimedInputs.contains(input.identifier) else {
                throw DurabilityError.inputAlreadyClaimed(input.identifier)
            }
            // 4. Blocked handoff
            guard !marks.contains(input.identifier) else {
                throw DurabilityError.inputHandedOff(input.identifier)
            }
        }
    }
}
