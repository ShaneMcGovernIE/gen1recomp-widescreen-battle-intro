# Changelog

## [1.2.1] - 2026-08-01

### Fixed

- The fullscreen flash overlay is now state-driven: it reads the live
  battle transition from the state stack every frame instead of relying on
  a draw/endFrame pairing.  Spawn-started battles on outdoor maps (Route 1
  and 2 with Wilds of Kanto) could leave the flash in the centered
  letterbox square; the overlay now always covers the whole window while a
  transition is flashing.

## [1.2.0] - 2026-08-01

### Added

- The intro transition now plays for every battle trigger, not just
  overworld spawns: scripted trainer battles (`start_battle "trainer"`,
  the rivals, Jessie & James), the static-encounter script and the
  Viridian catch tutorial all get the standard transition instead of
  appearing with no intro at all.  The wipe selection still follows the
  vanilla bits (wild = flash + circle wipe, trainer = spiral/shrink/split).

## [1.1.0] - 2026-08-01

### Added

- Wild battles started through the `start_battle "wild"` script command —
  the path overworld-spawn mods use for touch-to-battle — now play the
  standard wild intro (flash + circle wipe) instead of appearing with no
  transition, so the fullscreen flash plays for them too.  Scripted
  trainer battles are unchanged.

## [1.0.1] - 2026-08-01

### Fixed

- Corrected the descriptions: the flash plays for wild encounters and
  battles against a stronger foe (the circle wipes), not trainer battles.
  Trainer battles use spiral / shrink / split wipes with no flash; they were
  already fullscreen and are unchanged by the mod.

## [1.0.0] - 2026-08-01

### Added

- Fullscreen flash overlay for the battle intro transition on non-4:3 windows.
