import Testing

/// Suites that use the shared clipboard or the shared recordings folder run one at a time,
/// so none sees another's writes (`.serialized` on one suite only orders the tests inside it).
@Suite(.serialized) enum SharedState {}
