-- Widescreen Battle Intro
--
-- The into-battle transition opens with the palette flash
-- (BattleTransition_FlashScreenPalettes) for the two circle wipes, then
-- wipes the screen.  The engine draws both phases into the classic 160x144
-- UI canvas, and only the wipe phase extends past the letterbox
-- (Renderer:drawBattleCascade).  On any window wider than 4:3 the flash
-- therefore plays inside a centered square while the frozen overworld
-- shows around it.
--
-- This mod extends the flash across the whole window:
--   * wrapping BattleTransition.draw records the shade/alpha the engine is
--     drawing this frame (same step math, same self.t), and
--   * wrapping Renderer.endFrame paints one full-window rect with that
--     shade/alpha after the frame has composited, in screen space.
--
-- The record is stamped per rendered frame, so once the transition has
-- popped (or on a frame where nothing drew) nothing is painted, and the
-- wipe and black-hold phases are left to the engine's own fullscreen
-- cascade untouched.  On a 4:3 window the overlay is the same shade the
-- letterbox square already shows, so vanilla is unchanged there.

local BattleTransition = require("src.render.BattleTransition")
local Renderer = require("src.render.Renderer")

-- BattleTransition_FlashScreenPalettes constants
-- (src/render/BattleTransition.lua): one palette step every FLASH_HOLD
-- frames; the first six steps fade to black (positive strength), the last
-- six back to white (negative), and the two zero steps mean "no flash on
-- screen that frame".
local FLASH_HOLD = 2
local FLASH_STEPS = {
  1 / 3, 2 / 3, 1, 2 / 3, 1 / 3, 0,
  -1 / 3, -2 / 3, -1, -2 / 3, -1 / 3, 0,
}

-- The flash the engine draws at frame t: { shade, alpha }, or nil when the
-- step is a zero-strength pause.
local function flashFor(t)
  local step = math.floor(t / FLASH_HOLD) % #FLASH_STEPS + 1
  local v = FLASH_STEPS[step]
  if v == 0 then return nil end
  return { shade = v > 0 and 0 or 1, alpha = math.abs(v) }
end

return function(mod)
  local recorded = nil -- { shade, alpha, stamp } or nil
  local frame = 0      -- bumped once per rendered frame by the endFrame wrap

  local originalDraw = BattleTransition.draw
  function BattleTransition.draw(self)
    -- record what the engine is about to draw, from its own t, so the
    -- overlay stays frame-locked to the letterbox flash
    if self.phase == "flash" then
      local flash = flashFor(self.t)
      recorded = flash
          and { shade = flash.shade, alpha = flash.alpha, stamp = frame }
          or nil
    else
      -- wipe / black-hold: the engine's cascade owns the window
      recorded = nil
    end
    return originalDraw(self)
  end

  local originalEndFrame = Renderer.endFrame
  function Renderer.endFrame(self, ...)
    frame = frame + 1
    local flash = recorded
    if flash and flash.stamp ~= frame - 1 then
      flash = nil -- stale: the transition popped since its last draw
      recorded = nil
    end
    local result = originalEndFrame(self, ...)
    if flash then
      local g = love and love.graphics
      if g and g.getDimensions and g.setColor and g.rectangle then
        local ww, wh = g.getDimensions()
        g.push("all")
        g.setShader()
        g.setColor(flash.shade, flash.shade, flash.shade, flash.alpha)
        g.rectangle("fill", 0, 0, ww, wh)
        g.pop()
      end
    end
    return result
  end

  -- Script-started battles -- the overworld spawn mod's touch-to-battle
  -- path, scripted trainer fights (the rivals, Jessie & James) and the
  -- static-encounter script -- push the battle straight onto the stack
  -- with no transition, so the intro never plays.  Give every one of them
  -- the same transition the engine's pushBattle uses (flash + circle wipe
  -- for wild spawns, spiral / shrink / split wipes for trainers), so the
  -- intro effect plays fullscreen no matter what triggered the battle.
  -- The wipe selection still follows the vanilla bits.
  local Commands = require("src.script.Commands")
  local originalStartBattle = Commands.start_battle
  function Commands.start_battle(ctx, kind, a, b)
    local BattleState = require("src.battle.BattleState")
    local BattleTransition = require("src.render.BattleTransition")
    local runner = ctx.runner
    local battle
    if kind == "wild" then
      battle = BattleState.newWild(ctx.game, a, b)
    else
      battle = BattleState.newTrainer(ctx.game, a, b)
    end
    battle.onFinish = function(result)
      ctx.lastBattleResult = result
      ctx.lastCheck = result == "win"
      if ctx.overworld then
        if result == "win" then
          ctx.afterScript = ctx.afterScript or {}
          table.insert(ctx.afterScript, function()
            ctx.overworld:afterBattle(result, battle)
          end)
        else
          ctx.overworld:afterBattle(result, battle)
        end
      end
      runner:resume()
    end
    local lead
    for _, mon in ipairs(ctx.game.save.party) do
      if mon.hp > 0 then lead = mon break end
    end
    local enemyLevel = battle.enemy and battle.enemy.mon
        and battle.enemy.mon.level or 0
    local overworld = ctx.overworld
    local dungeon = overworld
        and type(overworld.isDungeonTransitionMap) == "function"
        and overworld:isDungeonTransitionMap() or false
    ctx.game.stack:push(BattleTransition.new(ctx.game, function()
      ctx.game.stack:push(battle)
    end, {
      trainer = kind == "trainer",
      stronger = lead ~= nil and enemyLevel >= lead.level + 3,
      dungeon = dungeon,
    }))
    runner:yield()
  end

  -- The Viridian catch tutorial (Commands.old_man_demo) also pushes its
  -- demo battle without a transition; give it the wild intro too.
  local originalOldManDemo = Commands.old_man_demo
  function Commands.old_man_demo(ctx)
    local BattleState = require("src.battle.BattleState")
    local BattleTransition = require("src.render.BattleTransition")
    local runner = ctx.runner
    local om = ctx.game.data.field.oldManBattle or { species = "WEEDLE", level = 5 }
    local battle = BattleState.newWild(ctx.game, om.species, om.level)
    battle:makeOldManDemo()
    battle.onFinish = function() runner:resume() end
    local lead
    for _, mon in ipairs(ctx.game.save.party) do
      if mon.hp > 0 then lead = mon break end
    end
    local overworld = ctx.overworld
    local dungeon = overworld
        and type(overworld.isDungeonTransitionMap) == "function"
        and overworld:isDungeonTransitionMap() or false
    ctx.game.stack:push(BattleTransition.new(ctx.game, function()
      ctx.game.stack:push(battle)
    end, {
      trainer = false,
      stronger = lead ~= nil and (tonumber(om.level) or 5) >= lead.level + 3,
      dungeon = dungeon,
    }))
    runner:yield()
  end

  -- exposed for the headless test suite
  mod.exports.flashFor = flashFor
  mod.exports.tickFlash = function()
    frame = frame + 1
    local flash = recorded
    if flash and flash.stamp ~= frame - 1 then
      flash = nil
      recorded = nil
    end
    return flash
  end
  mod.exports.peekRecorded = function() return recorded end
end
