# Security Policy

## Supported scope

This prototype processes only owner-approved local text. It intentionally does
not accept dating-service credentials or offer remote execution.

## Reporting a vulnerability

Do not include real profile or conversation content in a report. Send a
minimal redacted reproduction to the repository owner through the repository's
private security-contact channel once one is configured. Public issues should
describe the class of problem only.

## Security boundaries

- Capture is owner-selected and one-shot.
- OCR frames are discarded after local recognition.
- Persistence is local SwiftData with CloudKit disabled.
- Foundation Models has no tools or network fallback.
- Mirroir is development-only test infrastructure, not a shipped dependency.
