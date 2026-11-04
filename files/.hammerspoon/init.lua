-- Hammerspoon — deployed by flake.nix. Edit here and run `just apply`; the
-- watcher below reloads the config when the symlink changes.

-- Start at login via Hammerspoon's own preference, so the Accessibility grant
-- bound to /Applications/Hammerspoon.app is the one that applies.
hs.autoLaunch(true)

-- Reload whenever home-manager re-points ~/.hammerspoon/init.lua.
configWatcher = hs.pathwatcher.new(hs.configdir, function(paths)
  for _, p in ipairs(paths) do
    if p:match("%.lua$") then
      hs.reload()
      return
    end
  end
end):start()

-- Ctrl+Opt+Space: tile all standard windows on the focused screen (current
-- Space). orderedWindows() only returns windows on the active Space, so other
-- Spaces are left alone.
hs.hotkey.bind({ "ctrl", "alt" }, "space", function()
  local screen = hs.screen.mainScreen()
  local wins = hs.fnutils.filter(hs.window.orderedWindows(), function(w)
    return w:isStandard() and w:isVisible() and w:screen():id() == screen:id()
  end)
  hs.window.tiling.tileWindows(wins, screen:frame())
end)

-- Ctrl+Opt+Cmd+Space: label every visible window with a hint and focus the one
-- whose key is typed — the macOS counterpart of sway-easyfocus. The default
-- style hands out hintChars in order, so it's one key per window (home row
-- first) until there are more windows than chars. Titles are hidden to keep the
-- overlay to icon + letter.
hs.hints.hintChars = { "a", "s", "d", "f", "j", "k", "l", "g", "h",
  "q", "w", "e", "r", "u", "i", "o", "p" }
hs.hints.showTitleThresh = 0
hs.hotkey.bind({ "ctrl", "alt", "cmd" }, "space", hs.hints.windowHints)

-- Ctrl+Opt+Cmd+E: Exposé-style thumbnail grid of windows across every Space,
-- grouped by Space; type a window's hint to focus it. Trial — includeOtherSpaces
-- leans on Hammerspoon's older Spaces support and can lag on first show, so set
-- it false if that gets in the way. Kept global, like configWatcher, so it isn't
-- garbage collected.
--
-- The stock look (40pt Lucida Grande, orange highlight, an extra strip for
-- minimized windows) is restyled to something closer to Mission Control:
-- near-black backdrop, small light hint letters, a thin accent outline on the
-- window under the typed hint, and no minimized/hidden strip.
expose = hs.expose.new(nil, {
  showThumbnails = true,
  includeOtherSpaces = true,
  otherSpacesStripPosition = "top",
  otherSpacesStripWidth = 0.25,
  otherSpacesStripBackgroundColor = { 0.08, 0.08, 0.09, 1 },
  includeNonVisible = false,

  backgroundColor = { 0.05, 0.05, 0.06, 1 },
  fontName = "Helvetica Neue",
  textSize = 18,
  textColor = { 0.95, 0.95, 0.95, 1 },
  showTitles = false,
  maxHintLetters = 1,

  highlightColor = { 0.25, 0.55, 0.95, 1 },
  highlightThumbnailStrokeWidth = 3,
  -- Windows that stop matching as you type a hint fade instead of vanishing.
  thumbnailAlpha = 0.25,
  highlightThumbnailAlpha = 1,
})
hs.hotkey.bind({ "ctrl", "alt", "cmd" }, "E", function() expose:toggleShow() end)

-- Ctrl+Cmd+h/j/k/l: focus the nearest window in that direction on the current
-- Space — sway's $mod+hjkl focus. Ctrl+Cmd rather than Cmd alone, which macOS
-- and most apps own (Cmd+H hides, Cmd+L is the address bar), and rather than
-- Ctrl+Opt, which is Rectangle's.
--
-- The built-in hs.window.filter.focus* helpers pick the nearest window rather
-- than the topmost one, and keep their current-Space filter running so the
-- first press after a reload isn't slow.
local focusDirections = {
  h = hs.window.filter.focusWest,
  j = hs.window.filter.focusSouth,
  k = hs.window.filter.focusNorth,
  l = hs.window.filter.focusEast,
}
for key, focus in pairs(focusDirections) do
  hs.hotkey.bind({ "ctrl", "cmd" }, key, focus)
