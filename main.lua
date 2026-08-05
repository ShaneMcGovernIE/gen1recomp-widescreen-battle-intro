-- Widescreen Battle Intro
--
-- The into-battle transition opens with the palette flash
-- (BattleTransition_FlashScreenPalettes) for the two circle wipes, then
-- wipes the screen.  The engine draws both phases fullscreen: the wipe as
-- a whole-surface cascade (Renderer:drawBattleWipe) and the flash as a
-- screen-space veil (Renderer.screenVeil).  Older engines drew the flash
-- only inside the centered 160x144 letterbox, so on any window wider than
-- 4:3 it played inside a centered square while the frozen overworld
-- showed around it.
--
-- This mod extends the flash across the whole window.  The engine itself
-- has done this since 0.1.53: BattleTransition:draw hands the flash to the
-- renderer as Renderer.screenVeil, which endFrame paints over the whole
-- surface.  This mod's Renderer.endFrame wrap therefore only fires when the
-- engine drew no veil that frame -- the out-of-battle poison pulse (below)
-- and old-engine or buried-transition flashes -- so it can never
-- double-darken the engine's own fullscreen flash.  The overlay is
-- state-driven: it asks the state stack whether a battle transition is in
-- its flash phase right now (a script runner can push the transition at
-- odd points in the frame, so there is no draw/endFrame pairing to
-- desync), and the shade math mirrors the engine's exactly, so it stays
-- frame-locked to the letterbox square.
--
-- The same overlay also covers the out-of-battle poison tick: every
-- fourth step with a poisoned party member, the overworld draws a dark
-- 0.45-alpha pulse inside the 160x144 canvas (OverworldController:draw,
-- ChangeBGPalColor0_4Frames).  On a widescreen window that pulse hides
-- in the centered square, so the endFrame overlay paints the same black
-- veil over the rest of the window while the pulse is up, using the live
-- poisonFlash counter so it can never desync from the square -- and only
-- over the rest: the in-canvas rect already has the square, so the veil
-- is drawn as the bands around the letterbox to keep the flash uniform.
--
-- The wipe and black-hold phases are left to the engine's own fullscreen
-- cascade untouched.  On a 4:3 window the overlay is the same shade the
-- letterbox square already shows, so vanilla is unchanged there.
--
-- FLASHLESS INTROS (an OPTIONS row): when ON, every battle intro plays the
-- Champion battle's intro -- the outward spiral, which never flashes (the
-- champion fight is a trainer battle, and only the circle wipes flash).
-- The transition.style hook runs for every BattleTransition.new -- engine
-- spawns (OverworldState:pushBattle), scripted battles and the catch
-- tutorial alike -- so one hook covers every trigger.

local Renderer = require("src.render.Renderer")
local Game = require("src.core.Game")
local Strings = require("src.core.Strings")

-- the vanilla 3-bit wipe selection (BattleTransition.lua, from
-- battle_transitions.asm GetBattleTransitionID_*): bit 0 trainer, bit 1
-- enemy at least 3 levels above the lead, bit 2 dungeon map
local BIT_STYLES = { [0] = "doublecircle", "spiralin", "circle", "spiralout",
                     "hstripes", "shrink", "vstripes", "split" }

-- the wipe the Champion battle plays: a trainer battle against a stronger
-- foe on a non-dungeon map resolves to bits %011 = spiralout, and the
-- spiral defs never flash
local CHAMPION_STYLE = "spiralout"

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

-- The overworld's poison-tick pulse (OverworldController:draw, the
-- ChangeBGPalColor0_4Frames port): poisonFlash counts 12..0 and the
-- screen darkens for one 4-frame burst in the middle.  { shade, alpha },
-- or nil when no state is pulsing.  The counter is decremented at the
-- top of the overworld's draw before the rect is painted, so by the time
-- endFrame runs (after every state drew) the value already reflects the
-- pulse that landed this frame -- the veil can never lag the square.
local POISON_SHADE = 0
local POISON_ALPHA = 0.45
local function poisonFlash(state)
  local flash = state and state.poisonFlash
  if not (flash and flash > 0) then return nil end
  if math.floor(flash / 4) % 2 == 1 then
    return { shade = POISON_SHADE, alpha = POISON_ALPHA }
  end
  return nil
