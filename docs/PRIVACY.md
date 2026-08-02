# Match Box Privacy

Match Box is a local macOS companion for reviewing visible dating-app context.

## What it reads

Only a window you explicitly choose to capture. The current prototype looks for
the visible iPhone Mirroring window, recognizes text locally with Vision, and
shows it for approval.

## What it stores

Only text you explicitly approve for saving: visible observations, the source
app/screen label, capture time, and locally saved conversation/profile context.
The capture frame is discarded after local OCR. Match Box stores approved data
in its own local SwiftData store and does not use CloudKit.

## Delete local data

In the current prototype, approved history is stored at
`~/Library/Application Support/MatchBox/MatchBox.store`. Removing that store
while Match Box is closed removes the local Match Box history. This is a
developer-stage deletion path; a released app must expose a clear in-app
delete-history control before distribution.

## What it does not do

Match Box has no dating-service login, API integration, background monitoring,
message sending, likes, swipes, matches, contact actions, analytics, accounts,
or cloud-sync feature.

## On-device intelligence

When available, the optional review uses Apple Foundation Models with only the
already-approved local observations. A deterministic local fallback is used if
the model is unavailable or fails. The review is advisory and must preserve
unknowns; it is never an instruction to send a message or take an action.

## Before public release

This document is a draft for the prototype. A public release still requires a
final privacy-policy URL, in-app deletion UX, signed distribution build, and a
manual owner acceptance test using fictional demo data.
