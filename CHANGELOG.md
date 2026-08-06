# Changelog

## [1.5.0] - 2026-08-06

### Added

- BLACK OUTRO option in the OPTIONS menu (ON by default): when ON, the
  post-battle return fades to black — the battle fades to full black over
  about 0.6s, the screen cuts behind the black, and the map fades up out of
  it — instead of the engine's white flash.  Losses (the blackout warp to
  the last Pokemon Center) never used the white flash and are unchanged.
  Off restores the engine's white return exactly.

### Fixed

- The black outro no longer white-flashes when another mod also replaces
  the post-battle transition.  `dramatic_shape_brick`'s voxel battle exit
  wraps `BattleState:finish` too, and its wrap pushed its own fade on top
  of the battle instead of ending it — the battle froze under both fades,
  then popped late and showed the engine's white `battleReturn` veil.  The
  outro now pops any such foreign fade and re-drives the exit until the
  battle has really closed behind the black, so the map still fades up out
  of black regardless of what else wrapped the finish.

## [1.4.1] - 2026-08-05

### Fixed

- The battle flash no longer double-darkens. The engine now paints the
  flash through `Renderer.screenVeil`, which `endFrame` paints across the
  whole window, so the mod's own wrap painted the same shade again (alpha
  `1-(1-a)^2`). The wrap now defers to `screenVeil`. The poison pulse no
  longer paints over the post-battle white fade either.
- Dropped the `Commands.start_battle` and `Commands.old_man_demo`
  overrides: the engine's `OverworldState:pushBattle` now owns scripted
  battle transitions and their music, and `old_man_demo` had silently
  dropped the `failThrow` argument Yellow's catch training needs.

### Changed

- Dead `src.render.BattleTransition` require and `defaultFlashless` export
  removed; README updated to the engine's current render names.

## [1.4.0] - 2026-08-03

### Added

- FLASHLESS INTROS option in the OPTIONS menu: when ON, every battle intro
  plays the Champion battle's intro — the flashless outward spiral —
  instead of the per-context wipe.  Applies to every battle trigger:
  overworld spawns, scripted trainer battles, the catch tutorial, and
  dungeon or stronger-foe wipes alike.

## [1.3.0] - 2026-08-02

### Added

- The out-of-battle poison damage pulse now plays fullscreen: every fourth
  step with a poisoned party member, the dark 0.45-alpha flash covers the
  whole window instead of the centered 160x144 square.  The veil is drawn
  only around the letterbox (the engine's in-canvas rect already darkens
  the square), so the flash is uniform across the window at any zoom.

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
