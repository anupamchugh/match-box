# Machiss Owner Test Matrix

This matrix records only adapter kind, result, and limitations. It contains no
real profiles, messages, screenshots, or identifiers.

| Surface | Intake | Status | Evidence / limitation |
| --- | --- | --- | --- |
| Bumble Profile | Mirroir positioned/local preview | PASS | Explicit `matchProfile`; prompt/interest fields persisted and local review completed. |
| Bumble Likes | Mirroir local preview | PASS | Approved local context persisted and local review completed. |
| Bumble Chats | Mirroir local preview | PASS | Visible list classified as `bumbleChats`; preview created. |
| Bumble Thread | Mirroir positioned/local preview | PASS | Visible bubble positions produced incoming/outgoing local messages; delivery chrome discarded. |
| Bumble Profile prompt labelling | Core + bridge | PASS | Local prompt/answer/interest labelling is covered by the test suite. |
| Bumble native ScreenCaptureKit UI flow | Machiss app | NOT YET TESTED | Requires owner-visible capture, review, save, quit, and relaunch in the macOS UI. |
| Hinge Profile / Likes / Chats / Thread | Native + bridge | NOT YET TESTED | Run only when the owner displays each surface. |

## Acceptance rule

A surface is complete only after the owner-selected visible screen is captured,
reviewed, approved, persisted locally, and appears in the correct app section
after relaunch. No test may like, swipe, match, type, or send in a dating app.
