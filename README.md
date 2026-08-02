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

## Every battle trigger

Some battles start with no transition at all: overworld spawns (mods that
run `start_battle "wild"`, like Wilds of Kanto), scripted trainer fights
(the rivals, Jessie & James) and the Viridian catch tutorial.  This mod
gives every one of them the standard intro — the flash + circle wipe for
wild battles, the spiral / shrink / split wipes for trainers — so the
fullscreen intro effect plays no matter what triggered the battle.

## Try it

```sh
# 1. install: copy the folder into the game's mods/ directory
cp -r mods/widescreen_battle_intro <game-dir>/mods/

# 2. run the game and step into tall grass — the flash now fills the window
love .

# 3. confirm it loaded: open the mod manager (or `mods` in the dev console)
```

## How it works

The engine draws the transition's flash into the classic 160x144 UI canvas
and only the wipe phase extends past the letterbox
(`Renderer:drawBattleCascade`).  This mod mirrors the engine's flash-step
math, records the shade/alpha the transition draws each frame (wrapping
`BattleTransition.draw`), and paints a full-window rect over the finished
composite (wrapping `Renderer.endFrame`).  A per-frame stamp guarantees the
overlay stops the moment the transition pops.

The out-of-battle poison pulse works the same way: the overworld's
in-canvas 0.45-alpha rect already covers the letterbox square, so the
overlay paints the same black veil only around it (the bands outside the
letterbox), keeping the flash uniform across the window.

## Compatibility

Targets the battle-transition code present since 0.1.53.  On a 4:3 window
the overlay is the same shade as the letterbox square, so vanilla is
unchanged; the wipe and black-hold phases are left to the engine's own
fullscreen cascade.
