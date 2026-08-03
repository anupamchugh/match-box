# Machiss launch checklist

Machiss is ready for a private alpha when the local app can be built and
tested. Public launch requires the additional release gates below.

## Product promise

Machiss is a local-first macOS conversation workspace. The owner selects a
visible screen, reviews literal observations, saves only approved context, and
asks an on-device model for ideas. It does not send messages, swipe, like,
scrape, bulk-download profiles or photos, or sync private conversations.

## Required before public launch

- [x] Add a first-run onboarding path for optional owner context.
- [ ] Add explicit clear-history and delete-capture controls.
- [x] Resolve duplicate captures in the UI before generating conversation ideas.
- [ ] Verify the full conversation timeline is readable without truncation.
- [ ] Ship a real app icon and signed/notarized release artifact.
- [x] Add a short privacy policy and platform-policy boundary.
- [x] Use only fictional dating-app fixtures and generated workflow artwork in public assets.
- [ ] Verify GitHub Actions on the supported macOS runner.
- [ ] Run the owner test matrix for the native ScreenCaptureKit flow.
- [x] Add accessible labels and identifiers to the primary Mac workflow controls.

The app’s stable UI vocabulary is centralized in `MatchBoxCopy` and backed by
the app target’s `Localizable.xcstrings`. Foundation Model instructions remain
separate from UI copy and are tested as model behavior.

## Evidence currently available

- Swift test suite: 51 tests passed in the last verified run.
- Release build: passed in the last verified run.
- `git diff --check`: passed in the last verified run.
- Apple Time Profiler trace captured locally; it is diagnostic evidence, not a
  performance sign-off.
- Mirroir remains a development/owner-selected read-only bridge.

## Public launch sequence

1. Review the sanitized diff and repository contents locally.
2. Push a confirmed branch to GitHub and open a draft pull request.
3. Publish a technical Show HN only when a stranger can run the app or inspect
   a complete reproducible demo.
4. Publish on Product Hunt after the signed app, screenshots, demo, privacy
   copy, and support path are ready.

The public demo may describe a generic dating-app workflow inspired by common
conversation patterns. It must not include real dating profiles, names, photos,
messages, service screenshots, local paths, account identifiers, or private
prompts. Bumble/Hinge testing remains owner-selected and read-only on the local
Mac only.
