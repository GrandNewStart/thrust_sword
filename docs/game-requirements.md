# Thrust Sword — Game Requirements v0.5

> Status: **PoC complete.** PoC 1 (iOS touch) and PoC 2 (macOS keyboard + mouse) played identically;
> desktop gives much more freedom, so **desktop is now the lead platform** (Windows, macOS, possibly Linux).
> Next: refining the game on the desktop build. ✅ = decided · 💡 = proposed default (used unless changed) · ❓ = open
> All numbers (costs, damage, speeds) are starting points and will be tuned in playtesting.

## 1. Vision
A 3D third-person action game for **mobile, played in portrait mode**. Two players duel with a giant
high-tech sword that is also their way of moving, attacking and defending. Matches are won by skill,
speed and intuition. The controls take patience to learn and have a high skill ceiling.

## 2. Pillars
1. **One weapon, many roles.** The sword is a blade, a thruster, a gun and a shield.
2. **Mastery over stats.** Customization changes *how* you play, not *how strong* you are.
3. **Speed and commitment.** Burst movement where every dash commits you.
4. **Deep controls that fit two thumbs.** Skill comes from combining simple inputs, not from more buttons.

## 3. PoC Goals ✅
The PoC must prove two things:
1. A **mobile portrait interface** can support a PvP action game with deep controls.
2. **Hyper-action combat** with a sword-thruster weapon is fun and worth exploring further.

The PoC opponent is an **AI**. Real player-vs-player (online) is the next phase after the PoC.

## 4. Platform & Tech ✅
| Item | Decision |
|---|---|
| Engine | Godot 4 (GDScript) |
| Platform | **Desktop first** (Windows, macOS, possibly Linux), keyboard + mouse, landscape. iOS portrait touch kept as a secondary build |
| Grip | **Two thumbs** |
| Dev testing | 💡 Desktop build with mouse emulating touch, plus regular builds on a real device |
| Art | 💡 Simple placeholder shapes and basic materials for the PoC; Halo-style sci-fi direction later |
| Architecture | 💡 Keep game logic separate from input and rendering, so online play can be added in the next phase |

## 5. Camera & Targeting ✅
- **Default:** camera fixed behind the character (like Marvel Rivals or Deadlock). Rotating the camera also turns the character to face that way.
- **Camera control:** drag on the right gesture pad (when not locked on).
- **Lock-on:** tap the opponent in the game view.
- **Release lock-on:** double-tap an empty area of the screen.

## 6. Controls (Portrait, Two Thumbs) ✅
```
┌─────────────────────┐
│                     │
│     Game view       │  tap opponent      = lock-on
│   (top ~60%)        │  double-tap empty  = release lock-on
│                     │
├──────────┬──────────┤
│  LEFT    │  RIGHT   │
│ joystick │ gesture  │
│  = move  │  pad     │
│          │ [GUARD]  │
│          │ [FIRE]   │
│          │ [JUMP]💡 │
└──────────┴──────────┘
```
| Input | Action |
|---|---|
| Left: floating joystick | Move. Push to the edge to run (💡). |
| Left: double-flick | Thrust dash in that direction (needs fuel) |
| Right pad: tap | Light swing |
| Right pad: swipe | Directional slash (swipe direction picks the attack) |
| Right pad: hold, then release | Charged heavy attack |
| Right pad: drag | Camera rotation (when not locked on) |
| Guard: hold | Block |
| Guard: tap just before a hit | Parry (only on swords that support it) |
| Fire | Secondary attack (needs ammo) |
| Jump 💡 | Jump. With fuel and a vertical-capable thruster: hold for vertical thrust. |

**Combos from mixed inputs:** e.g. swipe during a dash = dash-slash (only on thrusters that allow mid-dash attacks).
Exact gesture thresholds (swipe length, hold time, flick speed) are to be tuned on a device.

## 7. Resources ✅
| Resource | Regenerates? | Used for | Refill |
|---|---|---|---|
| **Health** | No | Survival. 0 = defeat. | None (Dark Souls style) |
| **Stamina** | Yes | Moving, running, jumping, swinging, blocking | Regenerates over time |
| **Fuel** | No | Thrust and thrust-powered/power attacks | Fuel packs |
| **Ammo** | No | Secondary attack | Ammo packs |

**With no fuel:** no thrust and no fuel-based attacks. Everything else (moving, running, jumping, swinging, blocking) still works, as long as there's enough stamina.

