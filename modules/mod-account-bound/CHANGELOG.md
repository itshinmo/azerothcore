# Changelog

All notable changes to AccountBound are documented in this file.

## 1.1.0 - 2026-06-06

- Changed account sharing to silent database-only synchronization.
- Removed live `learnSpell()` calls for mounts and companion pets.
- Removed live replay of achievements, titles, reputations and friend lists.
- Added `SyncOnCreate` support to every shared category.
- Enabled startup friend backfill by default.
- Removed the optional achievement live-sync core patch.

## 1.0.0 - 2026-06-06

- Initial public release.
- Added account-wide achievements.
- Added account-wide mounts with riding, class and faction checks.
- Added account-wide vanity companion pets.
- Added account-wide titles.
- Added monotonic account-wide reputation sharing.
- Added account-wide profession ranks, progress and recipes.
- Added configurable support for all 11 primary professions.
- Added account-wide friend lists and notes.
- Added per-category switches, filters and startup backfill.
- Added compatibility with stock AzerothCore and mod-playerbots.
- Added optional instant achievement import patch.
