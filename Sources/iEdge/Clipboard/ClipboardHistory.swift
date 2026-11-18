import Foundation

/// The clipboard history rules, as a value type with no I/O (docs/SPEC.md §1.3):
/// same content moves to the top instead of duplicating, `maxEntries` never evicts pinned
/// entries, clearing keeps the pinned ones, and the list shows pinned first, then most recent.
///
/// Mutations return the entries that left the history, so the owner can delete their files.
struct ClipboardHistory: Equatable {
    /// Most recent first.
    private(set) var entries: [ClipboardEntry]
    var maxEntries: Int

    init(entries: [ClipboardEntry] = [], maxEntries: Int) {
        self.entries = entries.sorted { $0.date > $1.date }
        self.maxEntries = max(1, maxEntries)
    }

    /// Pinned first, then most recent.
    var sorted: [ClipboardEntry] {
        entries.filter(\.pinned) + entries.filter { !$0.pinned }
    }

    func entry(id: UUID) -> ClipboardEntry? {
        entries.first { $0.id == id }
    }

    /// Adds `entry` on top. When an entry with the same content exists (`isSameContent`), that
    /// one moves to the top with the new date and source instead, keeping its id and pin, and the
    /// incoming entry is returned as dropped.
    @discardableResult
    mutating func insert(
        _ entry: ClipboardEntry,
        isSameContent: (ClipboardContent, ClipboardContent) -> Bool = { $0 == $1 }
    ) -> [ClipboardEntry] {
        var dropped: [ClipboardEntry] = []
        if let index = entries.firstIndex(where: { isSameContent($0.content, entry.content) }) {
            var existing = entries.remove(at: index)
            existing.date = entry.date
            existing.sourceBundleID = entry.sourceBundleID ?? existing.sourceBundleID
            existing.sourceAppName = entry.sourceAppName ?? existing.sourceAppName
            entries.insert(existing, at: 0)
            if existing.content != entry.content { dropped.append(entry) }
        } else {
            entries.insert(entry, at: 0)
        }
        return dropped + trim()
    }

    /// Moves an entry to the top with a fresh date (after copying it back).
    mutating func touch(id: UUID, date: Date = Date()) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var moved = entries.remove(at: index)
        moved.date = date
        entries.insert(moved, at: 0)
    }

    mutating func setPinned(_ pinned: Bool, id: UUID) -> [ClipboardEntry] {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return [] }
        entries[index].pinned = pinned
        // Unpinning can push the history over the limit again.
        return trim()
    }

    mutating func togglePin(id: UUID) -> [ClipboardEntry] {
        guard let entry = entry(id: id) else { return [] }
        return setPinned(!entry.pinned, id: id)
    }

    mutating func remove(id: UUID) -> ClipboardEntry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        return entries.remove(at: index)
    }

    /// Removes every entry that is not pinned.
    mutating func clear() -> [ClipboardEntry] {
        let removed = entries.filter { !$0.pinned }
        entries.removeAll { !$0.pinned }
        return removed
    }

    mutating func setMaxEntries(_ value: Int) -> [ClipboardEntry] {
        maxEntries = max(1, value)
        return trim()
    }

    /// Drops the oldest unpinned entries while over the limit. Pinned entries never leave, so a
    /// history with more pins than `maxEntries` stays above it.
    private mutating func trim() -> [ClipboardEntry] {
        var removed: [ClipboardEntry] = []
        while entries.count > maxEntries, let index = entries.lastIndex(where: { !$0.pinned }) {
            removed.append(entries.remove(at: index))
        }
        return removed
    }
}