💡 Proposed costs:
| Action | Stamina | Fuel | Ammo |
|---|---|---|---|
| Walk / run | – / low (ongoing) | – | – |
| Jump | low | – | – |
| Light swing | low | – | – |
| Heavy swing | medium | – | – |
| Block (per hit taken) | scales with hit power | – | – |
| Parry attempt | low | – | – |
| Thrust dash | low | ✔ | – |
| Vertical thrust | low | ✔ (ongoing) | – |
| Thrust-powered attack | medium | ✔ | – |
| Secondary fire | – | – | ✔ |

## 8. Sword System ✅
Everyone shares the same **base sword frame**. Players customize **components**, which change both
stats and appearance. Each sword's behavior emerges from its components.

| Component | Controls |
|---|---|
| **Blade** | Swing damage, speed, reach, block coverage (big blade = blocks almost anything; small = blocks only weak hits) |
| **Thruster** | Dash distance/duration, vertical thrust, fuel efficiency, whether you can attack during or right after a dash |
| **Barrel** | Secondary attack type (none / machine gun / rocket / …), ammo capacity |
| **Guard / Core** | Parry support, parry window, stamina efficiency |

Rules:
- Some attacks are **guard-breaking** and ignore blocks entirely.
- ✅ Blade size sets a **block limit**: a hit stronger than the limit crushes the guard (half damage + short stagger).
- Swords with no barrel have 0 ammo and can't use ammo packs.

### 8.1 PoC Presets ✅
No customization screen in the PoC. Instead, three ready-made swords:
| Preset | Blade | Thruster | Barrel | Parry |
|---|---|---|---|---|
| **Striker** (mobility) | Light, fast, small block coverage | Long dashes, vertical thrust, attack mid-dash | Machine gun, low damage | ✔ |
| **Breaker** (power) | Huge, slow, blocks almost anything, guard-breaking heavy | Short dashes | None | ✘ |
| **Lancer** (balanced/ranged) | Medium | Medium, attack right after dash | Rocket, high damage, few shots | ✔ |

## 9. Armor System ✅
Armor type sets the pace of the fight. Any armor can be paired with any sword.
| Armor | Movement speed | Damage resistance | Fight length |
|---|---|---|---|
| **Heavy** | Slow | High | Long, many hits to defeat |
| **Medium** | Normal | Normal | Normal |
| **Light** | Fast | Low | Short, decisive |

## 10. Match ✅
- **Format:** 1v1.
- **Arena:** large and open, with few objects. Wall interactions postponed.
- **Win condition:** ✅ best of 3 rounds, 75 s each. A round is won by K.O., or on timeout by the higher
  health percentage (equal = draw round, no point; the match ends after 5 rounds at most).
- **Flow:** ✅ SETUP → round intro + 3-2-1 countdown (fighters frozen) → FIGHT → K.O. slow motion / TIME →
  ROUND WON / LOST → … → VICTORY / DEFEAT / DRAW with REMATCH and SETUP. A TRAINING mode skips rounds.
- **Pickups:** ✅ fuel packs (near the center) and ammo packs (further out) respawn 15 s after use,
  and all reset at the start of each round.

## 11. AI Opponents ✅
- Act as **training partners** only; no single-player campaign.
- ✅ Training modes: IDLE dummy, always-BLOCK, aggressive ATTACK, and SPAR (a full sparring partner:
  spacing, reaction-delayed guard/parry/dodge, anticipation guarding, punishes, dash attacks, guns, fuel runs).
- ✅ Loadouts for both sides and the AI mode are chosen in the in-game SETUP menu.
- ✅ AI uses the same sword, armor and resource rules as the player.

## 11b. PoC 2 — macOS Desktop ✅
Goal: compare the **exact same gameplay** on desktop. Same codebase and game logic; only the
front-end differs (input scheme, landscape layout, camera FOV, renderer).
- Keyboard + mouse produce the same PlayerIntent as touch. The left mouse button reuses the touch
  attack-pad gestures (click / flick / hold), so attack selection works identically.
- Landscape 16:9 window, centred HUD column, side-by-side SETUP menu, Forward+ renderer.
- Built as `build/macos/ThrustSword.app` (ad-hoc signed, for local testing).

## 12. Out of Scope for PoC
- Online PvP (next phase)
- Customization screen (presets only)
- Modes other than 1v1
- Wall interactions
- Final art, audio polish
- Matchmaking, accounts, progression

## 13. Open Questions ❓
None blocking. Remaining 💡 items use the proposed default unless changed.
