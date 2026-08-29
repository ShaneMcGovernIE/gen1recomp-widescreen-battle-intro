-- Standalone: luajit mods/widescreen_battle_intro/tests/logic.lua
-- Asserts the mod's stated effect: the battle transition's flash phase
-- records a fullscreen shade/alpha each frame (the value the endFrame wrap
-- paints over the whole window), the zero-strength steps record nothing,
-- the wipe phase hands the window back to the engine's cascade, and the
-- FLASHLESS INTROS toggle turns every battle intro into the Champion
-- battle's flashless outward spiral.  The BLACK OUTRO toggle (on by
-- default) replaces the engine's white post-battle return with a slow fade
-- to black: the fade state's choreography -- out over the battle's last
-- live frame, the engine finish behind full black, the map up out of it --
-- is driven headlessly on a fake stack.  Script-started battles are not
-- exercised here: the engine routes them through OverworldState:pushBattle
-- (f109530), which pushes the transition and starts the battle music, and
-- the mod's transition.style hook governs their wipe through that path.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

-- the fixture dataset: this mod only wraps engine render functions, so it
-- needs no ROM-derived base data (the suite runs in the ROM-free T4 tier)
local run = T.sdk.loadMod("mods/widescreen_battle_intro")
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

local exports = run.loader.exports.widescreen_battle_intro
T.check(exports ~= nil, "the mod exports its flash helper")
T.check(type(exports.flashFor) == "function", "flashFor is exported")

-- ------- the FLASHLESS INTROS toggle
-- Runs first: the mod's closures captured the module table loaded at
-- loadMod time; the activeFlash tests below replace and nil
-- package.loaded["src.core.Game"], so requiring it again here would grab a
-- different table and the toggle reads would go dead.

-- pure style resolution: ON forces the champion spiral for every context,
-- OFF is the vanilla 3-bit selection
T.eq(exports.styleFor(true, {}), "spiralout",
  "toggle ON: wild spawn -> the champion spiral")
T.eq(exports.styleFor(true, { trainer = true, dungeon = true }), "spiralout",
  "toggle ON: dungeon trainer battles too")
T.eq(exports.styleFor(false, {}), "doublecircle",
  "toggle OFF: vanilla wild bits")
T.eq(exports.styleFor(false, { stronger = true }), "circle",
  "toggle OFF: stronger wild -> circle")
T.eq(exports.styleFor(false, { trainer = true }), "spiralin",
  "toggle OFF: plain trainer -> spiral in")
T.eq(exports.styleFor(false, { trainer = true, stronger = true }), "spiralout",
  "toggle OFF: the champion ctx resolves to spiralout anyway")
T.eq(exports.styleFor(false, { dungeon = true }), "hstripes",
  "toggle OFF: dungeon wild -> hstripes")

-- the transition.style hook honours the toggle (BattleTransition.new asks
-- it for the wipe on every battle, so one wrap covers every trigger)
local Game = require("src.core.Game")
Game.mods = run.loader
local Runtime = require("src.mods.Runtime")
local vanillaStyle = function(ctx) return exports.styleFor(false, ctx) end
T.eq(Runtime.call("transition.style", vanillaStyle, {}), "doublecircle",
  "hook passes the vanilla wipe through when OFF")
run.loader.modOptions = { widescreen_battle_intro = { flashless_intros = true } }
T.eq(Runtime.call("transition.style", vanillaStyle, {}), "spiralout",
  "hook forces the champion spiral when ON")
T.eq(Runtime.call("transition.style", vanillaStyle,
                  { trainer = true, dungeon = true }), "spiralout",
  "dungeon trainer battles are flashless when ON")
run.loader.modOptions = nil

-- the OPTIONS row rides the ui.options.rows hook
local optionRows = Runtime.call("ui.options.rows", function(_, r) return r end,
                                {}, {})
local toggleRow
for _, row in ipairs(optionRows) do
  if row.id == "flashless_intros" then toggleRow = row break end
end
T.neq(toggleRow, nil, "the FLASHLESS INTROS row joins the options menu")
T.eq(toggleRow.label, "FLASHLESS INTROS", "row label")
T.eq(toggleRow.value(), "OFF", "defaults to OFF")
run.loader.modOptions = { widescreen_battle_intro = { flashless_intros = false } }
toggleRow.step()
T.eq(run.loader.modOptions.widescreen_battle_intro.flashless_intros, true,
  "stepping the row flips the persisted bucket")
T.eq(toggleRow.value(), "ON", "the row shows ON after the flip")
toggleRow.step()
T.eq(run.loader.modOptions.widescreen_battle_intro.flashless_intros, false,
  "stepping again flips back")
T.eq(toggleRow.value(), "OFF", "the row shows OFF again")
run.loader.modOptions = nil

-- ------- the BLACK OUTRO toggle (the battle exit fades to black)

