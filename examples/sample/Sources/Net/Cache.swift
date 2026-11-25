import Foundation

actor ResponseCache {
    private var items: [URL: Data] = [:]
    private var order: [URL] = []
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
    }

    convenience init() {
        self.init(
    }

    func 
}
