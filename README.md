# Widescreen Battle Intro

On windows wider than 4:3, the flash at the start of the battle intro
(trainer battles' circle wipes) used to play inside a centered 160x144
square; this mod extends the flash across the entire window.

## Try it

```sh
# 1. install: copy the folder into the game's mods/ directory
cp -r mods/widescreen_battle_intro <game-dir>/mods/

# 2. run the game and start a trainer battle — the flash now fills the window
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

## Compatibility

Targets the battle-transition code present since 0.1.53.  On a 4:3 window
the overlay is the same shade as the letterbox square, so vanilla is
unchanged; the wipe and black-hold phases are left to the engine's own
fullscreen cascade.
