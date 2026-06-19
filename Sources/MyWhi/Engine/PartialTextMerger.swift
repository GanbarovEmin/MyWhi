// PartialTextMerger.swift
// Phase 14 — pure logic for sliding-window live-transcript merging.
//
// PROBLEM
// Phase 8's live-streaming loop decodes the full rolling buffer every
// 0.8s. For a 5-minute recording that's ~5 minutes of decode every
// tick — useless UX-wise and needlessly expensive. Phase 14 switches
// to a sliding window: only the last `liveWindowSeconds` of audio is
// decoded per tick, keeping cost constant regardless of duration.
//
// NEW PROBLEM
// With a sliding window, consecutive decodes overlap. Suppose the
// user said "привет как дела" in two ticks:
//
//   tick 1: decode("…привет как")        → "привет как"
//   tick 2: decode("…как дела")          → "как дела"  (window slid forward)
//
// If we naively replace tick 1's text with tick 2's, we lose
// "привет". If we concatenate, we get "привет как как дела".
//
// SOLUTION
// Find the longest overlap between the tail of `previous` and the
// head of `next`. Concatenate `previous` + the part of `next` that
// comes after the overlap. That's the standard "diff/merge" trick.
//
// OVERLAP DETECTION
// We don't try to be clever — we just look at the last N tokens of
// `previous` (default N=12) and check each against the head of
// `next`, returning the longest matching suffix/prefix pair. Token
// boundaries are whitespace. This handles the common case where the
// window slides by one tick — last 2-3 words overlap perfectly.
//
// LIMITATIONS
// - Hallucinations: WhisperKit can produce text for the same audio
//   in different forms ("привет, как дела?" vs "Привет как дела").
//   We do a case-insensitive compare for the overlap, but if the
//   words differ, we keep `previous` and ignore `next`. This is the
//   conservative choice — better to miss new words than to duplicate.
// - Empty `next`: return `previous` unchanged.
// - Empty `previous`: return `next` (no merge needed).
//
// This function is pure — it has no dependencies on the audio engine
// or SwiftUI, so it's straightforward to unit-test.

import Foundation

enum PartialTextMerger {

    /// Maximum number of trailing tokens from `previous` we'll try to
    /// match against the head of `next`. Larger N = better chance of
    /// catching long overlaps; smaller N = faster. 12 is plenty for
    /// 0.8s tick cadence (typically 2-5 words).
    static let maxOverlapTokens: Int = 12

    /// Merge `previous` (the text we showed last tick) with `next`
    /// (what WhisperKit just produced from the sliding window). Returns
    /// the new full transcript to display.
    static func merge(previous: String, next: String) -> String {
        // Strip leading/trailing whitespace AND a layer of pure
        // punctuation ("...", "?!", etc.). We don't want to treat
        // punctuation-only strings as "real" content.
        let prev = sanitize(previous)
        let nxt = sanitize(next)
        if prev.isEmpty { return nxt }
        if nxt.isEmpty  { return prev }

        let prevTokens = tokenize(prev)
        let nextTokens = tokenize(nxt)
        guard !prevTokens.isEmpty, !nextTokens.isEmpty else { return prev }

        // Try suffix-of-prev ↔ prefix-of-next of lengths 1..min(N, both).
        let maxCheck = min(maxOverlapTokens, prevTokens.count, nextTokens.count)
        var bestOverlap = 0
        for n in stride(from: maxCheck, through: 1, by: -1) {
            if tailsMatchHead(prevTail: prevTokens, n: n, nextHead: nextTokens) {
                bestOverlap = n
                break
            }
        }

        if bestOverlap == 0 {
            // No overlap detected. Conservative: keep previous, ignore
            // next. (We could append the whole `next`, but that risks
            // duplication when WhisperKit hallucinates a different
            // transcript for the same audio.)
            return prev
        }

        // Stitch: previous (unchanged) + next's tokens after overlap.
        let newTail = nextTokens.suffix(from: bestOverlap)
        if newTail.isEmpty {
            // The overlap consumed everything in `next` — return
            // previous unchanged. Avoids a trailing space.
            return prev
        }
        return prev + " " + newTail.joined(separator: " ")
    }

    /// Tokenize a string by whitespace, dropping empty tokens.
    private static func tokenize(_ s: String) -> [String] {
        s.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Trim whitespace AND treat strings consisting only of
    /// punctuation/whitespace as empty. This makes the empty checks
    /// at the top of `merge` handle pathological inputs like
    /// `"   "` or `"..."` or `"?!?"` cleanly — without it, the
    /// tokenize step would return a single bogus token and we'd
    /// accidentally treat it as "real content".
    private static func sanitize(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        // If every character is punctuation or whitespace, it's
        // effectively empty (the user hasn't actually said anything
        // yet — WhisperKit just emitted a hesitation marker).
        let hasLetterOrDigit = trimmed.unicodeScalars.contains { scalar in
            CharacterSet.alphanumerics.contains(scalar)
        }
        return hasLetterOrDigit ? trimmed : ""
    }

    /// Are the last `n` tokens of prevTokens (case-insensitive) equal
    /// to the first `n` tokens of nextTokens?
    private static func tailsMatchHead(prevTail: [String], n: Int, nextHead: [String]) -> Bool {
        let prevStart = prevTail.count - n
        for i in 0..<n {
            let a = prevTail[prevStart + i].lowercased()
                .trimmingCharacters(in: CharacterSet.punctuationCharacters)
            let b = nextHead[i].lowercased()
                .trimmingCharacters(in: CharacterSet.punctuationCharacters)
            if a != b || a.isEmpty {
                return false
            }
        }
        return true
    }
}