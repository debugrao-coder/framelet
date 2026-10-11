import Foundation

/// Tracks text mutations separately from recognition request cancellation.
/// An older worker must never overwrite edits made after it started.
struct OCRRevision {
    private(set) var token = UUID()
    private(set) var recognizedText = ""
    mutating func changed() { token = UUID() }
    mutating func reset() { changed(); recognizedText = "" }
    mutating func recognized(_ text: String) { recognizedText = text }
    func needsConfirmation(for text: String) -> Bool { !text.isEmpty && text != recognizedText }
    func canApply(_ snapshot: UUID) -> Bool { snapshot == token }
}
