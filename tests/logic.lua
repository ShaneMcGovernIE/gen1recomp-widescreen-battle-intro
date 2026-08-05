-- Standalone: luajit mods/widescreen_battle_intro/tests/logic.lua
-- Asserts the mod's stated effect: the battle transition's flash phase
-- records a fullscreen shade/alpha each frame (the value the endFrame wrap
-- paints over the whole window), the zero-strength steps record nothing,
-- the wipe phase hands the window back to the engine's cascade, and the
-- FLASHLESS INTROS toggle turns every battle intro into the Champion
-- battle's flashless outward spiral.  Script-started battles are not
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

run.release()
T.finish("widescreen_battle_intro")
