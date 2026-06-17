// StatsObserver.swift
// Bridges the async VaultStore/VaultIndex world with the @MainActor
// AppState. Watches for vault changes and republishes the latest
// aggregate stats + notes list to the UI.
//
// Why a debounce? A flurry of saves (e.g. migration of 50 entries
// from history.json) shouldn't fire 50 SwiftUI redraws.

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

    /// Force an immediate refresh (no debounce).
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

    /// Save a new transcript and trigger a refresh.
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
            await vaultIndex.invalidate()
            await refresh()
            return note
        } catch {
            NSLog("MyWhi.StatsObserver: save failed: \(error)")
            return nil
        }
    }

    /// Update an existing note's body.
    func update(note: TranscriptNote, newBody: String) async -> TranscriptNote? {
        do {
            let updated = try await vaultStore.update(note, newBody: newBody)
            await vaultIndex.invalidate()
            await refresh()
            return updated
        } catch {
            NSLog("MyWhi.StatsObserver: update failed: \(error)")
            return nil
        }
    }

    /// Delete a note.
    func delete(note: TranscriptNote) async {
        do {
            try await vaultStore.delete(note)
            await vaultIndex.invalidate()
            await refresh()
        } catch {
            NSLog("MyWhi.StatsObserver: delete failed: \(error)")
        }
    }

    /// Run the one-time migration from the legacy history.json.
    func runMigrationIfNeeded() async {
        do {
            let n = try await vaultStore.migrateFromLegacyHistoryJSON()
            if n > 0 {
                NSLog("MyWhi.StatsObserver: migrated \(n) entries from history.json")
                await vaultIndex.invalidate()
                await refresh()
            }
        } catch {
            NSLog("MyWhi.StatsObserver: migration failed: \(error)")
        }
    }
}