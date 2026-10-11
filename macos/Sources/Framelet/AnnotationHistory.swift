/// Bounded snapshots of annotation values only; screenshot pixels are never copied.
/// The current document is not truncated when a history entry exceeds the budget.
struct AnnotationHistory<Element> {
    private(set) var current: [Element] = []
    private var backward: [[Element]] = []
    private var forward: [[Element]] = []
    let limit: Int
    let costLimit: Int
    let cost: (Element) -> Int
    init(limit: Int = 32, costLimit: Int = 100_000, cost: @escaping (Element) -> Int) {
        self.limit = max(0, limit); self.costLimit = max(0, costLimit); self.cost = cost
    }
    var canUndo: Bool {!backward.isEmpty}
    var canRedo: Bool {!forward.isEmpty}
    mutating func replace(_ value: [Element]) {
        backward.append(current); forward.removeAll(); current = value; trim()
    }
    mutating func reset() {current = []; backward.removeAll(); forward.removeAll()}
    @discardableResult mutating func undo() -> Bool {
        guard let previous = backward.popLast() else {return false}
        forward.append(current); current = previous; trim(); return true
    }
    @discardableResult mutating func redo() -> Bool {
        guard let next = forward.popLast() else {return false}
        backward.append(current); current = next; trim(); return true
    }
    private mutating func trim() {
        // Stop counting at the cap, avoiding integer overflow on arbitrary weights.
        func overBudget() -> Bool {
            var total = 0
            for snapshot in backward + forward {
                for element in snapshot {
                    let weight = max(1, cost(element))
                    if weight > costLimit - total {return true}
                    total += weight
                }
            }
            return false
        }
        while backward.count + forward.count > limit || overBudget() {
            if !backward.isEmpty {backward.removeFirst()}
            else if !forward.isEmpty {forward.removeFirst()}
            else {break}
        }
    }
}
