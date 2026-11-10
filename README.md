# Thrust Sword

3D third-person sci-fi duel game: fight with a giant sword that is also a thruster and a gun.
Built with **Godot 4.7** (GDScript).

**Lead platform: desktop** (Windows, macOS, possibly Linux) with keyboard + mouse.
The proof-of-concept phase is complete:
- **PoC 1 — iOS**, portrait, two-thumb touch controls (`tools/ios_deploy.sh`) — still builds
- **PoC 2 — macOS**, landscape window, keyboard + mouse (`tools/macos_build.sh`) — chosen direction

Both share one codebase with identical gameplay; only the input scheme and layout differ.
Design spec: [docs/game-requirements.md](docs/game-requirements.md)

## Run
```sh
godot --path .            # play (desktop window, mouse acts as one finger)
godot -e --path .         # open in the editor
godot --headless --path . -s tests/test_step1.gd   # movement / camera / lock-on test
godot --headless --path . -s tests/test_step2.gd   # combat test
godot --headless --path . -s tests/test_step3.gd   # thrust / fuel / secondary fire test
godot --headless --path . -s tests/test_step4.gd   # swords / armor / AI test
godot --headless --path . -s tests/test_step5.gd   # match loop test
godot --headless --path . -s tests/test_desktop.gd # keyboard + mouse test
tools/ios_deploy.sh                                # build + install on a connected iPhone
tools/macos_build.sh                               # build build/macos/ThrustSword.app and launch it
godot --path . -- --touch                          # run the touch layout on desktop (mouse = finger)
godot --path . -s tests/screenshot.gd -- <dir>     # render screenshots
```

## Controls
Desktop (macOS) — same actions, same gesture logic as touch:

| Keyboard + mouse | Action |
|---|---|
| WASD · Shift | move · run |
| double-tap WASD · C | thrust dash (that direction · movement direction) |
| Space (hold in the air) | jump (vertical thrust) |
| Mouse | camera (when not locked on) |
| LMB click · LMB + quick flick · hold LMB | light · directional slash (←/→ slash, ↑ thrust, ↓ smash) · charged heavy |
| RMB hold · RMB tap before a hit | guard · parry |
| F | fire secondary weapon |
| Tab / middle mouse | lock on / release |
| Esc | setup menu |

Touch (phone):

| Touch | Action |
|---|---|
| Bottom-left: drag joystick to move, push to edge to run | WASD, Shift to run |
| Bottom-right: drag to rotate camera | drag with mouse |
| JUMP button | Space |
| Attack pad tap: light attack (tap again during recovery to combo) | J |
| Attack pad swipe ← / →: horizontal slashes | Left / Right arrows |
| Attack pad swipe ↑: lunging thrust · swipe ↓: overhead smash | Up / Down arrows |
| Attack pad hold, then release: charged heavy (full charge breaks guard) | hold K |
| GUARD hold: block · tap just before a hit: parry | hold L |
| Joystick double-flick: thrust dash (fuel). Attack during a dash = boosted dash attack | C (dash toward move direction) |
| JUMP hold in the air: vertical thrust (fuel) | hold Space |
| FIRE: secondary weapon (machine gun: hold · rocket: one per press) | F |
| Tap opponent: lock on | Tab toggles lock |
| Double-tap empty area: release lock | Tab |

Orange canisters = fuel packs (+50 fuel), cyan boxes = ammo packs (+50% ammo). Both respawn after 15 s.
Fuel never regenerates on its own.

The app opens on **SETUP**: choose MATCH (best of 3 rounds, 75 s each; on timeout the higher health %
wins) or TRAINING (endless, resets after a K.O.), sword + armor for each side, and the opponent AI
(IDLE / BLOCK / ATTACK / SPAR). SPAR is a real sparring partner: spacing, guards, parries, dodges,
punishes, dash attacks, guns, and grabs fuel when low.

| Sword | Style |
|---|---|
| Striker | Fast, light hits. Long dashes, 3 air dashes, flight, attack mid-dash. Machine gun. Small blade: hits over 14 dmg crush its guard. |
| Breaker | Slow, +45% damage, long reach. Smash and heavy always break guard. Blocks anything. No gun, no parry. |
| Lancer | Balanced. Attack fires the instant a dash ends. 4 rockets. |

| Armor | HP | Damage taken | Speed |
|---|---|---|---|
| Light | 85 | 115% | 115% |
| Medium | 100 | 100% | 100% |
| Heavy | 140 | 75% | 82% |


## Layout
```
scenes/            main, fighter, camera rig
scripts/combat/    SwordDef (3 presets: blade + core + thruster + barrel), ArmorDef (3 presets)
                   AttackDef + Movesets — attack data (timings, damage, reach, poses)
                   ThrusterDef, BarrelDef — sword components; Projectile — bullets/rockets
scripts/ai/        DummyBrain — training partner (idle / block / attack / spar)
scripts/game/      SessionManager — match rounds / timer / banners / results, training mode, loadouts
scripts/input/     PlayerIntent — device-independent "what the player wants";
                   InputMode (touch vs desktop), DesktopControls (keyboard + mouse)
scripts/ui/        TouchControls (portrait touch layout), Hud, LoadoutMenu (SETUP), ResultPanel
scripts/fighter/   Fighter — movement, attacks, guard/parry, health/stamina; FighterVisual — placeholder animation
scripts/camera/    FighterCamera — behind-the-back camera, lock-on
scripts/player/    PlayerController — connects input to fighter + camera
scripts/world/     Arena (generated in code), Pickup (fuel / ammo packs)
tests/             automated tests and screenshot tool
```

## 3D assets
| Asset | Source | How it's built |
|---|---|---|
| Swords (`assets/swords/*.glb`) | Our own | `Blender -b -P tools/blender/build_swords.py -- assets/swords` |
| Character (`assets/mixamo/vanguard.glb`) | Mixamo "Vanguard" + great-sword animations | `Blender -b -P tools/blender/build_character.py -- assets/mixamo/source assets/mixamo/vanguard.glb assets/mixamo/anim_info.json` |

(`Blender` = `/Applications/Blender.app/Contents/MacOS/Blender`)

- **Mixamo files are git-ignored** (free to use in the game, not to redistribute). Raw downloads live in
  `assets/mixamo/source/` (ignored by Godot too); only the merged `vanguard.glb` ships in the app.
  Without them the game still runs, falling back to placeholder capsule fighters.
- `scripts/fighter/character_animator.gd` maps fighter states to clips. Attacks are scrubbed, not played,
  so each swing's fastest point lines up with the game's hit window (`ATTACK_CLIPS` table).
- Preview tools: `tests/screenshot_anims.gd` (contact sheet of every state), `tests/screenshot_swords.gd`.
