# Response cache

## Step 1: ResponseCache in Sources/Net/Cache.swift

`actor ResponseCache` holds at most `capacity` items; the default capacity is 100.

- `func store(_ data: Data, for key: URL) async` inserts, then calls `evictIfNeeded()`.
- `private func evictIfNeeded()` removes the oldest key in `order` while `items.count > capacity`.
- No force unwraps.

## Step 2: Python mirror in tools/cache.py

`class Cache` keeps `self.items` (a dict) and `self.order` (a list of keys).
`put(self, key, value)` stores the value, appends the key to `self.order`, then calls `self._evict()`.
