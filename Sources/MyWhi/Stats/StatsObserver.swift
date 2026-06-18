// StatsObserver.swift
// Bridges the async VaultStore/VaultIndex world with the @MainActor
// AppState. Watches for vault changes and republishes the latest
// aggregate stats + notes list to the UI.
//
// Why a debounce? A flurry of saves (e.g. migration of 50 entries
// from history.json) shouldn't fire 50 SwiftUI redraws.
//
// Phase 4.1 — Incremental updates
// We keep the in-memory `notes` cache in sync as records are saved,
// updated, or deleted. The expensive `vaultStore.listAll()` walk is
// only done on the initial load and on explicit `reloadFromDisk()`
// (e.g. when the vault folder changes externally). Saves are O(1).

import Foundation
import Combine

@MainActor
final class StatsObserver: ObservableObject {

    @Published private(set) var notes: [TranscriptNote] = []
    @Published private(set) var stats: AggregateStats = .empty
    @Published private(set) var isLoading: Bool = false

    private let vaultStore: VaultStore
    private let vaultIndex: VaultIndex

    private var refreshTask: Task<Void, Never>?

    init(vaultStore: VaultStore, vaultIndex: VaultIndex) {
        self.vaultStore = vaultStore
        self.vaultIndex = vaultIndex
    }

    /// Trigger an async reload of the index from disk. Cancels any
    /// in-flight refresh. Safe to call on every save.
    func scheduleRefresh(after delay: TimeInterval = 0.3) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return  // cancelled
            }
            await self.refresh()
        }
    }

    /// Force an immediate refresh (no debounce). Used on first load
    /// and on external file change.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let allNotes = try await vaultStore.listAll()
            await vaultIndex.setNotes(allNotes)
            let stats = await vaultIndex.aggregate()
            self.notes = allNotes
            self.stats = stats
        } catch {
            NSLog("MyWhi.StatsObserver: refresh failed: \(error)")
        }
    }

    /// Search the current index (no disk hit).
    func search(_ query: String) async -> [TranscriptNote] {
        await vaultIndex.search(query)
    }

    /// Save a new transcript and update the in-memory list + stats
    /// incrementally. No full disk walk (Phase 4.1).
    func recordTranscript(
        text: String,
        language: String,
        model: String,
        engine: String,
        durationSeconds: Double,
        audio: String?
    ) async -> TranscriptNote? {
        do {
            let note = try await vaultStore.save(
                transcript: text,
                language: language,
                model: model,
                engine: engine,
                durationSeconds: durationSeconds,
                audio: audio
            )
            // Update in-memory state without a full disk rescan.
            // Insert at the top (newest-first sort is maintained by
            // vaultStore.listAll but we can shortcut here).
            var updated = self.notes
            updated.insert(note, at: 0)
            self.notes = updated
            await vaultIndex.setNotes(updated)
            self.stats = await vaultIndex.aggregate()
            return note
        } catch {
            NSLog("MyWhi.StatsObserver: save failed: \(error)")
            return nil
        }
    }

    /// Update an existing note's body in-memory.
    func update(note: TranscriptNote, newBody: String) async -> TranscriptNote? {
        do {
            let updated = try await vaultStore.update(note, newBody: newBody)
            if let idx = self.notes.firstIndex(where: { $0.id == updated.id }) {
                var list = self.notes
                list[idx] = updated
                self.notes = list
                await vaultIndex.setNotes(list)
                self.stats = await vaultIndex.aggregate()
            }
            return updated
        } catch {
            NSLog("MyWhi.StatsObserver: update failed: \(error)")
            return nil
        }
    }

    /// Delete a note and remove it from the in-memory list.
    func delete(note: TranscriptNote) async {
        do {
            try await vaultStore.delete(note)
            let list = self.notes.filter { $0.id != note.id }
            self.notes = list
            await vaultIndex.setNotes(list)
            self.stats = await vaultIndex.aggregate()
        } catch {
            NSLog("MyWhi.StatsObserver: delete failed: \(error)")
        }
    }

    /// Force a full reload from disk. Call this if the user has been
    /// editing files in another app (Obsidian, vim, TextEdit).
    func reloadFromDisk() async {
        await refresh()
    }

    /// Run the one-time migration from the legacy history.json.
    func runMigrationIfNeeded() async {
        do {
            let n = try await vaultStore.migrateFromLegacyHistoryJSON()
            if n > 0 {
                NSLog("MyWhi.StatsObserver: migrated \(n) entries from history.json")
                // Migration is a one-time bulk write — full refresh is
                // the simplest correct thing.
                await refresh()
            }
        } catch {
            NSLog("MyWhi.StatsObserver: migration failed: \(error)")
        }
    }
}