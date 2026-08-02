# Contributing to Match Box

Match Box is a privacy-first, read-only local companion. Contributions must
preserve these boundaries: no dating-service APIs, login, background polling,
network LLM fallback, messaging, likes, swipes, matching, or automation.

## Local checks

```sh
swift test
swift build --product match-inbox
swift build --product MatchInboxApp
```

Use only fictional/redacted fixtures in commits, issues, screenshots, and pull
requests. Never commit a captured screen, real profile, real conversation,
local Match Box store, or credentials.

## Contribution shape

- Add a focused test before behavior changes.
- Keep capture adapters typed, local, and review-before-save.
- Treat unrecognized/partial OCR as uncertain rather than inventing data.
- Keep Foundation Models output source-grounded; uncited output must fall back
  locally.
