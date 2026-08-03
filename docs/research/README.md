# Machiss multimodal research direction

## Working title

**From visible conversation to user-controlled reflection: a local-first,
provenance-aware multimodal assistant for macOS**

## Research question

Can a native Apple-platform assistant help a person reflect on a conversation
without silently turning screenshots into identity, appearance, personality, or
intent claims?

## System boundary

The owner selects what is visible. A read-only bridge captures the selected
screen. Vision/OCR extracts literal text and geometry. The owner reviews and
approves the result. Foundation Models receives only approved, typed context
and returns structured ideas with source references and uncertainty. No model
tool can send messages, swipe, like, scrape, download profiles/photos, or act
on a dating service.

## Multimodal roadmap

- Vision OCR for visible conversation text and profile prompts.
- Owner-selected image understanding for neutral descriptions such as lighting,
  crop, clothing, visible activity, and composition.
- Optional pose/composition cues limited to framing or accessibility use cases.
- No body-type classification, attractiveness scoring, health inference,
  identity recognition, protected-trait inference, personality claims, or
  intent claims from appearance or pose.
- Every image observation is preview-only until the owner approves it.

## Mirroir pilot observation — 2026-08-04

One read-only Mirroir check reported that mirroring was connected and screen
capture was available. The connected iPhone was on its home screen. OCR returned
visible interface labels and icon locations; no dating-app content was opened,
tapped, typed, or changed. This demonstrates the capture/OCR boundary, not
Foundation Models image understanding.

The next controlled experiment should use a fictional fixture image supplied by
the researcher, then compare literal Vision observations, typed Foundation
Models descriptions, and unsupported inferences rejected by the validator. Real
people and private dating photos should not be used in the public dataset.

## Evaluation dimensions

- Observation fidelity: describe only visible content.
- Provenance: point every suggestion to approved input.
- Abstention: reject unsupported identity/body/personality claims.
- Privacy: discard raw screenshots and exclude private content from artifacts.
- Agency: require owner review before saving observations or ideas.
- Utility: measure usefulness without automated action.

This is a research direction and evaluation plan, not a claim that all roadmap
capabilities are currently shipped.
