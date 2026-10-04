import Testing
@testable import Core

extension AllCoreTests {
    struct DefaultArchiveAssociationsTests {
        @Test func includesRegisteredTarballCompositions() {
            let ids = Set(DefaultArchiveAssociations.choices(catalog: ArchiveTypeCatalog()).map(\.id))
            #expect(ids.isSuperset(of: ["tar.bz2", "tar.gz", "tar.lz4", "tar.xz", "tar.z"]))
        }

        @Test func neverRequestsIndividualVolumeAssociations() {
            let catalog = ArchiveTypeCatalog()
            for (id, expected) in [("rar", ["cbr", "rar"]), ("7zip", ["7z"])] {
                let format = catalog.getAllTypes().first { $0.id == id }!
                #expect(DefaultArchiveAssociations.extensions(for: format) == expected)
            }
            let zip = catalog.getAllTypes().first { $0.id == "zip" }!
            let extensions = DefaultArchiveAssociations.extensions(for: zip)
            #expect(!extensions.contains("001"))
            #expect(!extensions.contains("apk"))
            #expect(!extensions.contains("jar"))
        }
    }
}
