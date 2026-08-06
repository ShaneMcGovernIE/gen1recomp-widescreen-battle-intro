# Widescreen Battle Intro

On windows wider than 4:3, the flash that opens the battle intro for wild
encounters — and for battles against a foe at least 3 levels above your
lead — used to play inside a centered 160x144 square; this mod extends that
flash across the entire window.  It also extends the dark pulse of
out-of-battle poison damage the same way: every fourth step with a poisoned
party member, the screen darkens across the whole window instead of just
the centered square.

The flash only plays for the circle wipes, which are exactly those two
cases.  Trainer battles use spiral / shrink / split wipes that have no
flash and were already fullscreen via the engine's own cascade.

## Flashless intros

The OPTIONS menu gains a FLASHLESS INTROS toggle.  ON plays every battle
intro the way the Champion battle does: the outward spiral, straight to
the wipe with no flash — for wild encounters, trainers, dungeon fights,
scripted battles and the catch tutorial alike.  The setting persists in
options.lua, so it survives NEW GAME, CONTINUE and quitting.

## Every battle trigger

Every battle trigger — overworld spawns (mods that run `start_battle
"wild"`, like Wilds of Kanto), scripted trainer fights (the rivals, Jessie
& James) and the Viridian catch tutorial — routes through the engine's
`OverworldState:pushBattle`, which pushes the standard transition and
starts the battle music.  This mod's `transition.style` hook still governs
the wipe they play (the FLASHLESS INTROS option included), so the
fullscreen intro effect plays no matter what triggered the battle.

## Black outro

When a battle ends, the engine returns to the map through a white flash —
a short hold, then a fade from white over roughly a third of a second.
This mod replaces that with a slow fade to black: the battle fades to full
black (about 0.6s), the screen cuts behind the black, and the map fades up
out of it.  The BLACK OUTRO option in OPTIONS — ON by default — turns the
behaviour on and off; the setting persists in options.lua like the other
toggles.  A loss (the blackout warp to the last Pokemon Center) is
untouched: it never used the white flash.

The fade also survives other mods that replace the post-battle transition
(such as `dramatic_shape_brick`'s voxel battle exit): if another fade has
been pushed on top of the battle at the cut, the outro pops it and drives
the battle's real exit behind the black, so the map still comes up out of
black rather than a white flash.

## Try it

```sh
# 1. install: copy the folder into the game's mods/ directory
cp -r mods/widescreen_battle_intro <game-dir>/mods/

# 2. run the game and step into tall grass — the flash now fills the window
love .

# 3. confirm it loaded: open the mod manager (or `mods` in the dev console)
```

## How it works

The engine draws the battle transition's flash over the whole surface
itself — `BattleTransition.draw` hands it to the renderer as a screen-space
veil (`Renderer.screenVeil`), which `Renderer.endFrame` paints across the
window.  This mod's `Renderer.endFrame` wrap asks the state stack whether a
battle transition is flashing right now, and only paints its own overlay
when the engine drew no veil that frame — the out-of-battle poison pulse
and old-engine / buried-transition flashes — so the engine's fullscreen
flash is never double-darkened.  The overlay's shade/alpha mirrors the
engine's flash-step math exactly, and it stops the moment the transition
pops.

The out-of-battle poison pulse works the same way: the overworld's
in-canvas 0.45-alpha rect already covers the letterbox square, so the
overlay paints the same black veil only around it (the bands outside the
letterbox), keeping the flash uniform across the window.

## Compatibility

Targets the battle-transition code present since 0.1.53.  On a 4:3 window
the overlay is the same shade as the letterbox square, so vanilla is
unchanged; the wipe and black-hold phases are left to the engine's own
fullscreen cascade.