end

-- The letterbox square in screen space, computed from the same renderer
-- state Renderer:endFrame uses (fitScale/uiSize + pixel dims).  The
-- overworld's in-canvas rect already darkens the square, so the poison
-- veil only paints the bands around it -- the flash is uniform across the
-- window.  Nil when the renderer can't be read (fall back to a
-- full-window rect); an empty list means the letterbox already covers the
-- window, so there is nothing to add and the engine's rect is the whole
-- flash (the 4:3 / zoomed cases, vanilla unchanged).
local function letterboxBands(self)
  local g = love and love.graphics
  if not (g and g.getDimensions and g.getPixelDimensions) then return nil end
  local ww, wh = g.getDimensions()
  local pw, ph = g.getPixelDimensions()
  local dpiX, dpiY = 1, 1
  if ww > 0 and pw > 0 then dpiX = pw / ww end
  if wh > 0 and ph > 0 then dpiY = ph / wh end
  if not (self and self.fitScale and self.uiSize) then return nil end
  local Sp = self:fitScale()
  local uiw, uih = self:uiSize()
  local vpw, vph = uiw * Sp / dpiX, uih * Sp / dpiY
  local ox = math.floor((pw - uiw * Sp) / 2) / dpiX
  local oy = math.floor((ph - uih * Sp) / 2) / dpiY
  local bands = {}
  if ox > 1e-6 then bands[#bands + 1] = { 0, 0, ox, wh } end
  if oy > 1e-6 then bands[#bands + 1] = { 0, 0, ww, oy } end
  if ww - (ox + vpw) > 1e-6 then
    bands[#bands + 1] = { ox + vpw, 0, ww - ox - vpw, wh }
  end
  if wh - (oy + vph) > 1e-6 then
    bands[#bands + 1] = { 0, oy + vph, ww, wh - oy - vph }
  end
  return bands
end

-- The wipe style for a battle context, with or without the flashless
-- toggle: ON forces every battle to the Champion battle's outward spiral;
-- OFF is the vanilla bits (mirror of BattleTransition.lua's vanillaStyle).
-- Pure, so the headless suite can assert both branches.
local function styleFor(flashless, ctx)
  if flashless then return CHAMPION_STYLE end
  return BIT_STYLES[(ctx.trainer and 1 or 0) + (ctx.stronger and 2 or 0)
                    + (ctx.dungeon and 4 or 0)]
end

-- The FLASHLESS INTROS OPTIONS row, built against caller-supplied get/set
-- so the menu and the headless tests share one implementation.
local function toggleRow(getFn, setFn)
  return {
    id = "flashless_intros",
    label = Strings("FLASHLESS INTROS"),
    value = function() return getFn() and Strings("ON") or Strings("OFF") end,
    step = function() setFn(not getFn()) return true end,
  }
end

return function(mod)
  -- The overlay is state-driven: every frame's endFrame asks the state
  -- stack whether a battle transition is in its flash phase right now and
  -- paints the same shade/alpha over the whole window.  There is no
  -- draw/endFrame pairing to desync (a script runner can push the
  -- transition at odd points in the frame, and the flash always matches
  -- the letterbox square the engine draws).  The wrap only paints when the
  -- engine drew no screenVeil that frame (see Renderer.endFrame), so the
  -- engine's own fullscreen flash is never double-darkened.  Returns
  -- { shade, alpha, bands = { {x, y, w, h}, ... } } -- bands set means
  -- the overlay is the poison pulse and only the area outside the
  -- letterbox needs the veil (the canvas rect already has the square).
  local function activeFlash(self)
    local ok, Game = pcall(require, "src.core.Game")
    local stack = ok and Game and Game.stack
    if not (stack and stack.states) then return nil end
    for i = #stack.states, 1, -1 do
      local state = stack.states[i]
      -- a battle transition: wipeLen is its marker (warp fades and the
      -- white flash never carry it)
      if state and state.phase == "flash" and state.wipeLen then
        return flashFor(state.t)
      end
      -- the overworld's poison-tick pulse (poisonFlash is its marker)
      local poison = poisonFlash(state)
      if poison then
        poison.bands = letterboxBands(self)
        return poison
      end
    end
    return nil
  end

  -- Toggles ride options.lua's per-mod bucket (the same store the mod
  -- manager writes) instead of the per-save modData: NEW GAME and CONTINUE
  -- replace the save's modData outright, and an unsaved session lost
  -- toggles on quit.  options.lua survives both, so the flip stays flipped.
  local FLASHLESS_KEY = "flashless_intros"
  local function getFlashless()
    local loader = Game.mods
    local bucket = loader and loader.modOptions and loader.modOptions[mod.id]
    return bucket and bucket[FLASHLESS_KEY] == true or false
  end
  local function setFlashless(value)
    local loader = Game.mods
    if not loader then return end
    loader.modOptions = loader.modOptions or {}
    loader.modOptions[mod.id] = loader.modOptions[mod.id] or {}
    loader.modOptions[mod.id][FLASHLESS_KEY] = value
    -- mirror into the active save's options so a session that saves keeps
    -- it; writeOptions persists options.lua
    if Game.save and Game.save.options then
      Game.save.options.modOptions = Game.save.options.modOptions or {}
      Game.save.options.modOptions[mod.id] =
        Game.save.options.modOptions[mod.id] or {}
      Game.save.options.modOptions[mod.id][FLASHLESS_KEY] = value
    end
    if Game.writeOptions then Game:writeOptions() end
  end

  -- FLASHLESS INTROS: with the toggle on, every battle intro becomes the
  -- Champion battle's -- the flashless outward spiral.  BattleTransition.new
  -- asks the transition.style hook for the wipe on every battle (engine
  -- spawns and scripted battles alike, the catch tutorial included), so one
  -- wrap covers every trigger; the spiral def has no flash flag, so the
  -- transition opens straight on the wipe.
  mod.hooks:wrap("transition.style", function(next, ctx)
    if getFlashless() then return styleFor(true, ctx) end
    return next(ctx)
  end)

  -- the OPTIONS row
  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    rows = next(game, rows)
    rows[#rows + 1] = toggleRow(getFlashless, setFlashless)
    return rows
  end)

  local originalEndFrame = Renderer.endFrame
  function Renderer.endFrame(self, ...)
    local result = originalEndFrame(self, ...)
    local flash = activeFlash(self)
    -- The engine's own screenVeil already painted the battle flash (and
    -- the post-battle white fade) across the whole window this frame
    -- (Renderer:endFrame).  Painting again would double-darken the flash,
    -- so the overlay fires only when the engine drew no veil -- the poison
    -- pulse, and old-engine / buried-transition flashes.
    if flash and not self.screenVeil then
      local g = love and love.graphics
      if g and g.getDimensions and g.setColor and g.rectangle then
        g.push("all")
        g.setShader()
        g.setColor(flash.shade, flash.shade, flash.shade, flash.alpha)
        if flash.bands then
          -- poison pulse: the overworld's in-canvas rect already darkens
          -- the letterbox square, so only the bands around it are veiled
          for _, band in ipairs(flash.bands) do
            g.rectangle("fill", band[1], band[2], band[3], band[4])
          end
        else
          local ww, wh = g.getDimensions()
          g.rectangle("fill", 0, 0, ww, wh)
        end
        g.pop()
      end
    end
    return result
  end

  -- Script-started battles -- the overworld spawn mod's touch-to-battle
  -- path, scripted trainer fights (the rivals, Jessie & James), the
  -- static-encounter script and the catch tutorial -- route through
  -- OverworldState:pushBattle since engine commit f109530, which pushes the
  -- same BattleTransition (flash + circle wipe for wild spawns, the
  -- vanilla-bit wipes for trainers) and starts the battle music, so they
  -- need no wrap here.  The transition.style hook above still governs their
  -- wipe, FLASHLESS INTROS included.

  -- exposed for the headless test suite
  mod.exports.flashFor = flashFor
  mod.exports.poisonFlash = poisonFlash
  mod.exports.letterboxBands = letterboxBands
  mod.exports.activeFlash = activeFlash
  mod.exports.styleFor = styleFor
  mod.exports.toggleRow = toggleRow
end
