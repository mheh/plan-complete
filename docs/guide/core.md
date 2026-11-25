---
files: ["Sources/PlanCompleteCore/**"]
symbols: [GuideChunk, GuideSelector, CompletionProvider, Engine]
priority: 1
---
## Guide types
`struct GuideChunk: Sendable, Equatable { var source: String; var heading: String?; var files: [String]; var symbols: [String]; var priority: Int; var text: String }`
Chunks come from `Guide.parse(markdown:source:)`. One chunk per `## ` section.

## Providers
`protocol CompletionProvider: Sendable { func complete(_ request: CompletionRequest) async throws -> String }`
Providers never retry. Cancellation comes from the calling Task. No force unwraps.
