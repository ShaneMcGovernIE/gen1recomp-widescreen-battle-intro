-- Standalone: luajit mods/widescreen_battle_intro/tests/logic.lua
-- Asserts the mod's stated effect: the battle transition's flash phase
-- records a fullscreen shade/alpha each frame (the value the endFrame wrap
-- paints over the whole window), the zero-strength steps record nothing,
-- and the wipe phase hands the window back to the engine's cascade.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

-- the fixture dataset: this mod only wraps engine render functions, so it
-- needs no ROM-derived base data (the suite runs in the ROM-free T4 tier)
local run = T.sdk.loadMod("mods/widescreen_battle_intro")
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

local exports = run.loader.exports.widescreen_battle_intro
T.check(exports ~= nil, "the mod exports its flash helper")
T.check(type(exports.flashFor) == "function", "flashFor is exported")

-- ------- flash step math (BattleTransition_FlashScreenPalettes)

local function expect(t, shade, alpha, label)
  local f = exports.flashFor(t)
  if shade == nil then
    T.eq(f, nil, label)
  else
    T.check(f ~= nil and f.shade == shade and f.alpha == alpha,
      label .. (" (got %s, %s)"):format(
        f and tostring(f.shade) or "nil", f and tostring(f.alpha) or "nil"))
  end
end

expect(0, 0, 1 / 3, "frame 0 fades to black a third")
expect(2, 0, 2 / 3, "frame 2 darkens to two thirds")
expect(4, 0, 1, "frame 4 is full black")
expect(6, 0, 2 / 3, "frame 6 lightens back")
expect(8, 0, 1 / 3, "frame 8 lightens further")
expect(10, nil, nil, "frame 10 is the zero-strength pause")
expect(12, 1, 1 / 3, "frame 12 fades to white a third")
expect(14, 1, 2 / 3, "frame 14 whitens to two thirds")
expect(16, 1, 1, "frame 16 is full white")
expect(18, 1, 2 / 3, "frame 18 darkens back")
expect(20, 1, 1 / 3, "frame 20 darkens further")
expect(22, nil, nil, "frame 22 is the zero-strength pause")
expect(24, 0, 1 / 3, "the 24-frame cycle wraps")

-- ------- the draw wrap records the flash the endFrame wrap will paint

local BattleTransition = require("src.render.BattleTransition")
local draw = BattleTransition.draw

-- a minimal stand-in for the engine's transition state; the flash branch
-- of the original draw only reads phase/t, the wipe branch also needs
-- wipeLen/style to reach its rectangles
local function fakeTransition(t, phase)
  return { t = t, phase = phase, wipeLen = 24, style = "split" }
end

local fake = fakeTransition(0, "flash")
draw(fake)
local recorded = exports.peekRecorded()
T.check(recorded ~= nil, "flash phase records a fullscreen shade")
T.eq(recorded.shade, 0, "black half of the cycle")
T.eq(recorded.alpha, 1 / 3, "step alpha matches the letterbox flash")

local painted = exports.tickFlash()
T.check(painted ~= nil, "the frame after a flash draw paints")
T.eq(painted.shade, 0, "painted shade is the recorded black")
T.eq(painted.alpha, 1 / 3, "painted alpha is the recorded alpha")

fake = fakeTransition(10, "flash") -- zero-strength step
draw(fake)
T.eq(exports.peekRecorded(), nil, "zero steps record nothing")
T.eq(exports.tickFlash(), nil, "zero steps paint nothing")

fake = fakeTransition(0, "wipe") -- the engine's cascade owns the window
draw(fake)
T.eq(exports.peekRecorded(), nil, "wipe phase records nothing")
T.eq(exports.tickFlash(), nil, "wipe phase paints nothing")

-- a transition that pops between its last draw and the next frame leaves a
-- stale record; the frame that drew paints, the next one must not
fake = fakeTransition(4, "flash")
draw(fake)
T.check(exports.peekRecorded() ~= nil, "flash recorded before the pop")
T.check(exports.tickFlash() ~= nil, "the frame that drew paints the flash")
T.eq(exports.tickFlash(), nil, "a popped transition paints nothing next frame")

-- ------- script-started battles get the transition (spawn-mod path)
-- The overworld spawn mod (and every scripted trainer battle, plus the
-- catch tutorial) pushes the battle with no transition.  The wrap must
-- push the standard transition instead, for every kind.

local Commands = require("src.script.Commands")
T.check(type(Commands.start_battle) == "function", "start_battle command exists")

