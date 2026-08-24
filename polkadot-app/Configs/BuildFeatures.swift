// Feature-availability flags are a single axis: a build carries exactly one of them.
//
// FEATURE_PRIZES     — prize branding and the game reveal webview (Nightly, Release).
// FEATURE_DIMS_FULL  — MobRules, DIM1, PolkadotPeer, DIM2 person actions (Debug, DevCI).
//
// Every `#if FEATURE_PRIZES` / `#if FEATURE_DIMS_FULL` site relies on its `#else` arm being the
// other configuration. Setting both in one xcconfig would silently take whichever branch a given
// call site happens to test first, so the combination is rejected here rather than at runtime.
//
// The environment axis (UNSTABLE / NIGHTLY) is independent and unconstrained by this check.

#if FEATURE_PRIZES && FEATURE_DIMS_FULL
    #error("FEATURE_PRIZES and FEATURE_DIMS_FULL are mutually exclusive — set exactly one in Configs/base.*.xcconfig")
#endif
