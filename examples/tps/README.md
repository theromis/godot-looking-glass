# Optional TPS camera adapter

This is our own generic camera-following adapter, not a copy of the third-person game's source or assets. It requires the current addon with managed capture ownership support.

Copy `game_output.gd` into the target project at `looking_glass/game_output.gd` and register an autoload named `LookingGlassGame`. Install `addons/looking_glass/`, launch Godot 4.8 with native Metal, and configure `BRIDGE_LIBRARY` externally. F4 starts/stops output; Shift+F4 cycles fast/balanced/quality and stops any active session before the next start. Camera replacement stops output. Route the game's explicit quit action through `LookingGlassGame.shutdown_and_quit()`.

Fast is deliberately a quality-reduced preset. The main camera/game environment is preserved; only additional Looking Glass cameras receive reduced source resolution, view count, positional shadow atlas and extra effects. The original mode is an internal benchmark control and intentionally bypasses managed capture ownership; it is not in the interactive profile list.

See [measured TPS profiles and limitations](../../docs/tps-performance-profiles.md). Window HUD is not included in the quilt. Camera projection/environment attributes are copied at startup; a changed FOV or world requires restart. Bridge synchronization is still experimental and bounded.