-- the rows captured earlier already include the outro row -- the mod
-- registers both at load; its get/set read the loader live, so the flip
-- below works against the same bucket the flashless tests used
local outroRow
for _, row in ipairs(optionRows) do
  if row.id == "black_outro" then outroRow = row break end
end
T.neq(outroRow, nil, "the BLACK OUTRO row joins the options menu")
T.eq(outroRow.label, "BLACK OUTRO", "outro row label")
T.eq(outroRow.value(), "ON", "defaults to ON (the fade is the point)")
outroRow.step()
T.eq(run.loader.modOptions.widescreen_battle_intro.black_outro, false,
  "stepping the row persists the flip")
T.eq(outroRow.value(), "OFF", "the row shows OFF after the flip")
outroRow.step()
T.eq(run.loader.modOptions.widescreen_battle_intro.black_outro, true,
  "stepping again flips back")
T.eq(outroRow.value(), "ON", "the row shows ON again")
run.loader.modOptions = nil

-- ------- the battle exit: fade to black instead of the white return

-- veil math: 0 on the battle's live frame -> 1 at the cut -> 0 back
local oa = exports.outroAlpha
T.check(type(oa) == "function", "outroAlpha is exported")
T.eq(oa("out", 0, 36), 0, "fade-out starts clear")
T.eq(oa("out", 18, 36), 0.5, "fade-out midpoint is half black")
T.eq(oa("out", 36, 36), 1, "fade-out ends full black")
T.eq(oa("in", 0, 36), 1, "fade-in starts full black")
T.eq(oa("in", 36, 36), 0, "fade-in ends clear")
T.eq(oa("out", 99, 36), 1, "overshoot clamps at black")
T.eq(oa("in", 99, 36), 0, "overshoot clamps at clear")

-- which endings get the fade: every non-lose end that goes through the
-- engine's white battleReturn, and nothing else
local ow = exports.outroWanted
T.check(type(ow) == "function", "outroWanted is exported")
T.eq(ow(nil), false, "no battle: no fade")
T.eq(ow({}), false, "battle without a game: no fade")
local g0 = { stack = {} }
T.eq(ow({ result = "lose", game = g0 }), false,
  "lose keeps the blackout warp untouched")
T.eq(ow({ result = "win", payDay = 100, game = g0 }), false,
  "the PAY DAY false start passes through")
T.eq(ow({ result = "win", game = g0 }), true, "win fades to black")
T.eq(ow({ result = "run", game = g0 }), true, "run fades to black")
T.eq(ow({ result = "caught", game = g0 }), true, "caught fades to black")