end

-- Ctrl+Opt+Cmd+h/l: switch to the Space on the left / right — sway's
-- workspace prev/next. Replays Mission Control's own Ctrl+Arrow shortcut
-- rather than rebinding it in com.apple.symbolichotkeys, which holds one
-- binding per action and would take Ctrl+Arrow away (throwToSpace below
-- depends on it). Same requirement as throwToSpace: "Move left/right a space"
-- must stay enabled in Keyboard Shortcuts > Mission Control.
local function switchSpace(arrow)
  -- fn is part of the stock shortcut: arrow keys always carry it, and macOS
  -- matches the flags exactly.
  hs.eventtap.keyStroke({ "ctrl", "fn" }, arrow, 10000)
end
hs.hotkey.bind({ "ctrl", "alt", "cmd" }, "h", function() switchSpace("left") end)
hs.hotkey.bind({ "ctrl", "alt", "cmd" }, "l", function() switchSpace("right") end)

-- Ctrl+Cmd+Shift+j/k: throw the focused window to the display on the left /
-- right, keeping its size and position relative to the screen — sway's
-- $mod+Shift move, applied across displays. On j/k rather than h/l, which
-- throw to the neighbouring Space below. noResize=false scales it to
-- the new screen; ensureInScreenBounds=true keeps it fully on screen.
--
-- animationDuration is global: it also makes the tile-all bind above instant,
-- which is the point — window moves that animate feel nothing like sway.
hs.window.animationDuration = 0
hs.hotkey.bind({ "ctrl", "cmd", "shift" }, "j", function()
  local win = hs.window.focusedWindow()
  if win then win:moveOneScreenWest(false, true) end
end)
hs.hotkey.bind({ "ctrl", "cmd", "shift" }, "k", function()
  local win = hs.window.focusedWindow()
  if win then win:moveOneScreenEast(false, true) end
end)

-- Ctrl+Cmd+Shift+h/l: throw the focused window to the Space on the left /
-- right — sway's move-to-workspace, as far as macOS allows. There is no
-- working API for this (hs.spaces.moveWindowToSpace broke in macOS 14.5;
-- yabai needs SIP off), so it uses the drag trick: hold the mouse down on the
-- title bar, switch Space with Mission Control's Ctrl+Arrow shortcut, and
-- release, so the window rides along. The cursor jumps briefly and is put back
-- afterwards.
--
-- Requires "Move left/right a space" enabled under System Settings > Keyboard >
-- Keyboard Shortcuts > Mission Control (the default). Windows without a title
-- bar are left alone, since there is nothing safe to grab.
local spaceThrowTimer -- held so the pending timer isn't garbage collected
-- How long to keep holding the window after the Space switch starts. Too short
-- and the window is dropped before the switch lands, so it stays behind.
local spaceSwitchSeconds = 0.25
local function throwToSpace(arrow)
  local win = hs.window.focusedWindow()
  local zoom = win and win:zoomButtonRect()
  if not zoom then return end

  -- Just right of the green zoom button: title bar, but clear of Chrome's tabs.
  local grab = hs.geometry.point(zoom.x + zoom.w + 5, zoom.y + zoom.h / 2)
  local restore = hs.mouse.absolutePosition()
  local types = hs.eventtap.event.types

  -- Explicit empty modifiers, so the still-held Ctrl of the hotkey doesn't
  -- turn the press into a right-click.
  hs.eventtap.event.newMouseEvent(types.leftMouseDown, grab, {}):post()
  spaceThrowTimer = hs.timer.doAfter(0.05, function()
    switchSpace(arrow)
    -- Release only after the Space switch animation, or the window stays put.
    spaceThrowTimer = hs.timer.doAfter(spaceSwitchSeconds, function()
      hs.eventtap.event.newMouseEvent(types.leftMouseUp, grab, {}):post()
      hs.mouse.absolutePosition(restore)
      win:focus()
    end)
  end)
end
hs.hotkey.bind({ "ctrl", "cmd", "shift" }, "h", function() throwToSpace("left") end)
hs.hotkey.bind({ "ctrl", "cmd", "shift" }, "l", function() throwToSpace("right") end)

hs.alert.show("Hammerspoon config loaded")
