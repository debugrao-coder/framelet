import Foundation

/// Saves acknowledge an exact document revision, never later edits or another document.
struct DocumentSaveState {
    struct Token: Equatable {let document: UUID; let revision: UInt64}
    private var document = UUID()
    private var revision: UInt64 = 0
    private var savedRevision: UInt64? = 0
    var token: Token {Token(document:document,revision:revision)}
    var isDirty: Bool {savedRevision != revision}
    mutating func reset(needsSave: Bool) {document = UUID();revision = 0;savedRevision = needsSave ? nil:0}
    mutating func edited() {revision &+= 1}
    @discardableResult mutating func saved(_ snapshot: Token) -> Bool {
        guard snapshot == token else {return false}
        savedRevision = revision;return true
    }
}
