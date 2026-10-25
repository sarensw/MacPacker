import AppKit
import Testing
@testable import Core
@testable import ArchivePreviewUI

extension AllCoreTests {
    @MainActor struct ArchivePreviewSortingTests {
        private func makePreview() async throws -> (ArchiveViewController, NSOutlineView, ArchiveState) {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folder = try #require(Bundle.module.url(forResource: "defaultArchives", withExtension: nil))
            state.open(url: folder.appendingPathComponent("defaultArchive.zip"))
            try await state.openTask?.value
            let root = try #require(state.root)
            let children = try #require(root.children).compactMap { state.entries[$0] }
            // Deliberately put files before folders to expose archive-order display.
            for child in children { root.removeChild(child.id) }
            for child in children.sorted(by: { $0.name > $1.name }) { root.addChild(child.id) }

            let controller = ArchiveViewController()
            let scrollView = try #require(controller.view.subviews.first as? NSScrollView)
            let outline = try #require(scrollView.documentView as? NSOutlineView)
            controller.state = state
            return (controller, outline, state)
        }

        @Test func initiallySortsByNameWithFoldersFirst() async throws {
            let (controller, outline, _) = try await makePreview()
            #expect(outline.sortDescriptors.first?.key == ArchiveSortOrder.name.rawValue)
            #expect(outline.sortDescriptors.first?.ascending == true)
            #expect((outline.item(atRow: 0) as? ArchiveItem)?.name == "folder")
            withExtendedLifetime(controller) {}
        }

        @Test func columnSortingPreservesExpansionAndSelection() async throws {
            let (controller, outline, state) = try await makePreview()
            let folder = try #require(state.entries.values.first { $0.name == "folder" })
            outline.expandItem(folder)
            let selected = try #require(state.entries.values.first { $0.name == "README.md" })
            outline.selectRowIndexes(IndexSet(integer: outline.row(forItem: selected)), byExtendingSelection: false)

            for column in outline.tableColumns {
                let prototype = try #require(column.sortDescriptorPrototype)
                for ascending in [true, false] {
                    outline.sortDescriptors = [NSSortDescriptor(key: prototype.key, ascending: ascending)]
                    #expect(outline.isItemExpanded(folder))
                    #expect(controller.selectedItems?.map(\.id) == [selected.id])
                    let children = try #require(folder.children).compactMap { state.entries[$0] }
                    let actual = (0..<children.count).compactMap {
                        outline.dataSource?.outlineView?(outline, child: $0, ofItem: folder) as? ArchiveItem
                    }
                    let expected = children.sorted { lhs, rhs in
                        switch prototype.key {
                        case ArchiveSortOrder.compressedSize.rawValue:
                            return ascending ? lhs.compressedSize < rhs.compressedSize : lhs.compressedSize > rhs.compressedSize
                        case ArchiveSortOrder.uncompressedSize.rawValue:
                            return ascending ? lhs.uncompressedSize < rhs.uncompressedSize : lhs.uncompressedSize > rhs.uncompressedSize
                        case ArchiveSortOrder.modificationDate.rawValue:
                            return ascending
                                ? (lhs.modificationDate ?? .distantPast) < (rhs.modificationDate ?? .distantPast)
                                : (lhs.modificationDate ?? .distantPast) > (rhs.modificationDate ?? .distantPast)
                        default:
                            let comparison = lhs.name.localizedStandardCompare(rhs.name)
                            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
                        }
                    }
                    #expect(actual.map(\.id) == expected.map(\.id))
                }
            }
            withExtendedLifetime(controller) {}
        }

        @Test func nestedArchiveUsesCurrentSortWhenFirstExpanded() async throws {
            let (controller, outline, state) = try await makePreview()
            let folder = try #require(state.entries.values.first { $0.name == "folder" })
            outline.expandItem(folder)
            let nested = try #require(state.entries.values.first { $0.name == "NestedArchive.zip" })
            outline.sortDescriptors = [NSSortDescriptor(key: ArchiveSortOrder.name.rawValue, ascending: false)]
            outline.expandItem(nested)

            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !outline.isItemExpanded(nested), ContinuousClock.now < deadline {
                await Task.yield()
            }
            #expect(outline.isItemExpanded(nested))
            let children = try #require(nested.children).compactMap { state.entries[$0] }
            #expect(!children.isEmpty)
            let expected = state.sortedForDisplay(children, order: .name, ascending: false)
            let actual = (0..<children.count).compactMap {
                outline.dataSource?.outlineView?(outline, child: $0, ofItem: nested) as? ArchiveItem
            }
            #expect(actual.map(\.id) == expected.map(\.id))
            withExtendedLifetime(controller) {}
        }
    }
}
