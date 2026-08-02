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

-- ------- the overlay is state-driven: it reads the live stack

local function withStack(states)
  package.loaded["src.core.Game"] = { stack = { states = states } }
  return exports.activeFlash()
end
local function transition(t, phase)
  return { t = t, phase = phase, wipeLen = 40 }
end

T.eq(withStack({}), nil, "no states, no overlay")

local flash = withStack({ transition(4, "flash") })
T.check(flash ~= nil and flash.shade == 0 and flash.alpha == 1,
  "a live flash transition yields its shade/alpha")

local weak = withStack({ transition(0, "flash") })
T.check(weak ~= nil and weak.alpha == 1 / 3,
  "the step matches the frame the letterbox shows")

T.eq(withStack({ transition(10, "flash") }), nil,
  "zero-strength steps yield nothing")

T.eq(withStack({ transition(0, "wipe") }), nil,
  "wipe phase yields nothing (the engine's cascade owns the window)")

-- the transition may sit below another state (a text box, a menu)
local buried = withStack({ { phase = "menu" }, transition(4, "flash") })
T.check(buried ~= nil and buried.shade == 0,
  "the overlay finds the transition below other states")

-- warp fades and the white flash must never match (they carry no wipeLen)
T.eq(withStack({ { phase = "out", t = 5 } }), nil,
  "a warp fade does not paint the battle flash")
T.eq(withStack({ { t = 3, frames = 7 } }), nil,
  "the white flash does not paint the battle flash")

package.loaded["src.core.Game"] = nil
T.eq(exports.activeFlash(), nil, "no game module, no overlay")

-- ------- the out-of-battle poison pulse gets the same veil

-- the engine decrements at the top of draw, then pulses when
-- floor(v/4) is odd; the endFrame overlay reads the post-decrement value,
-- so it sees 11..1 and the four dark frames are values 7..4
local pf = exports.poisonFlash
T.check(type(pf) == "function", "poisonFlash is exported")
T.eq(pf(nil), nil, "no state: no pulse")
T.eq(pf({}), nil, "unpoisoned state: no pulse")
T.eq(pf({ poisonFlash = 0 }), nil, "expired counter: no pulse")
for v = 12, 1, -1 do
  local expected = (v - 1) >= 4 and (v - 1) <= 7
  local flash = pf({ poisonFlash = v - 1 })
  if expected then
    T.check(flash ~= nil and flash.shade == 0 and flash.alpha == 0.45,
      ("pulse frame %d (%s, %s)"):format(v,
        flash and tostring(flash.shade) or "nil",
        flash and tostring(flash.alpha) or "nil"))
  else
    T.eq(flash, nil, "off frame " .. v)
  end
end

-- a fake renderer that mirrors Renderer:fitScale/uiSize, plus a
-- widescreen window: the veil is the bands around the centered letterbox
local savedDims = love.graphics.getDimensions
local savedPx = love.graphics.getPixelDimensions
love.graphics.getDimensions = function() return 1280, 720 end
love.graphics.getPixelDimensions = function() return 1280, 720 end
local renderer = {
  fitScale = function() return 5 end,
  uiSize = function() return 160, 144 end,
}
T.check(type(exports.letterboxBands) == "function",
  "letterboxBands is exported")
local bands = exports.letterboxBands(renderer)
T.eq(#bands, 2, "widescreen: two side bands")
local left, right
for _, band in ipairs(bands) do
  if band[1] == 0 then left = band else right = band end
end
T.eq(table.concat(left, ","), "0,0,240,720", "left band")
T.eq(table.concat(right, ","), "1040,0,240,720", "right band")

-- a 4:3 window: the letterbox is the whole window, nothing to add
love.graphics.getDimensions = function() return 640, 480 end
love.graphics.getPixelDimensions = function() return 640, 480 end
T.eq(#exports.letterboxBands(renderer), 0, "4:3: no bands")

-- an unreadable renderer falls back to nil (full-window veil)
love.graphics.getDimensions = function() return 1280, 720 end
love.graphics.getPixelDimensions = function() return 1280, 720 end
T.eq(exports.letterboxBands(nil), nil, "no renderer: nil, full-window")
love.graphics.getDimensions = savedDims
love.graphics.getPixelDimensions = savedPx

-- a poisoning overworld on the stack yields the banded poison veil
local function withPoison(poisonFlash, over)
  package.loaded["src.core.Game"] = {
    stack = { states = over or { { poisonFlash = poisonFlash } } },
  }
  return exports.activeFlash(renderer)
end
local pflash = withPoison(6)
T.check(pflash ~= nil and pflash.shade == 0 and pflash.alpha == 0.45,
  "poison pulse detected through the stack")
T.eq(type(pflash.bands), "table", "poison veil is banded")
T.eq(withPoison(9), nil, "off-pulse frame: no overlay")

-- a battle transition outranks a lingering poison counter (a transition
-- is pushed on top of the overworld, so it is the last stack entry)
local intro = withPoison(nil, {
  { poisonFlash = 6 },
  transition(4, "flash"),
})
T.check(intro ~= nil and intro.shade == 0, "battle flash wins over poison")
T.eq(intro.bands, nil, "battle flash is full-window, not banded")
package.loaded["src.core.Game"] = nil


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
for _ = 1, 300 do
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
for _ = 1, 300 do
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
for _ = 1, 300 do
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
