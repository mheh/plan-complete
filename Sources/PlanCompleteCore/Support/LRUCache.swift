struct LRUCache<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    let capacity: Int
    private var values: [Key: Value] = [:]
    private var order: [Key] = []

    init(capacity: Int) { self.capacity = capacity }

    mutating func value(for key: Key) -> Value? {
        guard let value = values[key] else { return nil }
        touch(key)
        return value
    }

    mutating func set(_ value: Value, for key: Key) {
        if values[key] == nil, values.count >= capacity, let oldest = order.first {
            order.removeFirst()
            values[oldest] = nil
        }
        values[key] = value
        touch(key)
    }

    mutating func removeAll() { values.removeAll(); order.removeAll() }

    private mutating func touch(_ key: Key) {
        if let index = order.firstIndex(of: key) { order.remove(at: index) }
        order.append(key)
    }
}
