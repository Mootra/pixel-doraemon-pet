# Pixel Doraemon Companion

This Windows-only personal Codex plugin maps lifecycle hooks to an independent
transparent Pixel Doraemon overlay. It does not replace or control Codex's
built-in pet renderer. Use it when you want hook-driven actions or the gadget
menu; hide one of the two pets if you do not want both the native pet and the
overlay visible at the same time.

## Interactions

- Drag: move the companion.
- Click: wave.
- Double-click: use the bamboo copter.
- Right-click: use the Chinese Doraemon-styled menu to choose a prop, pause
  animation, refresh usage, open settings, restart, or exit.
- Launch: Codex SessionStart starts one instance automatically; the installed
  desktop shortcut provides an explicit manual start button.
- Manage: right-click to refresh usage now, reload sprites, open the user config,
  restart the companion, or exit it.
- Idle: look toward the cursor using the v2 direction rows.
- Sprite updates: prefer the separately installed `pixel-doraemon-v3` PNG, poll for
  changes, and fall back to the plugin's bundled atlas.
- Motion: use per-frame v2 timing, a short cursor-direction settle window, and
  shortest-path one-frame look stepping so turns pass through intermediate poses
  instead of snapping directly to a distant direction.
- Usage bubble: show the lowest live remaining percentage as the main number,
  list every active limit window below it, and keep reset times in the tooltip.
  Data comes from the local Codex App Server and does not read or store account
  tokens.

The first run copies `config/default-config.json` into the plugin's writable
data directory as `config.json`. Edit that user copy to change animation speed,
action hold time, event mappings, weighted prop probabilities, or the usage
badge. Set `usage.enabled` to `false` to hide it; `usage.pollMs` controls the
automatic refresh interval (60 seconds by default) and is clamped to at least
15 seconds.

New defaults remain available to older user configs: missing asset, timing,
cursor-settle, or usage settings are read from `default-config.json`. The
right-click menu can refresh the atlas or request a fresh Codex usage snapshot.

Codex requires plugin hooks to be reviewed and trusted before they run. The
overlay uses Windows PowerShell/WPF plus a bundled Node helper that asks the
local Codex App Server for the same rate-limit snapshot used by Codex clients.
