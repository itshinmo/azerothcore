---
description: Journal dungeon/raid card previews render white/untextured for some bosses (e.g. Gilnid)
owner: implementer + server-operator
status: blocked
related: local-server-setup
created: 2026-11-21
---

# White boss models in the journal

## Context

Owner reported journal preview models rendering white for some bosses. Previews are client-side
(`model:SetCreature(entry)` through the client's creature cache); the server feeds only records.
The client is the WoSSilicon Ascension bundle: patch-A carries the Ascension model pack and glue
screens; patch-S was deleted (Orgrimmar performance) and may have owned textures the pack expects.

## Findings / hypotheses

- The broken models never appear textured in stock 3.3.5a either — likely missing textures in the
  Ascension model replacements, not a journal bug.
- Pinning server display ids in `HandleCreatureRecords` could bypass replaced models per creature.

## Open questions

- Which bosses/items reproduce it, and is it stable per creature entry?
- Does the client-patch pipeline own the fix, or does the journal need a display-id pin list?

## To promote on resolution

- Client-patch pipeline: `specs/content-pipeline.md` + a `client-patch-and-extract` skill.
- If display-id pinning wins: the pin list lives with the journal module's data.