-- stub the battle factory so the command needs no real game/data
local stubbed = {
  newWild = function(_, species, level)
    local battle = { enemy = { mon = { level = tonumber(level) or 5 } } }
    battle.makeOldManDemo = function(self) self.oldManDemo = true end
    return battle
  end,
  newTrainer = function(_, cls, index)
    return { trainer = cls, partyIndex = index }
  end,
}
local realBattleState = package.loaded["src.battle.BattleState"]
package.loaded["src.battle.BattleState"] = stubbed

local pushes = {}
local fakeGame = {
  data = { field = {} },
  save = { party = { { hp = 20, level = 5 } } },
  stack = {
    push = function(_, s) pushes[#pushes + 1] = s end,
    pop = function() end,
  },
}
local yields, resumes = 0, 0
local fakeRunner = {
  yield = function() yields = yields + 1 end,
  resume = function() resumes = resumes + 1 end,
}

local function runCommand(kind, a, b, overworld)
  pushes = {}
  local ctx = { game = fakeGame, save = fakeGame.save,
                runner = fakeRunner, overworld = overworld }
  Commands.start_battle(ctx, kind, a, b)
  return ctx
end

-- a normal overworld spawn: wild, weaker than the lead -> doublecircle
local ctx = runCommand("wild", "PIDGEY", 3)
T.eq(#pushes, 1, "wild scripted battle pushes one transition")
local transition = pushes[1]
T.check(transition and transition.phase == "flash",
  "the transition opens with the flash")
T.eq(yields, 1, "the runner yields until the battle is pushed")
for _ = 1, 200 do
    if #pushes >= 2 then break end
    transition:update(1 / 60)
  end
T.eq(#pushes, 2, "the battle is pushed once the transition finishes")
T.eq(resumes, 0, "the runner stays suspended until the battle ends")
local battle = pushes[2]
T.check(battle and battle.enemy and battle.enemy.mon.level == 3,
  "the battle is the wild spawn")
battle.onFinish("win")
T.eq(resumes, 1, "the battle finish resumes the runner")
T.eq(ctx.lastBattleResult, "win", "the finish result reaches the script ctx")

-- a stronger wild spawn -> circle wipe, still flashes
runCommand("wild", "PIDGEOT", 9)
T.check(pushes[1] and pushes[1].phase == "flash",
  "a stronger wild spawn still opens with the flash")

-- a dungeon wild spawn -> hstripes, no flash (vanilla-faithful)
runCommand("wild", "ZUBAT", 3,
  { isDungeonTransitionMap = function() return true end })
T.check(pushes[1] and pushes[1].phase == "wipe",
  "dungeon wild spawns use the non-flash wipe like vanilla")

-- scripted trainer battles get the standard trainer transition
runCommand("trainer", "OPP_RIVAL1", 1)
T.eq(#pushes, 1, "scripted trainer battle pushes one transition")
local trainerTransition = pushes[1]
T.check(trainerTransition and trainerTransition.phase == "wipe",
  "trainer wipes never flash (vanilla bits)")
for _ = 1, 200 do
    if #pushes >= 2 then break end
    trainerTransition:update(1 / 60)
  end
T.eq(#pushes, 2, "the trainer battle is pushed after the transition")
T.check(pushes[2] and pushes[2].trainer == "OPP_RIVAL1",
  "the pushed battle is the scripted trainer")

-- the Viridian catch tutorial gets the wild intro too
pushes = {}
local resumesBefore = resumes
local omCtx = { game = fakeGame, save = fakeGame.save,
                runner = fakeRunner, overworld = nil }
Commands.old_man_demo(omCtx)
T.eq(#pushes, 1, "the catch tutorial pushes one transition")
local omTransition = pushes[1]
T.check(omTransition and omTransition.phase == "flash",
  "the tutorial battle opens with the wild flash")
for _ = 1, 200 do
    if #pushes >= 2 then break end
    omTransition:update(1 / 60)
  end
T.eq(#pushes, 2, "the demo battle is pushed after the transition")
T.check(pushes[2] and pushes[2].oldManDemo, "it is the old man's demo battle")
T.eq(resumes, resumesBefore, "the runner stays suspended until the demo ends")
pushes[2].onFinish()
T.eq(resumes, resumesBefore + 1, "the demo finish resumes the runner")

package.loaded["src.battle.BattleState"] = realBattleState

run.release()
T.finish("widescreen_battle_intro")
