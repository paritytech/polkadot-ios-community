# Domain Glossary: Chain & Connection Status

## Terms

**Block age** — Elapsed time since the most recent block was received. (Not to be confused with expected block time, which is the nominal interval between blocks.)

**Chain** — A Substrate chain the app maintains a connection to. Three chains are monitored: Individuality, Asset Hub, and Bulletin.

**Connection** — A monitored endpoint whose liveness the app reports. Four connections exist: three chains plus the Statement Store. This is the umbrella term for all monitored endpoints. (Legacy code may refer to all four as "chains"; this is imprecise and is being corrected.)

**Expected block time** — The nominal interval between a chain's blocks. A constant per chain. (Distinct from block age and easily confused with it. Not surfaced in the UI.)

**Finality lag** — How many blocks behind the finalized head a chain's current head is.

**Health** — A 0-to-1 score for a connection, derived from block age, finality lag, and latency using worst-of logic, then smoothed by a rolling median. Health is independent of state: a connection can be connected and still have health near zero. That gap between "connected" and "working well" is the core purpose of the status UI.

**Latency** — Round-trip time to a connection. (The codebase also refers to this as "ping" in one place; "latency" is the canonical term.)

**State** — A connection's coarse liveness status: connected, connecting, or offline.

**Statement Store** — A delivery subscription that rides on the Individuality chain's connection. It is a connection but not a chain. It has no independent latency, block age, or finality lag; the values reported for it are copied from Individuality's.

---

## Alignment Notes

The codebase does not yet use these terms consistently. The following legacy terms survive in the source and have planned alignment:

- "ping" (latency)
- "lastBlockDate" (block age)
- All four connections currently filed under "chain"

Aligning the code with this glossary is deliberately deferred to a separate change to keep diffs focused.
