import Testing
import Foundation
@testable import FlaunedexCore

/// The folder tree:
///
///     Langues ── Anglais ── Verbes
///            └── Italien
///     Histoire
struct FolderTreeTests {

    private let langues = UUID()
    private let anglais = UUID()
    private let verbes = UUID()
    private let italien = UUID()
    private let histoire = UUID()

    private var nodes: [FolderNode] {
        [
            FolderNode(id: langues, parentID: nil),
            FolderNode(id: anglais, parentID: langues),
            FolderNode(id: verbes, parentID: anglais),
            FolderNode(id: italien, parentID: langues),
            FolderNode(id: histoire, parentID: nil),
        ]
    }

    @Test func aFolderIncludesEverythingBelowIt() {
        #expect(FolderTree.subtree(of: langues, in: nodes) == [langues, anglais, verbes, italien])
        #expect(FolderTree.subtree(of: anglais, in: nodes) == [anglais, verbes])
        #expect(FolderTree.subtree(of: histoire, in: nodes) == [histoire])
    }

    @Test func aFolderCannotMoveIntoItselfOrItsDescendants() {
        #expect(!FolderTree.canMove(langues, under: langues, in: nodes))
        #expect(!FolderTree.canMove(langues, under: verbes, in: nodes))
        #expect(!FolderTree.canMove(anglais, under: verbes, in: nodes))
    }

    @Test func aFolderCanMoveSidewaysOrToTheTop() {
        #expect(FolderTree.canMove(verbes, under: italien, in: nodes))
        #expect(FolderTree.canMove(anglais, under: histoire, in: nodes))
        #expect(FolderTree.canMove(verbes, under: nil, in: nodes))
    }

    @Test func pathRunsFromTheTopDown() {
        #expect(FolderTree.path(to: verbes, in: nodes) == [langues, anglais, verbes])
        #expect(FolderTree.path(to: histoire, in: nodes) == [histoire])
        #expect(FolderTree.depth(of: verbes, in: nodes) == 2)
        #expect(FolderTree.depth(of: langues, in: nodes) == 0)
    }

    @Test func aLoopInTheDataCannotHangTheApp() {
        // Not reachable through the app, but two offline devices syncing could
        // in principle produce it. Every walk must still terminate.
        let a = UUID(), b = UUID()
        let loop = [FolderNode(id: a, parentID: b), FolderNode(id: b, parentID: a)]
        #expect(FolderTree.subtree(of: a, in: loop) == [a, b])
        #expect(FolderTree.path(to: a, in: loop).count == 2)
    }

    @Test func anUnknownFolderIsItsOwnPath() {
        let stranger = UUID()
        #expect(FolderTree.path(to: stranger, in: nodes) == [stranger])
        #expect(FolderTree.subtree(of: stranger, in: nodes) == [stranger])
    }
}
