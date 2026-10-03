import Testing
import Foundation
@testable import Core

struct ArchiveEngineSelectorDar: ArchiveEngineSelectorProtocol {
    private var engine = ArchiveDarEngine()

    func engine(for id: String) -> (any Core.ArchiveEngine)? {
        return engine
    }

    func engine(for type: Core.ArchiveEngineType) -> any Core.ArchiveEngine {
        return engine
    }

    func engineType(for id: String) -> Core.ArchiveEngineType? {
        return .dar
    }
}
