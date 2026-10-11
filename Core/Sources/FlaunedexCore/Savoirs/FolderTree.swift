import Foundation

/// One folder, reduced to what the tree logic needs: who it is and who holds
/// it. The app projects its stored folders into these.
public struct FolderNode: Sendable, Equatable, Hashable {
    public let id: UUID
    public let parentID: UUID?

    public init(id: UUID, parentID: UUID?) {
        self.id = id
        self.parentID = parentID
    }
}

/// Walking the folder tree.
///
/// Every walk keeps a set of folders already visited. A well-formed tree never
/// needs it, but two devices editing the same folders offline and syncing
/// through iCloud can in principle produce a loop, and a loop must cost a
/// wrong answer at worst, never a frozen app.
public enum FolderTree {

    /// The folder itself and everything below it, at any depth. This is what a
    /// session on a folder draws from: revising "Anglais" includes
    /// "Anglais › Verbes irréguliers".
    public static func subtree(of root: UUID, in nodes: [FolderNode]) -> Set<UUID> {
        var children: [UUID: [UUID]] = [:]
        for node in nodes {
            if let parent = node.parentID { children[parent, default: []].append(node.id) }
        }
        var result: Set<UUID> = [root]
        var stack = [root]
        while let current = stack.popLast() {
            for child in children[current] ?? [] where result.insert(child).inserted {
                stack.append(child)
            }
        }
        return result
    }

    /// Whether `folder` may be moved under `newParent` (nil is the top level).
    /// Moving a folder into itself or into one of its own descendants would cut
    /// it and everything in it off from the top of the tree, so it is refused.
    public static func canMove(_ folder: UUID, under newParent: UUID?, in nodes: [FolderNode]) -> Bool {
        guard let newParent else { return true }
        return !subtree(of: folder, in: nodes).contains(newParent)
    }

    /// The chain from the top level down to `folder`, both ends included.
    public static func path(to folder: UUID, in nodes: [FolderNode]) -> [UUID] {
        var parents: [UUID: UUID?] = [:]
        for node in nodes { parents[node.id] = node.parentID }
        var chain: [UUID] = []
        var seen: Set<UUID> = []
        var current: UUID? = folder
        while let id = current, seen.insert(id).inserted {
            chain.append(id)
            current = parents[id] ?? nil
        }
        return chain.reversed()
    }

    /// How deep `folder` sits: 0 at the top level.
    public static func depth(of folder: UUID, in nodes: [FolderNode]) -> Int {
        max(0, path(to: folder, in: nodes).count - 1)
    }
}
