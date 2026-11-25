---
files: ["Sources/Net/**"]
symbols: [ResponseCache, store, evict]
---
## ResponseCache
`actor ResponseCache` holds at most `capacity` items; the default capacity is 100.
`func store(_ data: Data, for key: URL) async` inserts, then calls `evictIfNeeded()`.
`private func evictIfNeeded()` removes the oldest key in `order` while `items.count > capacity`.
