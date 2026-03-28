import CSevenZip

/// Wraps the raw C handle. Intentionally non-Sendable so the compiler
/// prevents it from escaping the actor's isolation domain.
final class BridgeHandle {
    /// The opaque archive reference from the C bridge.
    let ref: SZArchiveRef
    /// Creates a handle wrapping the given C reference.
    init(ref: SZArchiveRef) { self.ref = ref }
    deinit { sz_close(ref) }
}
