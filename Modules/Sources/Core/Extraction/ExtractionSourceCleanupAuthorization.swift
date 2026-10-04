/// A requested confirmation must receive an explicit approval. When the user
/// disables confirmation, successful extraction can clean up without a prompt.
enum ExtractionSourceCleanupAuthorization {
    static func isAuthorized(requiresConfirmation: Bool, response: Bool?) -> Bool {
        !requiresConfirmation || response == true
    }
}
