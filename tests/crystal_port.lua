-- Standalone from a Gen1 Recomp engine checkout:
--   luajit mods/widescreen_battle_intro/tests/crystal_port.lua
--
-- The WSB_ENGINE_ROOT/WSB_MOD_PATH overrides are for running this checkout
-- against the bundled ROM-free engine fixture without copying the mod.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local root = os.getenv("WSB_ENGINE_ROOT") or "."
local modPath = os.getenv("WSB_MOD_PATH") or "mods/widescreen_battle_intro"
require("src.core.GameVersion").set("crystal")
local run = T.sdk.loadMod(modPath, { root = root, generation = 2 })

T.check(run.mod ~= nil,
  "the mod is enabled for a Crystal/Gen2 load")
T.eq(#run.errors, 0,
  "the mod loads cleanly on a Crystal/Gen2 fixture (" ..
  tostring(run.errors[1]) .. ")")

if run.mod then
  local exports = run.loader.exports.widescreen_battle_intro
  T.check(exports ~= nil, "the Crystal load still publishes the mod exports")
  T.check(type(exports.styleFor) == "function",
    "the Crystal load still publishes styleFor")

  local Runtime = require("src.mods.Runtime")
  T.eq(Runtime.call("transition.style", function() return "vanilla" end, {}),
    "vanilla", "Crystal leaves the native transition style unchanged")
  local rows = Runtime.call("ui.options.rows", function(_, r) return r end,
                            {}, {})
  T.eq(#rows, 0, "Crystal does not expose unsupported Gen 1-only toggles")
end

run.release()
T.finish("crystal port")