-- the fade state's own choreography: fade out over the battle's last live
-- frame, run the engine finish at full black, re-cover the white return it
-- pushed, fade the map up, then hand the map back the way the return's
-- onDone would
local overworld = { id = "overworld" }
local function makeStack(initial)
  local states = initial or { overworld }
  return {
    states = states,
    push = function(self, s) states[#states + 1] = s end,
    pop = function(self)
      local s = states[#states]
      states[#states] = nil
      return s
    end,
    top = function(self) return states[#states] end,
  }
end
local midpoints = 0
local finished = 0
local stackA = makeStack()
local gameA = { stack = stackA, overworld = overworld }
local battleReturn = {
  onDone = function() finished = finished + 1 end,
}
local fade = exports.outroFade(gameA, {}, function()
  midpoints = midpoints + 1
  -- what BattleState:finish does for a non-lose result: the battle pops
  -- itself, then the engine pushes the white battleReturn
  stackA:pop()
  stackA:push(battleReturn)
end, 4, 3)
stackA:push({ id = "battle" })
stackA:push(fade)

for _ = 1, 3 do fade:update() end
T.eq(fade.phase, "out", "still fading the battle out")
T.eq(stackA:top(), fade, "the fade sits on top through the fade-out")
fade:update() -- t reaches the out frames: the cut
T.eq(midpoints, 1, "the engine finish runs once, at full black")
T.eq(fade.phase, "in", "the map now fades up out of black")
T.eq(stackA:top(), fade, "re-pushed to cover the white return")
local veil = {}
gameA.renderer = veil
fade:draw()
T.check(veil.screenVeil and veil.screenVeil[1] == 0, "the veil is black")
T.eq(veil.screenVeil[2], 1, "full black at the start of the fade-in")
for _ = 1, 2 do fade:update() end
T.eq(stackA:top(), fade, "still fading in")
fade:update() -- t reaches the in frames: done
T.eq(stackA:top(), overworld, "fade and white return both popped")
T.eq(finished, 1, "the white return's onDone hands the map back")

-- a battle that does not come back through a white return (a blackout's
-- own warp, a second finish()): the fade ends at the cut, no fade-in
local midpoints2 = 0
local stackB = makeStack()
local gameB = { stack = stackB, overworld = overworld }
local fade2 = exports.outroFade(gameB, {}, function()
  midpoints2 = midpoints2 + 1
  stackB:pop() -- the battle pops; nothing replaces it
end, 2, 2)
stackB:push({ id = "battle" })
stackB:push(fade2)
fade2:update() -- t=1
T.eq(stackB:top(), fade2, "still on top before the cut")
fade2:update() -- t=2: the cut
T.eq(midpoints2, 1, "midpoint still runs")
T.eq(stackB:top(), overworld, "no white return: ends at the cut")

-- another fade mod wrapped BattleState:finish too (dramatic_shape_brick's
-- voxel battle exit): its wrap runs instead of the battle closing and
-- pushes ITS fade on top -- the battle would sit under our fade-in and the
-- map would never show.  Our fade pops that fade and re-drives the exit
-- until the battle is really gone.
local midpoints3 = 0
local finished3 = 0
local stackD = makeStack()
local gameD = { stack = stackD, overworld = overworld }
local battleD = { id = "battle" }
local foreignFade = { phase = "out", id = "dsb exit" }
local leaving = false
local battleReturn3 = {
  onDone = function() finished3 = finished3 + 1 end,
}
local fade3 = exports.outroFade(gameD, battleD, function()
  midpoints3 = midpoints3 + 1
  if not leaving then
    -- first drive: the foreign mod's wrap pushes its own fade and returns
    -- without closing the battle
    leaving = true
    stackD:push(foreignFade)
    return
  end
  -- re-drive: the foreign wrap passes through to the engine finish, which
  -- pops the battle and pushes the white battleReturn
  stackD:pop()
  stackD:push(battleReturn3)
end, 2, 2)
stackD:push(battleD)
stackD:push(fade3)
fade3:update() -- t=1
fade3:update() -- t=2: the cut
T.eq(midpoints3, 2, "the foreign fade gets popped and the exit re-driven")
T.check(stackD:top() == fade3, "re-pushed over the white return to fade in")
for i, s in ipairs(stackD.states) do
  T.check(s ~= foreignFade, "the foreign fade is gone, not stacked under ours")
end
fade3:update() -- t=3: still fading the map in
fade3:update() -- t=4: fade-in done
T.eq(stackD:top(), overworld, "battle and white return both popped")
T.eq(finished3, 1, "the white return's onDone still hands the map back")

-- the finish() wrap: an ON battle pushes the fade instead of the white cut
local BattleState = require("src.battle.BattleState")
T.eq(BattleState.wsbBattleOutroHook, true, "the BLACK OUTRO hook is installed")
run.loader.modOptions = { widescreen_battle_intro = { black_outro = true } }
local stackC = makeStack()
local gameC = { stack = stackC, overworld = overworld }
local fakeBattle = setmetatable({ result = "win", game = gameC }, BattleState)
BattleState.finish(fakeBattle)
local pushed = stackC:top()
T.check(pushed and pushed.phase == "out" and pushed.frames == 36,
  "finish pushes the 36-frame fade over the battle")
T.eq(fakeBattle.wsbBattleOutro, true, "the battle is flagged while the fade runs")

-- Level-up evolution belongs to BattleState:finish.  The black outro must
-- let that check push and complete its evolution screen before it starts
-- fading; otherwise the fade's foreign-state cleanup mistakes the evolution
-- state for another fade and pops it.
local originalEvolution = package.loaded["src.pokemon.Evolution"]
local evolutionDone
local evolutionState = { id = "evolution" }
package.loaded["src.pokemon.Evolution"] = {
  checkParty = function(game, onDone)
    evolutionDone = onDone
    game.stack:push(evolutionState)
    return 1
  end,
}
local stackE = makeStack()
local gameE = { stack = stackE, overworld = overworld }
local evolvingBattle = setmetatable({ result = "win", game = gameE }, BattleState)
stackE:push(evolvingBattle)
BattleState.finish(evolvingBattle)
T.check(stackE:top() == evolutionState,
  "black outro leaves the level-up evolution state active")
T.eq(evolvingBattle.wsbBattleOutroPending, true,
  "black outro waits for evolution before starting its fade")
if evolutionDone then
  stackE:pop()
  evolutionDone()
  local evolutionFade = stackE:top()
  T.check(evolutionFade and evolutionFade.phase == "out"
          and evolutionFade.frames == 36,
    "black outro starts after level-up evolution completes")
end
package.loaded["src.pokemon.Evolution"] = originalEvolution
run.loader.modOptions = nil

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
  return exports.activeFlash(nil, { stack = { states = states } })
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
  local game = {
    stack = { states = over or { { poisonFlash = poisonFlash } } },
  }
  return exports.activeFlash(renderer, game)
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

run.release()
T.finish("widescreen_battle_intro")
