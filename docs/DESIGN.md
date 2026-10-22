# FactoryGun: Design Spec (v1, final)

This file is the single source of truth for building FactoryGun v1. You do not need to read anything else.
Every Godot and GUT fact it relies on was checked against the Godot **4.5.1-stable** binary, its class
reference XML, and the vendored **GUT 9.5.0** source. Section L.1 lists those facts and how each was checked.

Sections: 0 Overview · A Architecture · B Data model · C Graph semantics · D Bullets and effects ·
E Editor UI · F Arena · G State machine and Main · H Progression · I Testing · J CI · K Work packages ·
L Risks and pitfalls.

---

## 0. Overview

FactoryGun splits the screen in two:

- **Left (600 px): the factory.** This is a blueprint editor in a Factorio style: dark industrial floor
  tiles and machines that snap to a grid.
  - Drag machines from the palette onto the floor.
  - Drag belts from output ports to input ports.
  - The factory defines what the gun fires.
- **Right (1000 px): the arena.** This is a top-down shooter.
  - WASD moves, the mouse aims, and the left mouse button fires.
  - Enemies come in waves.
  - Bullet effects visibly apply on every hit.

Each round goes through these phases:

1. **BUILD.** The editor is editable. The arena is idle and the gun is locked.
2. **START WAVE.** The player presses Space or the button.
3. **PLAY.** The arena runs and the editor is locked.
4. **Wave cleared → REWARD.** The player picks 1 of 3 machine offers and heals 25 HP.
5. **BUILD** again for the next wave.

If the player dies, the run goes to **GAME OVER**, then **Restart**.

### 0.1 Decisions at a glance

| Topic | Decision |
|---|---|
| Engine | Godot 4.5.1-stable, GDScript, static typing everywhere (`untyped_declaration` = error). |
| Renderer | `gl_compatibility` for desktop and mobile; the game must run as a web export. |
| Editor | A custom `Control` (`FactoryBoard`) over pure geometry and interaction classes. Do **not** use GraphEdit: it is marked experimental in 4.5.1. |
| Floor | 14×12 tiles of 40 px (560×480). Every machine is 2×2 tiles (80×80). |
| Machines | Basic Bullet (source, fixed) and Output (muzzle, fixed). Placeable: Fire, Ice, Poison, Speed Up, Size Up, Pierce, Splitter. |
| Graph | An output port carries at most 1 belt; connecting from a busy output replaces its belt. An input port accepts any number of belts (streams merge). Only the Splitter forks. No cycles. |
| Bullets | One bullet per complete Basic Bullet → Output path. Hard cap: **8 paths**. A connect that would make a 9th path is refused. |
| Stacking | Each bullet carries the modifiers on its own path. Caps per bullet: 3 of each element, 3 Speed Up, 3 Size Up, 4 Pierce. A Splitter that really splits gives ×0.7 damage. |
| Effects | Fire: burn DoT. Ice: slow. Poison: stacking DoT. All are exact-time integrated and drawn on the enemy. |
| Arena | 1000×900. Three enemy types (Grunt, Runner, Brute). Waves are endless, with HP and speed scaling. Swept circle collisions. |
| Progression | Start inventory: Fire ×1, Speed Up ×1. After each cleared wave, pick 1 of 3 weighted offers; the first reward always includes a Splitter. Placing a machine uses 1 from the inventory; removing it refunds 1. |
| Purity | `src/core` and `src/sim` are RefCounted-only pure logic. A test enforces this. |
| Tests | GUT 9.5.0 vendored in `addons/gut`; tests in `res://test`; a post-run hook and a sanity test plug GUT's blind spots. |
| CI | The existing `ci` job is unchanged except for **one appended step**: a clean-tree check plus a headless boot smoke. |
| Art and audio | Everything is drawn procedurally with `draw_*`. No assets, no audio in v1, no network at runtime. |

### 0.2 Glossary

| Term | Meaning |
|---|---|
| Machine | One placed 2×2 block (`MachineInstance`) of a kind (`MachineDef`). |
| Port | An input port (left edge; 0 or 1 per machine) or an output port (right edge; 0, 1 or 2 per machine). |
| Belt | A connection from an output port to an input port. In code it is a `Wire`. |
| Path | A directed route from the Basic Bullet (id 1) to the Output (id 2). One path makes one bullet. |
| Live machine | A machine on at least one path. Only live machines affect bullets. |
| Real split | A Splitter whose two outputs both feed live machines. It costs ×0.7 damage for every bullet through it. |
| Plan | A `ShotPlan`: the compiled list of `BulletSpec`s that one trigger pull fires, plus statuses and issues. |
| Stream | The partial bullet stats carried on one belt. They are drawn as coloured items on the belt. |
| Offer | One reward card: N machines of one kind. |

---

## A. Architecture

### A.1 Layers and dependency rule

```
src/core   pure rules: graph, compiler, inventory, rewards, flow, run state     (RefCounted only)
src/sim    pure arena simulation                                               (RefCounted only)
src/ui     views: theme, editor, arena, overlays                               (Control nodes)
src/main   Main scene and input-map setup                                      (glue)
```

**Allowed imports.** A layer may use only the layers listed here. Within `ui/`, every folder may also
use `ui/theme`.

| Layer | May use |
|---|---|
| `core` | `core` |
| `sim` | `core`, `sim` |
| `ui/editor` | `core`, `ui/editor` |
| `ui/arena` | `core`, `sim`, `ui/arena`, and `main/input_setup.gd` (`InputSetup` action-name constants only) |
| `ui/overlays` | `core`, `ui/editor` (only for `MachinePainter.draw_icon`) |
| `main` | everything |

**What "pure" means.** It applies to every script in `src/core` and `src/sim`. Test I.4 enforces it.

- The script must say `extends RefCounted`.
- It must not use any of these:
  - `Node`, `Node2D`, `Control`, `CanvasItem` or `SceneTree`
  - `Input`, `InputMap`, `Time`, `OS`, `Engine` or `DisplayServer`
  - `FileAccess`, `DirAccess` or `ResourceLoader`
  - `get_tree()` or `await`
  - any `print*` function (`print`, `printerr`, `prints`, `print_rich`, …), `push_warning` or `push_error`
  - the global RNG: `randi`, `randf`, `randi_range`, `randf_range`, `randfn`, `randomize` or `seed`
- Randomness must come only from a `RandomNumberGenerator` that the script creates and seeds itself.

**Data flow.** The model is changed in one place only:

- Views never mutate the model. They emit `*_requested` signals.
- `Main` turns each request into a `RunState.try_*` call.
- `RunState` validates, then mutates.
- The model emits signals, and the views refresh.

### A.2 File tree and owners

The owners are work packages (section K). No file has two owners at the same time. `main.gd` is a WP0
stub that WP4 replaces after WP0 has merged.

```
project.godot                         WP0   (A.3)
.gitignore                            WP0   (A.3)
.gutconfig.json                       WP0   (A.3)
README.md                             WP4
docs/DESIGN.md                        WP0   this file; later edits only in a separate small PR, merged before dependent WPs branch
addons/gut/**                         WP0   GUT 9.5.0 vendored unmodified (241 files incl. .uid/.import)
export_presets.cfg                    master (other workstream). Do not edit.
.github/workflows/pages.yml           master (other workstream). Do not edit.
.github/workflows/ci.yml              master; WP0 appends exactly one step (J.2)
src/core/tuning.gd                    Tuning              WP0
src/core/machine_def.gd               MachineDef          WP0
src/core/machine_catalog.gd           MachineCatalog      WP0
src/core/machine_instance.gd          MachineInstance     WP0
src/core/wire.gd                      Wire                WP0
src/core/graph_error.gd               GraphError          WP0
src/core/factory_graph.gd             FactoryGraph        WP0
src/core/bullet_spec.gd               BulletSpec          WP0
src/core/plan_issue.gd                PlanIssue           WP0
src/core/shot_plan.gd                 ShotPlan            WP0
src/core/inventory.gd                 Inventory           WP0
src/core/seeds.gd                     Seeds               WP0
src/core/factory_compiler.gd          FactoryCompiler     WP1
src/core/reward_offer.gd              RewardOffer         WP1
src/core/reward_generator.gd          RewardGenerator     WP1
src/core/game_flow.gd                 GameFlow            WP1
src/core/run_state.gd                 RunState            WP1
src/sim/sim_tuning.gd                 SimTuning           WP2
src/sim/enemy_type.gd                 EnemyType           WP2
src/sim/wave_plan.gd                  WavePlan            WP2
src/sim/status_effects.gd             StatusEffects       WP2
src/sim/collision_math.gd             CollisionMath       WP2
src/sim/player_intent.gd              PlayerIntent        WP2
src/sim/sim_event.gd                  SimEvent            WP2
src/sim/player_state.gd               PlayerState         WP2
src/sim/enemy_state.gd                EnemyState          WP2
src/sim/bullet_state.gd               BulletState         WP2
src/sim/arena_world.gd                ArenaWorld          WP2
src/ui/theme/ui_colors.gd             UiColors            WP0
src/ui/theme/factory_theme.gd         FactoryTheme        WP3
src/ui/editor/board_layout.gd         BoardLayout         WP3
src/ui/editor/belt_router.gd          BeltRouter          WP3
src/ui/editor/port_ref.gd             PortRef             WP3
src/ui/editor/board_hit.gd            BoardHit            WP3
src/ui/editor/board_action.gd         BoardAction         WP3
src/ui/editor/drop_preview.gd         DropPreview         WP3
src/ui/editor/board_interaction.gd    BoardInteraction    WP3
src/ui/editor/machine_painter.gd      MachinePainter      WP3
src/ui/editor/belt_painter.gd         BeltPainter         WP3
src/ui/editor/floor_layer.gd          FloorLayer          WP3
src/ui/editor/machine_ghost.gd        MachineGhost        WP3
src/ui/editor/factory_board.gd        FactoryBoard        WP3
src/ui/editor/palette_slot.gd         PaletteSlot         WP3
src/ui/editor/shot_readout.gd         ShotReadout         WP3
src/ui/editor/factory_panel.gd        FactoryPanel        WP3
src/ui/arena/arena_view.gd            ArenaView           WP2
src/ui/arena/hud.gd                   Hud                 WP2
src/ui/arena/arena_controller.gd      ArenaController     WP2
src/ui/overlays/reward_overlay.gd     RewardOverlay       WP4
src/ui/overlays/game_over_overlay.gd  GameOverOverlay     WP4
src/main/input_setup.gd               InputSetup          WP0
src/main/main.tscn                                        WP0   (A.3; never edited again)
src/main/main.gd                      Main                WP0 stub → WP4
test/gut_post_run.gd                                      WP0   (I.3)
test/test_project_sanity.gd                               WP0   (I.4)
test/helpers/fixtures.gd                                  WP0   (I.5)
test/helpers/bot.gd                                       WP2   (I.5)
test/helpers/mouse.gd                                     WP3   (I.5)
test/unit/core/test_*.gd                                  WP0 / WP1 (per file, I.6)
test/unit/sim/test_*.gd                                   WP2
test/unit/ui/test_*.gd                                    WP2 / WP3 / WP4 (per file, I.6)
test/integration/test_*.gd                                WP4
```

Every `.gd` file gets a `.gd.uid` sibling the first time Godot imports it. **Commit the `.uid` files.**
The CI clean-tree check (J.2) fails if one is missing.

### A.3 Project files (verbatim)

`project.godot`:

```ini
; Engine configuration file.
; Hand-written; see docs/DESIGN.md section A.3.

config_version=5

[application]

config/name="FactoryGun"
run/main_scene="res://src/main/main.tscn"
config/features=PackedStringArray("4.5", "GL Compatibility")

[debug]

gdscript/warnings/untyped_declaration=2

[display]

window/size/viewport_width=1600
window/size/viewport_height=900
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
environment/defaults/default_clear_color=Color(0.07, 0.075, 0.08, 1)
```

Notes on `project.godot`:

- `inference_on_variant` already defaults to 2 (error).
- `exclude_addons` defaults to true, so GUT's untyped code raises no warnings.
- Do not add an `[input]` section: `InputSetup` registers actions in code (B.9).
- Do not enable the GUT editor plugin: the command-line runner does not need it.
- `godot --headless --import` does not rewrite this file (verified).

`.gitignore`:

```
.godot/
/build/
```

`.gutconfig.json` (CI's "Validate JSON" step checks it, so it must be strict JSON without comments):

```json
{
  "post_run_script": "res://test/gut_post_run.gd"
}
```

`src/main/main.tscn` is hand-written. It has no `uid=` line, and import leaves it unchanged (verified).
It is the only scene in the project: every other node is built in code.

```
[gd_scene format=3]

[ext_resource type="Script" path="res://src/main/main.gd" id="1_main"]

[node name="Main" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1_main")
```

WP0's stub `src/main/main.gd`:

```gdscript
class_name Main
extends Control
## WP0 stub so CI can boot the main scene. WP4 replaces this file (docs/DESIGN.md G.3).


func _ready() -> void:
	InputSetup.ensure_actions()
```

### A.4 Coding rules (all code, tests included)

1. **Static typing everywhere.** The rules below are what Godot 4.5.1 actually enforces (L.1):
   - Type every `var` (and every `const` you write), every parameter and every return value.
   - Iterating an untyped `Array` or `Dictionary` with an unannotated iterator is an error. To be
     uniform, always annotate: `for w: Wire in wires:`.
   - Typed arrays, typed dictionaries, packed arrays and `range` infer the iterator type, but annotate
     anyway.
   - `var x := some_variant` is a hard parse error. Write `var x: T = some_variant`.
   - Lambdas need typed parameters and a return type: `func(w: Wire) -> bool: return ...`.
   - `Array.filter()` keeps the array's type. `Array.map()` returns an untyped `Array`, so use
     `typed.assign(src.map(...))`.
   - Nested typed collections do not exist. Write `Dictionary[String, Array]` and convert with
     `Array[T].assign()` at the boundary.
2. **Files and classes.**
   - One class per file. The file name is snake_case; the `class_name` is the PascalCase of the file
     name.
   - Member order: `class_name`, `extends`, `##` doc comment, signals, enums, constants, static vars,
     vars, `_init`, built-in virtuals, public methods, private (`_`-prefixed) methods.
   - `class_name` and `extends` go on separate lines.
   - Preload only by absolute `res://` path.
   - **No `class_name` in `test/`.** Test helpers are preloaded by path.
3. **Nodes are built in code.** Build child nodes in `_init()`, so every public method works before the
   node enters the tree. The only scene is `main.tscn`. There are no autoloads.
   - `get_viewport()` is `null` outside the tree (verified). Guard every viewport call in a public method
     or in `_get_drag_data`: `if is_inside_tree() and get_viewport().gui_is_dragging(): ...`.
4. **Signals.**
   - Name facts in the past tense (`changed`, `plan_changed`). Name asks `*_requested`.
   - Inside RefCounted code, connect signals **only to methods**, never to lambdas. A lambda that
     captures `self` and sits on the object's own signal makes a reference cycle, which leaks (verified).
   - Never connect the same callable twice: Godot reports an error. `bind()`-style methods are called
     once.
5. **No `print*`, `push_warning` or `push_error` in `src/`.**
   - Report refusals as `GraphError.Code` or `bool` return values.
   - GUT fails a test on any engine warning or error, and the boot smoke fails on any `WARNING:` line.
   - Two engine calls warn and must never be written (verified):
     - Setting `size` on a Control whose opposite anchors differ, even before it enters the tree.
       Full-rect children (`ArenaView`, `Hud`) get only `set_anchors_preset(Control.PRESET_FULL_RECT)` in
       their parent's `_init()` and follow the parent's size. Controls placed by `Main._add()` and the
       panel's absolute rects keep the default anchors, so setting their `size` is fine.
     - `draw_rect(r, c, true, width)`. Outlines use `draw_rect(r, c, false, w)`; fills use
       `draw_rect(r, c)` with no width argument.
6. **Machine kinds** are always written as `MachineCatalog` constants (`MachineCatalog.FIRE`), never as
   string literals.
7. **UI text uses ASCII plus `× · ° — − …` only.** The default font (Open Sans SemiBold) has these
   glyphs. It does **not** have `▶ ► ═ → ✕` (verified).
8. **Buttons use `focus_mode = Control.FOCUS_NONE`.** Global keys are handled in `Main._unhandled_input`.
   Otherwise Space or Enter would also press a focused button.
9. **Comments say why, not what.** A known limit gets a comment of the form `# shortcut: <limit>, <when to upgrade>`.

---

## B. Data model (`src/core`)

The signatures below are the contract between work packages. Private helpers are free.

### B.1 `Tuning` (WP0): every rules number shared by the factory, the readout and the run

```gdscript
class_name Tuning
extends RefCounted

const GRID_COLS: int = 14
const GRID_ROWS: int = 12
const MAX_BULLETS_PER_SHOT: int = 8
const GUN_INTERVAL: float = 0.25          # 4 shots/s
const FAN_STEP_DEG: float = 10.0
const FAN_MAX_DEG: float = 50.0

const BASE_DAMAGE: float = 10.0
const BASE_SPEED: float = 600.0           # px/s
const BASE_RADIUS: float = 5.0            # px
const BASE_LIFETIME: float = 1.4          # s

const SPEED_MULT: float = 1.35            # per Speed Up level
const SPEED_DAMAGE_MULT: float = 1.10
const SIZE_RADIUS_MULT: float = 1.5       # per Size Up level
const SIZE_DAMAGE_MULT: float = 1.25
const SIZE_SPEED_MULT: float = 0.9
const PIERCE_PER_LEVEL: int = 1
const SPLIT_DAMAGE_MULT: float = 0.7      # per real split on the path

const FIRE_DPS_PER_LEVEL: float = 6.0
const FIRE_DURATION: float = 3.0
const ICE_SLOW_PER_LEVEL: float = 0.2
const ICE_DURATION: float = 2.0
const POISON_STACKS_PER_LEVEL: int = 1
const POISON_DPS_PER_STACK: float = 1.5
const POISON_DURATION: float = 4.0
const POISON_MAX_STACKS: int = 15

const PLAYER_MAX_HP: float = 100.0
const HEAL_ON_REWARD: float = 25.0
const OFFER_COUNT: int = 3
const START_INVENTORY: Dictionary[StringName, int] = {&"fire": 1, &"speed_up": 1}
```

`START_INVENTORY` uses literals rather than `MachineCatalog` constants on purpose: a cross-script const
expression between `Tuning` and `MachineCatalog` risks a cyclic resolution.

Arena-only numbers live in `SimTuning` (F.1). Editor geometry lives in `BoardLayout` (E.3). Colours live
in `UiColors` (B.10).

### B.2 `MachineDef` and `MachineCatalog` (WP0)

| kind const | `kind` | display_name | short | in | out | color | max_stacks | description (exact text) |
|---|---|---|---|---|---|---|---|---|
| SOURCE | `&"source"` | Basic Bullet | BULLET | 0 | 1 | `d9b45a` | 0 | Every shot starts here: one plain bullet (10 damage, 600 px/s). |
| OUTPUT | `&"output"` | Output | OUTPUT | 1 | 0 | `9aa3ad` | 0 | The gun muzzle. Every bullet stream that reaches it is fired. |
| FIRE | `&"fire"` | Fire | FIRE | 1 | 1 | `ff7a2f` | 3 | Sets targets on fire: 6 damage/s per level for 3 s. |
| ICE | `&"ice"` | Ice | ICE | 1 | 1 | `6fd8ff` | 3 | Chills targets: -20% speed per level for 2 s. |
| POISON | `&"poison"` | Poison | POISON | 1 | 1 | `8ee04f` | 3 | Each hit adds 1 poison stack per level (1.5 damage/s each, 4 s, up to 15). |
| SPEED_UP | `&"speed_up"` | Speed Up | SPEED | 1 | 1 | `ffe14d` | 3 | Bullet speed ×1.35 and damage ×1.1 per level. |
| SIZE_UP | `&"size_up"` | Size Up | SIZE | 1 | 1 | `c08bff` | 3 | Bullet size ×1.5 and damage ×1.25 per level, speed ×0.9. |
| PIERCE | `&"pierce"` | Pierce | PIERCE | 1 | 1 | `f0f0f0` | 4 | The bullet passes through 1 more enemy per level. |
| SPLITTER | `&"splitter"` | Splitter | SPLIT | 1 | 2 | `ff9f3a` | 0 | Forks the stream: each output fires its own bullets. ×0.7 damage when both outputs are used. |

`removable` and `placeable` are both `kind != SOURCE and kind != OUTPUT`.

```gdscript
class_name MachineDef
extends RefCounted
## Immutable description of one kind. Created only by MachineCatalog.
var kind: StringName
var display_name: String
var short_name: String
var description: String
var input_ports: int
var output_ports: int
var color: Color
var removable: bool
var placeable: bool
var max_stacks: int
func is_modifier() -> bool        # placeable and not the Splitter
func is_splitter() -> bool

class_name MachineCatalog
extends RefCounted
const SOURCE: StringName = &"source"   # ... one const per row above
const FOOTPRINT: Vector2i = Vector2i(2, 2)
const PALETTE_ORDER: Array[StringName] = [FIRE, ICE, POISON, SPEED_UP, SIZE_UP, PIERCE, SPLITTER]
static var _defs: Dictionary[StringName, MachineDef] = {}   # built lazily on first get_def()
static func get_def(kind: StringName) -> MachineDef          # null if unknown
static func has_kind(kind: StringName) -> bool
static func placeable_kinds() -> Array[StringName]           # == PALETTE_ORDER (a copy)
static func palette_index(kind: StringName) -> int           # -1 if not placeable
```

A static-var cache of RefCounted objects does not leak at exit (verified).

### B.3 `MachineInstance`, `Wire`, `GraphError` (WP0)

```gdscript
class_name MachineInstance
extends RefCounted
## One placed machine. Mutated only by FactoryGraph.
var id: int
var kind: StringName
var cell: Vector2i                        # top-left tile of the 2x2 footprint
static func make(p_id: int, p_kind: StringName, p_cell: Vector2i) -> MachineInstance
func footprint() -> Rect2i                # Rect2i(cell, MachineCatalog.FOOTPRINT)

class_name Wire
extends RefCounted
## One belt: output port from_port of from_id feeds input port to_port of to_id. Immutable once made.
var from_id: int
var from_port: int
var to_id: int
var to_port: int
static func make(p_from_id: int, p_from_port: int, p_to_id: int, p_to_port: int) -> Wire
func key() -> String                      # "%d:%d>%d:%d", e.g. "1:0>2:0"
func same_as(other: Wire) -> bool         # same four fields; false for null
static func less(a: Wire, b: Wire) -> bool   # canonical order: from_id, from_port, to_id, to_port
```

`GraphError.Code` has the values below. `static func describe(code: Code) -> String` returns the
player-facing text, exactly as listed:

| Code | Text |
|---|---|
| OK | "" |
| LOCKED | The factory is locked until the next build phase. |
| UNKNOWN_KIND | Unknown machine. |
| NOT_PLACEABLE | That machine can't be placed. |
| OUT_OF_BOUNDS | That doesn't fit on the factory floor. |
| CELL_OCCUPIED | Something is already there. |
| NO_SUCH_MACHINE | That machine no longer exists. |
| NOT_REMOVABLE | The Basic Bullet and the Output can't be removed. |
| NO_SUCH_PORT | There is no such port. |
| NO_SUCH_WIRE | That belt no longer exists. |
| SELF_LOOP | A machine can't feed itself. |
| DUPLICATE_WIRE | Those ports are already connected. |
| WOULD_CYCLE | That would make a loop: bullets can't go backwards. |
| TOO_MANY_BULLETS | The gun fires at most 8 bullets per shot. (built from `Tuning.MAX_BULLETS_PER_SHOT`) |
| OUT_OF_STOCK | None left. Earn more by clearing waves. |

### B.4 `FactoryGraph` (WP0)

```gdscript
class_name FactoryGraph
extends RefCounted
## The player's factory: machines on the grid and the belts between their ports. Pure rules.
signal changed                            # exactly once per successful mutation; never on a refusal

const SOURCE_ID: int = 1
const OUTPUT_ID: int = 2
const SOURCE_CELL: Vector2i = Vector2i(1, 5)
const OUTPUT_CELL: Vector2i = Vector2i(11, 5)

var _machines: Dictionary[int, MachineInstance] = {}
var _owner: Dictionary[Vector2i, int] = {}     # every covered cell -> machine id
var _wires: Array[Wire] = []
var _next_id: int = 3                           # ids grow and are never reused within a graph's life

static func create_default() -> FactoryGraph    # Source + Output + belt 1:0>2:0

# Queries
func has_machine(id: int) -> bool
func get_machine(id: int) -> MachineInstance    # null if none; callers must not mutate it
func kind_of(id: int) -> StringName             # &"" if none
func def_of(id: int) -> MachineDef              # null if none
func machine_ids() -> PackedInt32Array          # ascending
func machine_at(cell: Vector2i) -> int          # -1 if no machine covers cell
func is_inside(cell: Vector2i) -> bool          # a 2x2 footprint at cell fits the 14x12 floor
func is_area_free(cell: Vector2i, ignore_id: int = -1) -> bool   # inside and overlaps no other machine
func count_kind(kind: StringName) -> int
func wires() -> Array[Wire]                     # a sorted copy (Wire.less); the Wire objects are shared
func wire_from(id: int, port: int) -> Wire      # the belt on that output port, or null
func wires_into(id: int) -> Array[Wire]         # sorted
func has_wire(w: Wire) -> bool
func reaches(from_id: int, to_id: int) -> bool  # directed path exists; from_id == to_id is true
func live_ids() -> Dictionary[int, bool]        # C.4
func count_live_paths() -> int                  # C.4
func live_paths_if_connected(from_id: int, from_port: int, to_id: int, to_port: int) -> int

# Validators: no side effects. Order of checks is in C.3.
func can_add_machine(kind: StringName, cell: Vector2i) -> GraphError.Code
func can_move_machine(id: int, cell: Vector2i) -> GraphError.Code
func can_remove_machine(id: int) -> GraphError.Code
func can_connect(from_id: int, from_port: int, to_id: int, to_port: int) -> GraphError.Code
func can_disconnect(w: Wire) -> GraphError.Code
func can_splice(kind: StringName, cell: Vector2i, w: Wire) -> GraphError.Code

# Mutations: validate first; on refusal change nothing and emit nothing.
func add_machine(kind: StringName, cell: Vector2i) -> int        # new id, or -1
func move_machine(id: int, cell: Vector2i) -> GraphError.Code    # belts follow; own cell = OK, no signal
func remove_machine(id: int) -> GraphError.Code                  # removes its belts, then heals (C.5)
func connect_ports(from_id: int, from_port: int, to_id: int, to_port: int) -> GraphError.Code
func disconnect_wire(w: Wire) -> GraphError.Code                 # matches by same_as()
func splice_machine(kind: StringName, cell: Vector2i, w: Wire) -> int   # new id, or -1 (C.5)
func assign_from(other: FactoryGraph) -> void   # deep copy into this instance; emits changed once
func to_dict() -> Dictionary                    # {"next_id", "machines": [{id, kind, cell:[x,y]}], "wires": [keys]}
func debug_check_invariants() -> PackedStringArray   # empty when consistent (C.1 invariants)
```

### B.5 `BulletSpec` (WP0)

```gdscript
class_name BulletSpec
extends RefCounted
## Stats of one bullet of a shot, or of the partial stream on one belt.
const ROMAN: PackedStringArray = ["", "I", "II", "III"]
var damage: float = Tuning.BASE_DAMAGE
var speed: float = Tuning.BASE_SPEED
var radius: float = Tuning.BASE_RADIUS
var lifetime: float = Tuning.BASE_LIFETIME
var pierce: int = 0
var fire_level: int = 0
var ice_level: int = 0
var poison_level: int = 0
var speed_level: int = 0
var size_level: int = 0
var real_splits: int = 0
## Radians added to the aim angle. y points down, so negative is counter-clockwise on screen.
var angle_offset: float = 0.0

## counts: occurrences of each modifier kind on the path. Levels are clamped to MachineDef.max_stacks here.
static func from_counts(counts: Dictionary[StringName, int], p_real_splits: int) -> BulletSpec
func burn_dps() -> float                  # FIRE_DPS_PER_LEVEL * fire_level
func slow_fraction() -> float             # ICE_SLOW_PER_LEVEL * ice_level
func poison_stacks_per_hit() -> int       # POISON_STACKS_PER_LEVEL * poison_level
func primary_color() -> Color             # first of fire, poison, ice, pierce, speed, size with level > 0; else the Source colour
func describe() -> String                 # D.1 format
```

### B.6 `PlanIssue` and `ShotPlan` (WP0)

```gdscript
class_name PlanIssue
extends RefCounted
enum Code { NO_PATH, DEAD_END, IDLE, CAPPED, ONE_SIDED }
enum Severity { INFO, WARNING, ERROR }
var code: Code
var machine_id: int = -1
var text: String = ""
static func make(p_code: Code, p_machine_id: int, p_text: String) -> PlanIssue
func severity() -> Severity               # NO_PATH = ERROR, ONE_SIDED = INFO, others WARNING
static func before(a: PlanIssue, b: PlanIssue) -> bool   # severity desc, then machine_id asc, then code asc

class_name ShotPlan
extends RefCounted
## What one trigger pull fires. Never mutated after compile; RunState replaces it on every edit.
enum MachineStatus { ACTIVE, CAPPED, ONE_SIDED, DEAD_END, IDLE }
var bullets: Array[BulletSpec] = []
var statuses: Dictionary[int, MachineStatus] = {}
var live_wire_keys: Dictionary[String, bool] = {}
var wire_streams: Dictionary[String, Array] = {}   # Wire.key() -> up to 4 distinct partial BulletSpecs
var issues: Array[PlanIssue] = []
static func empty() -> ShotPlan           # no bullets + the NO_PATH issue
func is_valid() -> bool                   # not bullets.is_empty()
func status_of(id: int) -> MachineStatus  # IDLE if unknown
func is_live_wire(w: Wire) -> bool
func streams_on(w: Wire) -> Array[BulletSpec]   # typed copy via assign()
func damage_per_shot() -> float           # sum of bullet damage
func has_issue(code: PlanIssue.Code) -> bool
func summary_lines() -> PackedStringArray # E.7 format
```

### B.7 `Inventory` and `Seeds` (WP0)

```gdscript
class_name Inventory
extends RefCounted
## Machines held but not placed. Only placeable kinds are ever stored.
signal changed
var _counts: Dictionary[StringName, int] = {}
var _ever: Dictionary[StringName, bool] = {}
static func from_counts(counts: Dictionary[StringName, int]) -> Inventory   # emits nothing; see below
func count(kind: StringName) -> int
func add(kind: StringName, amount: int = 1) -> bool   # false, no change: unknown/unplaceable kind or amount <= 0
func take(kind: StringName) -> bool                   # false, no change: none left
func ever_owned(kind: StringName) -> bool             # true once added, even after taking all
func kinds_ever_owned() -> Array[StringName]          # palette order
func assign_from(other: Inventory) -> void            # copies counts and ever-owned; emits once
func to_dict() -> Dictionary                          # {"fire": 2, ...} for counts > 0, palette order

class_name Seeds
extends RefCounted
## Per-purpose RNG seeds. String.hash() is djb2-like: "wave|1|1" and "wave|1|2" give adjacent
## integers, and similar seeds give similar RandomNumberGenerator streams. SHA-256 mixes every bit.
const WAVE: StringName = &"wave"
const REWARD: StringName = &"reward"
static func derive(run_seed: int, wave: int, purpose: StringName) -> int:
	return ("%s|%d|%d" % [purpose, run_seed, wave]).sha256_text().substr(0, 15).hex_to_int()
```

`derive` returns a non-negative 60-bit integer: 15 hex digits, so it never overflows `int`.

`from_counts` copies its input key by key: it keeps only placeable kinds with a count above 0, and marks
each kept kind ever-owned (so the starting palette shows Fire and Speed Up, not "???"). It never stores
`counts` itself: `Tuning.START_INVENTORY` is a `const`, so it is read-only, and a stored reference makes
the first `take()` fail with "Dictionary is in read-only state" (verified).

### B.8 WP1 types: `FactoryCompiler`, `RewardOffer`, `RewardGenerator`, `GameFlow`, `RunState`

```gdscript
class_name FactoryCompiler
extends RefCounted
static func compile(graph: FactoryGraph) -> ShotPlan                    # C.6
static func fan_angles(count: int) -> PackedFloat64Array               # D.2
static func is_real_split(graph: FactoryGraph, live: Dictionary[int, bool], id: int) -> bool

class_name RewardOffer
extends RefCounted
var kind: StringName
var amount: int = 1
static func make(p_kind: StringName, p_amount: int) -> RewardOffer
func label() -> String                    # "Fire ×2"

class_name RewardGenerator
extends RefCounted
static func generate(run_seed: int, wave_cleared: int, ever_owned: Array[StringName]) -> Array[RewardOffer]   # H.2
static func weight_of(kind: StringName, wave_cleared: int) -> float
static func amount_of(kind: StringName, wave_cleared: int) -> int

class_name GameFlow
extends RefCounted
signal state_changed(previous: State, current: State)
enum State { BUILD, PLAY, REWARD, GAME_OVER }
var state: State = State.BUILD
var wave: int = 1                         # the wave being built for, played, or just cleared (1-based)
func is_editing_allowed() -> bool         # state == BUILD
func start_wave() -> bool                 # BUILD -> PLAY
func clear_wave() -> bool                 # PLAY -> REWARD
func lose() -> bool                       # PLAY -> GAME_OVER
func finish_reward() -> bool              # REWARD -> BUILD, wave += 1
func restart() -> void                    # any -> BUILD, wave = 1; ALWAYS emits (views reset)
# Each transition that does not start from its expected state returns false and emits nothing.

class_name RunState
extends RefCounted
## Aggregate root of one run. graph, inventory and flow are the same instances for the whole
## session (restart() copies into them), so views bind once.
signal plan_changed(plan: ShotPlan)
var graph: FactoryGraph = FactoryGraph.create_default()
var inventory: Inventory = Inventory.from_counts(Tuning.START_INVENTORY)
var flow: GameFlow = GameFlow.new()
var plan: ShotPlan                        # compiled in _init and after every graph change
var active_plan: ShotPlan = ShotPlan.empty()   # frozen by start_wave(); the arena fires this
var run_seed: int = 0
var player_hp: float = Tuning.PLAYER_MAX_HP
var total_kills: int = 0
var offers: Array[RewardOffer] = []       # set by complete_wave(); cleared by choose_offer/fail_wave/restart
func _init(p_run_seed: int = 0) -> void   # compiles plan; graph.changed.connect(_on_graph_changed)
func try_place_machine(kind: StringName, cell: Vector2i, splice: Wire = null) -> GraphError.Code
func try_move_machine(id: int, cell: Vector2i) -> GraphError.Code
func try_remove_machine(id: int) -> GraphError.Code     # refunds 1 to the inventory
func try_connect(from_id: int, from_port: int, to_id: int, to_port: int) -> GraphError.Code
func try_disconnect(w: Wire) -> GraphError.Code
func owned(kind: StringName) -> int       # inventory + on the floor; only rewards change it
func can_start_wave() -> bool             # BUILD and plan.is_valid()
func start_reason() -> String             # "" or "Connect the Basic Bullet to the Output first."
func start_wave() -> bool                 # active_plan = plan; flow.start_wave()
func wave_seed() -> int                   # Seeds.derive(run_seed, flow.wave, Seeds.WAVE)
func complete_wave(hp_left: float, kills: int) -> bool  # PLAY only: hp = hp_left, total_kills += kills, offers, then flow.clear_wave()
func fail_wave(kills: int) -> bool        # PLAY only: hp = 0, total_kills += kills, offers = [], flow.lose()
func choose_offer(index: int) -> bool     # REWARD only: inventory.add, heal (cap), offers = [], flow.finish_reward()
func restart(p_run_seed: int) -> void     # seed, HP, kills, offers, active_plan, inventory, graph; then flow.restart()
```

`RunState` rules:

- Every `try_*` returns `LOCKED` first when `flow.state != BUILD`.
- `try_place_machine` returns `OUT_OF_STOCK` when the kind is known and placeable but `inventory.count(kind) == 0`.
- After that, `try_place_machine` returns the result of `graph.can_add_machine`, or of
  `graph.can_splice` when `splice != null`.
- A refused `try_*` changes nothing at all: not the graph, not the inventory.
- `complete_wave` fills `offers` **before** it calls `flow.clear_wave()`, so `state_changed` listeners
  already see the offers.

### B.9 `InputSetup` (WP0)

```gdscript
class_name InputSetup
extends RefCounted
## Registers every input action in code (no [input] section in project.godot). Idempotent.
const MOVE_LEFT: StringName = &"move_left"          # physical A, Left
const MOVE_RIGHT: StringName = &"move_right"        # physical D, Right
const MOVE_UP: StringName = &"move_up"              # physical W, Up
const MOVE_DOWN: StringName = &"move_down"          # physical S, Down
const FIRE: StringName = &"fire"                    # left mouse button
const START_WAVE: StringName = &"start_wave"        # Space, Enter, Keypad Enter
const DELETE_HOVERED: StringName = &"delete_hovered"  # Delete, X
const CANCEL: StringName = &"cancel"                # Escape
const RESTART: StringName = &"restart"              # R
const PICK: Array[StringName] = [&"pick_1", &"pick_2", &"pick_3"]   # 1/Keypad 1, 2/Keypad 2, 3/Keypad 3
static func ensure_actions() -> void      # adds each missing action with the events listed above
```

`FIRE` gets one `InputEventMouseButton` with `button_index = MOUSE_BUTTON_LEFT`. Every other action gets
`InputEventKey` events with `physical_keycode` set. Physical keycodes make WASD work on AZERTY keyboards.

### B.10 `UiColors` (WP0)

```gdscript
class_name UiColors
extends RefCounted
const FLOOR_A: Color = Color("2a2c2e")
const FLOOR_B: Color = Color("2e3032")
const SEAM: Color = Color("1a1b1c")
const STEEL: Color = Color("4b4f54")
const STEEL_LIGHT: Color = Color("6c7177")
const STEEL_DARK: Color = Color("2b2e31")
const OUTLINE: Color = Color("151617")
const RIVET: Color = Color("8d9399")
const BELT_BED: Color = Color("34332e")
const RAIL: Color = Color("77736a")
const CHEVRON: Color = Color("e2b43a")
const CHEVRON_DIM: Color = Color("6e6248")
const PANEL_BG: Color = Color("1e2124")
const PANEL_EDGE: Color = Color("3a3f44")
const TEXT: Color = Color("e6e2d3")
const TEXT_DIM: Color = Color("9a968a")
const ACCENT: Color = Color("e3a83a")
const OK: Color = Color("6fdc6f")
const WARN: Color = Color("ffb547")
const ERROR: Color = Color("ff5a4f")
const LAMP_IDLE: Color = Color("6b6b6b")
const HAZARD: Color = Color("f2c230")
const ARENA_FLOOR: Color = Color("1b1d20")
const ARENA_GRID: Color = Color("23262a")
const PLAYER: Color = Color("5da9e9")
```

Machine colours live in `MachineCatalog`. Enemy colours live in `EnemyType`.

---

## C. Graph semantics

### C.1 Floor, machines, invariants

- The floor is 14 columns × 12 rows. A machine's `cell` is its top-left tile. It covers
  `Rect2i(cell, (2, 2))`, which must lie inside the floor.
- Footprints never overlap. Any free 2×2 area is valid: there is no other placement restriction.
- The Basic Bullet (id 1, at (1,5)) and the Output (id 2, at (11,5)) always exist. They can be moved
  but not removed.
- `create_default()` adds the belt `1:0>2:0`, so a new run fires 1 plain bullet.
- New machines get ids `3, 4, 5, …`. An id is never reused within a graph's lifetime. Only
  `assign_from` (restart) resets ids.
- `debug_check_invariants()` checks all of the following:
  - The Source and Output exist with their kinds.
  - Every machine is inside the floor.
  - `_owner` matches the footprints exactly.
  - No machine has `id >= _next_id`.
  - Every belt touches existing machines and valid ports.
  - No output port carries two belts.
  - No cycles.
  - `count_live_paths() <= MAX_BULLETS_PER_SHOT`.

### C.2 Ports and belts

- Input ports: 0 or 1 per machine, on the middle of the left edge. **An input port accepts any number
  of belts**: streams merge, but each path stays a separate bullet.
- Output ports: 0, 1 or 2 per machine (Splitter: port 0 upper, port 1 lower). **An output port carries
  at most one belt.**
- Connecting from an output port that already has a belt **replaces** that belt in one step. This is
  how players re-route.
- Belts are directed. A connect that would create a cycle is refused.

### C.3 Validation order (first failure wins)

| Operation | Checks in order |
|---|---|
| `can_add_machine(kind, cell)` | UNKNOWN_KIND → NOT_PLACEABLE → OUT_OF_BOUNDS → CELL_OCCUPIED |
| `can_splice(kind, cell, w)` | UNKNOWN_KIND → NOT_PLACEABLE → NO_SUCH_WIRE → OUT_OF_BOUNDS → CELL_OCCUPIED |
| `can_move_machine(id, cell)` | NO_SUCH_MACHINE → OUT_OF_BOUNDS → CELL_OCCUPIED (ignoring itself) |
| `can_remove_machine(id)` | NO_SUCH_MACHINE → NOT_REMOVABLE |
| `can_connect(f, fp, t, tp)` | NO_SUCH_MACHINE (either) → NO_SUCH_PORT (`fp` not in `[0, out)`) → NO_SUCH_PORT (`tp` not in `[0, in)`) → SELF_LOOP → DUPLICATE_WIRE (`wire_from(f, fp)` already goes to `t:tp`) → WOULD_CYCLE (`reaches(t, f)`) → TOO_MANY_BULLETS (`live_paths_if_connected(...) > 8`) |
| `can_disconnect(w)` | NO_SUCH_WIRE |
| `RunState.try_*` | LOCKED (not BUILD) → [place only] OUT_OF_STOCK → the graph check above |

Every placeable kind has 1 input and at least 1 output, so any of them can be spliced.

### C.4 Live set and path count

```gdscript
# live = reachable from the Source AND able to reach the Output
func live_ids() -> Dictionary[int, bool]:
	var fwd: Dictionary[int, bool] = _closure(SOURCE_ID, true, _wires)
	var bwd: Dictionary[int, bool] = _closure(OUTPUT_ID, false, _wires)
	var live: Dictionary[int, bool] = {}
	for id: int in fwd:
		if bwd.has(id):
			live[id] = true
	return live

# number of Source -> Output paths: memoised DP over the DAG
func _paths_from(id: int, wire_list: Array[Wire], memo: Dictionary[int, int]) -> int:
	if id == OUTPUT_ID:
		return 1
	if memo.has(id):
		return memo[id]
	memo[id] = 0                          # guards against corrupt (cyclic) data
	var total: int = 0
	for w: Wire in wire_list:
		if w.from_id == id:
			total += _paths_from(w.to_id, wire_list, memo)
	memo[id] = total
	return total

# live_paths_if_connected: the same count on a trial list with any belt on (from_id, from_port)
# removed and Wire.make(from_id, from_port, to_id, to_port) appended.
```

With at most 42 machines, the count stays below 2^40, so `int` never overflows. No cap is needed.

**Only `connect_ports` can raise the path count.** That is why the 8-bullet cap is checked only there,
and why no truncation code exists anywhere:

- `add_machine` creates a machine with no belts.
- `move_machine` keeps all belts.
- `disconnect_wire` and a non-healing remove only delete paths.
- A healing remove and a splice keep the count exactly (C.5).

### C.5 Remove with heal, and splice

- **Remove** deletes the machine and every belt touching it. Then it heals:
  - If the machine had **exactly one incoming belt and exactly one outgoing belt** (A→X→B), it adds the
    belt A→B, using A's port and B's port.
  - Healing never needs validation. A's output port was freed with X's incoming belt, so the new belt
    cannot be a duplicate. A already reached B, so it cannot make a cycle. Paths through X map one to
    one onto paths through A→B, so the path count is unchanged.
  - A merge (two or more incoming belts) or a real fork is not healed: those belts just disappear.
- **Splice** happens when a palette machine N is dropped onto belt A→B. The belt becomes `A→N:0` and
  `N:0→B`.
  - The path count is unchanged.
  - A spliced Splitter uses only output 0, so it shows ONE_SIDED until the player wires port 1.

### C.6 Compilation (`FactoryCompiler.compile`)

The code below is valid typed GDScript, except for the two helper calls described in comments
(`_add_stream`, `_collect_issues`).

```gdscript
static func compile(graph: FactoryGraph) -> ShotPlan:
	var plan: ShotPlan = ShotPlan.new()
	var live: Dictionary[int, bool] = graph.live_ids()
	for w: Wire in graph.wires():
		if live.has(w.from_id) and live.has(w.to_id):
			plan.live_wire_keys[w.key()] = true
	var paths: Array[PackedInt32Array] = []      # machine ids, Source .. Output
	var ports: Array[PackedInt32Array] = []      # output port taken at each step (size = path size - 1)
	if live.has(FactoryGraph.SOURCE_ID):
		_walk(graph, live, FactoryGraph.SOURCE_ID, PackedInt32Array([FactoryGraph.SOURCE_ID]),
				PackedInt32Array(), paths, ports)
	var angles: PackedFloat64Array = fan_angles(paths.size())
	var useful: Dictionary[int, bool] = {}       # modifier counted within its cap on some path
	var capped: Dictionary[int, bool] = {}       # modifier beyond its cap on some path
	for bi: int in paths.size():
		var counts: Dictionary[StringName, int] = {}
		var splits: int = 0
		for j: int in paths[bi].size():
			var id: int = paths[bi][j]
			var def: MachineDef = graph.def_of(id)
			if def.is_splitter():
				if is_real_split(graph, live, id):
					splits += 1
			elif def.is_modifier():
				var n: int = counts.get(def.kind, 0) + 1
				counts[def.kind] = n
				if n > def.max_stacks:
					capped[id] = true
				else:
					useful[id] = true
			if j < ports[bi].size():               # the belt leaving this machine carries the partial stream
				_add_stream(plan, graph.wire_from(id, ports[bi][j]).key(), BulletSpec.from_counts(counts, splits))
		var spec: BulletSpec = BulletSpec.from_counts(counts, splits)
		spec.angle_offset = angles[bi]
		plan.bullets.append(spec)
	for id: int in graph.machine_ids():
		plan.statuses[id] = _status(graph, live, id, useful, capped)
	_collect_issues(graph, plan)                  # C.7, then issues.sort_custom(PlanIssue.before)
	return plan

# Depth-first, output ports in ascending order, following only belts into live machines.
# Live machines all reach the Output and the graph is acyclic, so every branch ends in a path.
static func _walk(graph: FactoryGraph, live: Dictionary[int, bool], id: int, path: PackedInt32Array,
		path_ports: PackedInt32Array, paths: Array[PackedInt32Array], ports: Array[PackedInt32Array]) -> void:
	if id == FactoryGraph.OUTPUT_ID:
		paths.append(path)
		ports.append(path_ports)
		return
	for port: int in graph.def_of(id).output_ports:
		var w: Wire = graph.wire_from(id, port)
		if w == null or not live.has(w.to_id):
			continue
		var next_path: PackedInt32Array = path.duplicate()
		next_path.append(w.to_id)
		var next_ports: PackedInt32Array = path_ports.duplicate()
		next_ports.append(port)
		_walk(graph, live, w.to_id, next_path, next_ports, paths, ports)

static func is_real_split(graph: FactoryGraph, live: Dictionary[int, bool], id: int) -> bool:
	var a: Wire = graph.wire_from(id, 0)     # both outputs must feed live machines
	var b: Wire = graph.wire_from(id, 1)
	return a != null and b != null and live.has(a.to_id) and live.has(b.to_id)

# _add_stream: keep at most 4 partial specs per belt key, skipping one whose describe() is already there.
```

**Order matters only through DFS.** Bullet `i` is the `i`-th path in depth-first, lowest-port-first
order. So a Splitter's upper output (port 0) gives the earlier bullet, which gets the more negative
(counter-clockwise) fan angle. Aiming right, the upper branch fires the upper bullet.

The order of modifiers along one path never changes the stats. It changes only which occurrences
count as CAPPED: the ones nearer the Output.

### C.7 Machine statuses and issues

| Status | Condition (first match) | Lamp | Issue (only for removable machines) |
|---|---|---|---|
| DEAD_END | not live, but `reaches(SOURCE_ID, id)` | red `ERROR` | WARNING DEAD_END: "%s #%d is a dead end: its belt never reaches the Output." |
| IDLE | not live and not `reaches(SOURCE_ID, id)` (every other non-live machine, even one with an incoming belt from an idle machine) | grey `LAMP_IDLE` | WARNING IDLE: "%s #%d is idle: no bullets reach it." |
| ONE_SIDED | live Splitter, not a real split | amber `WARN` | INFO ONE_SIDED: "Splitter #%d uses one output, so it does not split." |
| CAPPED | in `capped` and not in `useful` | amber `WARN` | WARNING CAPPED: "%s #%d adds nothing: %s is capped at %d per bullet." |
| ACTIVE | otherwise | green `OK` | none |

`%s` is `display_name` and `#%d` is the machine id. With no bullets at all, the plan also gets
`NO_PATH` (ERROR, machine_id −1): "Connect the Basic Bullet to the Output." `NO_PATH` disables Start
Wave.

### C.8 Worked examples (golden tests)

| Factory | Bullets (in order) |
|---|---|
| default (Source → Output) | #1 DMG 10.0 · SPD 600 · SIZE 5.0, angle 0 |
| Source → Speed Up → Size Up → Fire → Output | #1 dmg 10·1.1·1.25 = 13.75, spd 600·1.35·0.9 = 729, r 7.5, fire I |
| Source → Fire → Splitter; upper: Speed Up → Output; lower: Pierce → Output | #1 dmg 10·1.1·0.7 = 7.7, spd 810, fire I, angle −5° · #2 dmg 7.0, spd 600, fire I, pierce 1, angle +5° |
| Source → Splitter; upper → Output; lower unconnected | 1 bullet, dmg 10.0 (no penalty); Splitter ONE_SIDED + INFO issue |
| Source → Sp1, both outputs → Sp2's input, both Sp2 outputs → Output | 4 bullets, each dmg 10·0.7² = 4.9; fan step 50°/3 = 16.67° → clamped to 10°: −15°, −5°, +5°, +15° |
| 3 Splitters chained as above | 8 bullets, dmg 3.43 each; any connect that adds a 9th path → TOO_MANY_BULLETS ("… This belt would make N.") |
| Source → Fire ×4 → Output | fire III; the 4th Fire (nearest the Output) is CAPPED with an issue |

---

## D. Bullets and effects

### D.1 Stats (`BulletSpec.from_counts`)

Let `Ls`, `Lz`, `Lp`, `Lf`, `Li`, `Lpo` be the clamped levels of Speed Up, Size Up, Pierce, Fire, Ice and
Poison on the path. Let `S` be the number of real splits on the path. Then:

```
damage   = 10 · 1.10^Ls · 1.25^Lz · 0.7^S
speed    = 600 · 1.35^Ls · 0.9^Lz          (max 600·1.35³ = 1476 px/s)
radius   = 5 · 1.5^Lz                      (max 16.9 px)
pierce   = Lp                              (extra enemies passed through; max 4)
lifetime = 1.4 s
```

`describe()` builds one string from these parts, joined with `" · "`:

1. `DMG %.1f`
2. `SPD %d` (speed rounded)
3. `SIZE %.1f` (the radius)
4. Each that applies: `FIRE <roman>`, `ICE <roman>`, `POISON <roman>`, `PIERCE %d`

Example: `DMG 7.0 · SPD 600 · SIZE 5.0 · FIRE I · PIERCE 1`.

`primary_color()` tints both bullets and belt items: fire > poison > ice > pierce > speed > size, else
brass (`d9b45a`).

### D.2 Fan (`FactoryCompiler.fan_angles(n)`)

- `n = 0`: `[]`.
- `n = 1`: `[0]`.
- `n > 1`: `step = deg_to_rad(min(10°, 50° / (n − 1)))`, and `angle_i = (i − (n − 1) / 2.0) · step`.
  Divide by `2.0`: with ints, `(n - 1) / 2` truncates (for `n = 2` it gives 0, not 0.5).
  Angles increase, so bullet 0 is the most counter-clockwise. The spread is at most 50°.

### D.3 Status effects (`StatusEffects`, one per enemy)

| Effect | On hit (only when level > 0) | Over time |
|---|---|---|
| Burn (Fire) | `burn_dps = max(current if burning else 0, 6·Lf)`; `burn_time = 3.0` | `burn_dps` damage/s while `burn_time > 0` |
| Chill (Ice) | `slow = max(current if chilled else 0, 0.2·Li)`; `slow_time = 2.0` | speed × `(1 − slow)` while chilled (max 60% slow) |
| Poison | `stacks = min((stacks if poisoned else 0) + Lpo, 15)`; `poison_time = 4.0` (refreshes all stacks) | `stacks · 1.5` damage/s while `poison_time > 0` |

`tick(delta)` integrates exactly, so totals do not depend on the frame rate:

```gdscript
func tick(delta: float) -> float:         # returns DoT damage for this step
	var dmg: float = burn_dps * minf(delta, burn_time) \
			+ poison_stacks * Tuning.POISON_DPS_PER_STACK * minf(delta, poison_time)
	burn_time = maxf(burn_time - delta, 0.0)
	slow_time = maxf(slow_time - delta, 0.0)
	poison_time = maxf(poison_time - delta, 0.0)
	if burn_time <= 0.0: burn_dps = 0.0
	if slow_time <= 0.0: slow = 0.0
	if poison_time <= 0.0: poison_stacks = 0
	return dmg
```

`StatusEffects` API: `apply_hit(spec: BulletSpec)`, `tick(delta) -> float`, `is_burning()`,
`is_chilled()`, `is_poisoned()`, `speed_multiplier() -> float`, and public vars `burn_dps`,
`burn_time`, `slow`, `slow_time`, `poison_stacks`, `poison_time`.

### D.4 Hit resolution

For each bullet, in id order, every physics step:

1. Sweep the segment `a = pos` → `b = pos + vel·dt`. Test every live enemy the bullet has not yet hit,
   using `CollisionMath.first_contact(a, b, enemy.pos, enemy.r + bullet.r)`.
2. Sort the hits by `(t, enemy index)`.
3. Apply the hits in that order. Each hit does all of the following:
   - `enemy.hp −= spec.damage`
   - `status.apply_hit(spec)`
   - remember the enemy in `hit_ids`
   - emit a HIT event
4. After each hit: if `pierce_left == 0`, the bullet dies at this hit. Otherwise `pierce_left −= 1`.
5. A surviving bullet moves to `b` and its `life −= dt`. It is removed when `life <= 0` or when it
   leaves the arena rectangle grown by 60 px.

An enemy whose `hp <= 0` is skipped by later bullets in the same step, so there is no overkill.

`CollisionMath.first_contact(a, b, c, r) -> float` returns the fraction `t` in [0, 1] at which a point
moving a→b first comes within `r` of `c`:

- It returns `0.0` if the point starts inside.
- It returns `-1.0` if it never comes that close during the step.
- It solves the quadratic `|a + t(b−a) − c|² = r²` and takes the smaller root.

Do **not** use `Geometry2D.segment_intersects_circle`. For a segment that starts inside the circle, it
returns the *exit* fraction, or −1 if the segment never leaves (verified).

### D.5 What the player sees (the effects are visible on hit)

| Event or state | Drawing (ArenaView, F.8) |
|---|---|
| Bullet | Filled circle of the spec radius in `primary_color()`, a 1 px light outline, and a trail line 2.5·r long behind it at 50% alpha. |
| HIT | The enemy flashes white for 0.08 s. A ring in the bullet's colour grows at the hit point from radius 4 to 18 over 0.25 s while it fades. |
| Burning | Body lerped 35% toward fire orange. 3 flickering flame triangles above the enemy. |
| Chilled | Body lerped 35% toward ice blue. A 2 px ice-blue ring at r+3. It visibly moves slower. |
| Poisoned | Body lerped 35% toward poison green. `min(stacks, 5)` green dots orbit at r+5. |
| Damaged | An HP bar (2r wide, 3 px tall) above any enemy with `hp < max_hp`. |
| KILL | 8 particles in the enemy colour fly outward at 120 px/s and fade over 0.35 s. |
| SHOT | Muzzle flash: a circle of radius 8 at the muzzle for 0.06 s. |
| PLAYER_HIT | Red edge flash: 12 px bands on all four arena edges, alpha 0.6 → 0 over 0.3 s. The player blinks while invulnerable. |

When several statuses apply, the body tint uses the highest priority one: burning > poisoned > chilled.
Every overlay (flames, ring, dots) is still drawn.

---

## E. Editor UI (left panel)

### E.1 Layout

All coordinates are absolute, inside the 600×900 panel at screen (0,0). There are no containers, so
tests can compute positions.

| Element | Rect (x, y, w, h) | Content |
|---|---|---|
| Panel background | 0, 0, 600, 900 | `Panel` with the theme's PANEL_BG and PANEL_EDGE style box |
| Title | 20, 12, 300, 44 | Label "FACTORY", size 20, ACCENT |
| Start button | 360, 18, 220, 32 | "START WAVE %d  [Space]"; disabled unless BUILD with a valid plan |
| Board | 20, 64, 560, 480 | `FactoryBoard` (14×12 tiles of 40 px) |
| Status line | 20, 552, 560, 22 | Label, size 12 (E.8) |
| Palette | slot i at (20 + 78·i, 582), 72×88 | 7 `PaletteSlot`s in `PALETTE_ORDER` |
| Readout | 20, 678, 560, 214 | `ShotReadout` (E.7); bottom edge at y 892 |

`FactoryPanel` constants: `BOARD_POS = Vector2(20, 64)`, `PALETTE_POS = Vector2(20, 582)`,
`SLOT_STEP = 78.0`, `READOUT_POS = Vector2(20, 678)`.

### E.2 Board rendering (Factorio look)

Layers are drawn back to front:

1. **Floor** (`FloorLayer`). A child with `show_behind_parent = true` and mouse ignored. It draws once,
   and again on resize.
   - The floor rect is filled with SEAM.
   - Each 40 px tile is a plate inset by 1 px. Plates alternate FLOOR_A and FLOOR_B in a checkerboard,
     and each gets a ±0.036 brightness jitter from `posmod(hash(Vector2i(x, y)), 7)`.
   - Each plate has a 1 px highlight line on its top edge.
   - Plates where `(x + y)` is even get 4 corner bolts of radius 1.4 px.
2. **Belts** (`BeltPainter.draw_belt`, along `BoardLayout.belt_points`):
   - a 14 px BELT_BED bed;
   - two RAIL polylines at ±6 px;
   - chevrons every 12 px. On live belts they scroll at 40 px/s in BUILD and 100 px/s while locked.
     Belts that are not live are dimmed (CHEVRON_DIM) and still;
   - on live belts only: 8 px items every 28 px, cycling through the colours of `plan.streams_on(w)`;
   - hover: a hovered belt, or the belt a palette drag would splice into, is drawn brightened (tint 1.25).
3. **Machines** (`MachinePainter.draw_machine`). Rect = cell×40, size 80×80:
   - a bevelled STEEL body inset 3 px, with a STEEL_LIGHT top and left bevel and a STEEL_DARK bottom
     and right bevel;
   - a 2 px OUTLINE;
   - a colour stripe in the kind colour, 5 px tall, near the top;
   - 4 rivets;
   - the procedural kind icon (E.2.1) at the centre;
   - the short name at the bottom (size 11);
   - a status lamp (r 4) at the top right, coloured by status (C.7);
   - the id plate "#id" for removable machines;
   - an input port marker: a dark notch with an ACCENT triangle;
   - output port markers: an ACCENT dot with an OUTLINE ring.
   A hovered machine gets a 2 px ACCENT outline.
4. **Gesture feedback**:
   - The machine being dragged is drawn at alpha 0.35 in its old place.
   - A ghost (alpha 0.6) is drawn at the target cell, with a 2 px OK or ERROR outline.
   - While a dragged machine's cursor is outside the floor, the old place gets an ERROR outline and the
     label "RELEASE TO REMOVE".
   - A wire preview runs from the output anchor to the snapped input or to the cursor. It is 4 px wide:
     OK when it can connect, ERROR when refused, CHEVRON when there is no target.
   - A refusal reason box is drawn next to the cursor and clamped inside the board. It has a PANEL_BG
     background at 92% alpha, an ERROR border and size-12 text.
5. **Lock overlay** (when locked):
   - PANEL_BG at 45% alpha;
   - HAZARD diagonal stripe bands, 14 px tall, at the top and bottom;
   - the lock text (for example "LOCKED · WAVE 3 IN PROGRESS"), centred, size 20, HAZARD.

#### E.2.1 Icons (`MachinePainter.draw_icon`, frozen WP3 → WP4 contract)

```gdscript
static func draw_icon(ci: CanvasItem, kind: StringName, centre: Vector2, s: float, alpha: float, t: float) -> void
```

`ci` is the CanvasItem whose `_draw()` is running. `t` is the animation time in seconds. Each caller keeps
its own clock: `FactoryBoard` passes its icon time (E.5), and `RewardOverlay` accumulates `delta` in
`_process` and calls `queue_redraw()` while visible (G.4).

Each icon is about 2·s wide, built from `draw_*` primitives:

| Kind | Icon |
|---|---|
| Source | A cartridge: a brass body and a copper tip triangle. |
| Output | A barrel rectangle with 3 ACCENT spray lines. |
| Fire | A two-layer flame polygon that flickers with `sin(t·11)`. |
| Ice | A 3-axis snowflake with side ticks. |
| Poison | A drop (circle plus triangle) and 2 bubbles. |
| Speed Up | A double chevron. |
| Size Up | A dot, a ring and 4 diagonal ticks. |
| Pierce | A plate with an arrow through it. |
| Splitter | A Y-fork with a hub dot. |

### E.3 Geometry (pure, static)

`BoardLayout`. Constants: `TILE 40`, `MACHINE_SIZE (80,80)`, `PORT_HIT 12`, `MAGNET 24`, `BELT_HIT 8`,
`SPLICE 10`, `DRAG_THRESHOLD 6`.

```gdscript
static func bounds() -> Rect2                                   # (0,0,560,480)
static func machine_rect_at(cell: Vector2i) -> Rect2
static func machine_rect(graph: FactoryGraph, id: int) -> Rect2
static func input_anchor_at(cell: Vector2i) -> Vector2          # cell*40 + (0, 40)
static func output_anchor_at(cell: Vector2i, port: int, port_count: int) -> Vector2
	# one output: cell*40 + (80, 40); two outputs: cell*40 + (80, 20 + 40*port)
static func port_anchor(graph: FactoryGraph, ref: PortRef) -> Vector2
static func ports_of(graph: FactoryGraph, id: int) -> Array[PortRef]
static func drop_cell(center: Vector2) -> Vector2i
	# Vector2i((center / 40 - (1, 1)).round()) clamped to [0, 12] x [0, 10]
static func belt_points(graph: FactoryGraph, w: Wire) -> PackedVector2Array   # via BeltRouter.route
static func hit_test(graph: FactoryGraph, p: Vector2) -> BoardHit
	# OUTSIDE if not in bounds; else PORT (nearest anchor within 12 px; ties: output beats input)
	# > MACHINE (cell owner) > BELT (nearest within 8 px; ties: canonical wire order) > EMPTY
static func belt_at(graph: FactoryGraph, p: Vector2, max_dist: float) -> Wire
static func nearest_input(graph: FactoryGraph, p: Vector2, max_dist: float, exclude_id: int) -> PortRef
```

**Port ties.** Side-by-side machines share an anchor: the Source at (1,5) has its output at (120,240),
and a machine at (3,5) has its input at the same point. The output port wins every tie at equal
distance. Only an output and an input can tie (two outputs are at least 40 px apart, two inputs at least
80 px), so no further tie-break exists. A press there therefore starts a wire from the left machine,
and a right-click or X cuts the belt on that output (E.4). A belt between adjacent machines has zero
length, so this port is its only hit target. The right machine is still dragged or removed through its
body.

`BeltRouter`. Constants: `STUB 20`, `LANE_STEP 8`.

```gdscript
static func route(a: Vector2, b: Vector2, from_rect: Rect2, to_rect: Rect2, lane: float, bounds: Rect2) -> PackedVector2Array
	# 1. same y and b.x >= a.x                 -> [a, b]
	# 2. b.x - a.x >= 2*STUB (Z route)         -> mx = clamp(snappedf((a.x+b.x)/2, STUB) + lane, a.x+STUB/2, b.x-STUB/2)
	#                                             [a, (mx, a.y), (mx, b.y), b]
	# 3. otherwise (around)                    -> x1 = a.x+STUB, x2 = b.x-STUB; lane_y = midpoint of the vertical gap
	#    between the rects, or (if they overlap vertically) min(max bottom + STUB, bounds.end.y - 6); lane_y += lane
	#                                             [a, (x1,a.y), (x1,lane_y), (x2,lane_y), (x2,b.y), b]
static func lane_offset(from_port: int, port_count: int) -> float
	# (float(from_port) - (port_count - 1) / 2.0) * LANE_STEP: -4 and +4 for a Splitter, 0 for one output.
	# Divide by 2.0: (port_count - 1) / 2 is integer division and gives 0 and +8.
static func length(points: PackedVector2Array) -> float
static func distance_to(points: PackedVector2Array, p: Vector2) -> float   # Geometry2D.get_closest_point_to_segment per segment
static func sample(points: PackedVector2Array, d: float) -> Array[Vector2] # [position, unit direction] at arc length d (clamped)
```

Small value types:

- `PortRef(machine_id, port, is_output)` with `make()` and `equals()`.
- `BoardHit(type: EMPTY|PORT|MACHINE|BELT|OUTSIDE, machine_id, port: PortRef, wire: Wire)` with
  `make()` and `same_as()`.
- `DropPreview(kind, cell, valid, splice: Wire, reason)`.
- `BoardAction(type: NONE|PLACE|MOVE|REMOVE|CONNECT|DISCONNECT, kind, machine_id, cell, splice, from, to, wire, refusal)`.
  Constructors: `none(refusal = "")`, `make_place`, `make_move`, `make_remove`, `make_connect` and
  `make_disconnect`. They use the `make_` prefix because `Object` already has `connect` and
  `disconnect`.

### E.4 Interaction (`BoardInteraction`, pure)

The board's pointer state machine takes board-local positions and returns a `BoardAction`. It **reads**
the graph and the inventory and never mutates them.

```
IDLE --press LMB on output port--> DRAG_WIRE --release--> IDLE   (CONNECT / refusal / silent cancel)
IDLE --press LMB on machine or input port--> PRESS_MACHINE --move > 6 px--> DRAG_MACHINE --release--> IDLE
PRESS_MACHINE --release (no drag)--> IDLE (nothing: there is no selection in v1)
any --cancel() / set_locked(true) / RMB press while not IDLE--> IDLE
```

| Gesture | Result |
|---|---|
| Drag a palette slot onto the board | PLACE at `drop_cell(cursor)`. If a belt is within 10 px of the cursor and `can_splice` is OK, the placement splices into that belt. |
| Drag a machine; release on the floor | MOVE to `ghost_cell()`; belts follow. If invalid: refused with the reason, and the machine stays. |
| Drag a machine; release outside the floor | REMOVE (refund). For the Source or Output: refused with the NOT_REMOVABLE text. |
| Drag from an output port; release with an input port within 24 px (magnet, own machine excluded) | CONNECT (replaces that output's old belt). If refused: the reason, plus " This belt would make N." for TOO_MANY_BULLETS. |
| Drag from an output port; release with no input port in range | Nothing (silent cancel). |
| Right-click a machine, its input port, or an output port with no belt | REMOVE (refund), or the NOT_REMOVABLE refusal. |
| Right-click a belt, or an output port that carries a belt | DISCONNECT that belt. |
| Right press while a gesture runs (PRESS_MACHINE, DRAG_MACHINE, DRAG_WIRE) | `cancel()`; nothing else. |
| Delete or X key | The same as a right-click on the currently hovered thing. |
| Escape | `cancel()`. During a palette drag, Godot itself cancels the drag on Escape (built-in `ui_cancel`) and consumes the key, so nothing needs coding (verified). |
| Mouse wheel, or any button other than left and right | Nothing: `press()` returns `BoardAction.none()` without a refusal, also while locked. |
| A left or right press while locked | Refused with the LOCKED text. |

```gdscript
class_name BoardInteraction
extends RefCounted
enum Mode { IDLE, PRESS_MACHINE, DRAG_MACHINE, DRAG_WIRE }
var mode: Mode = Mode.IDLE
var locked: bool = false
var graph: FactoryGraph = FactoryGraph.create_default()
var inventory: Inventory = Inventory.new()
var hover: BoardHit = BoardHit.new()
var cursor: Vector2 = Vector2.ZERO
var drag_id: int = -1
var drag_grab: Vector2 = Vector2.ZERO     # cursor minus the dragged machine's top-left, fixed at press
var wire_from: PortRef = null
var wire_target: PortRef = null           # magnet-snapped input port, or null
var wire_code: GraphError.Code = GraphError.Code.OK
func bind(p_graph: FactoryGraph, p_inventory: Inventory) -> void
func set_locked(value: bool) -> void      # true also cancels
func cancel() -> void
func press(p: Vector2, button: MouseButton) -> BoardAction
	# sets cursor = p, then: 1. not LEFT/RIGHT -> none(); 2. RIGHT while not IDLE -> cancel(), none();
	# 3. locked -> LOCKED refusal; 4. RIGHT -> secondary(BoardLayout.hit_test(graph, p));
	# 5. LEFT -> start a gesture (diagram above)
func motion(p: Vector2) -> void           # sets cursor = p; IDLE: refresh_hover(); else drag threshold, wire target
func release(p: Vector2) -> BoardAction   # sets cursor = p; left button only; none() in IDLE
func refresh_hover() -> void              # hover = hit_test(graph, cursor) if IDLE and cursor in bounds(), else BoardHit.new()
func secondary(hit: BoardHit) -> BoardAction   # right-click / Delete semantics (table above)
	# BELT, or an output PORT with a belt -> DISCONNECT that belt; MACHINE or any other PORT -> REMOVE its
	# machine (or the NOT_REMOVABLE refusal); EMPTY / OUTSIDE -> none()
func ghost_cell() -> Vector2i             # drop_cell(cursor - drag_grab + MACHINE_SIZE / 2)
func ghost_valid() -> bool
func is_drag_outside() -> bool            # DRAG_MACHINE and cursor not in BoardLayout.bounds()
func drop_preview(kind: StringName, p: Vector2) -> DropPreview
	# LOCKED if locked; else OUT_OF_STOCK if inventory.count(kind) == 0; else splice if a belt is
	# within SPLICE px of p and can_splice is OK; else can_add_machine(kind, drop_cell(p))
func drop(kind: StringName, p: Vector2) -> BoardAction   # PLACE, or NONE with the preview's reason
func refusal_text() -> String
```

### E.5 `FactoryBoard` (Control, 560×480, `clip_contents`, mouse STOP)

```gdscript
class_name FactoryBoard
extends Control
signal place_requested(kind: StringName, cell: Vector2i, splice: Wire)   # splice may be null
signal move_requested(machine_id: int, cell: Vector2i)
signal remove_requested(machine_id: int)
signal connect_requested(from_id: int, from_port: int, to_id: int, to_port: int)
signal disconnect_requested(wire: Wire)
signal refused(reason: String)
const DRAG_TYPE: String = "factorygun.machine"
const BELT_SPEED_BUILD: float = 40.0
const BELT_SPEED_PLAY: float = 100.0
var interaction: BoardInteraction = BoardInteraction.new()
func bind(graph: FactoryGraph, inventory: Inventory) -> void   # also graph.changed.connect(_on_graph_changed)
func set_plan(plan: ShotPlan) -> void
func set_locked(locked: bool, text: String) -> void
	# locking also calls get_viewport().gui_cancel_drag() when is_inside_tree() and get_viewport().gui_is_dragging()
func cancel_interaction() -> void
func delete_hovered() -> void             # applies interaction.secondary(interaction.hover) when IDLE
```

Input routing:

- `_gui_input`:
  - A mouse button press calls `press(...)`. `press()` itself ignores the wheel and other buttons.
  - A left-button release calls `release(...)`.
  - Motion calls `motion(...)`.
  - Every resulting action goes to `_apply(action)`, which emits the matching `*_requested` signal, or
    `refused(reason)` for a NONE action with a non-empty reason. `_apply` ends with
    `interaction.refresh_hover()`.
- **Hover is never stale.** `_on_graph_changed()` calls `interaction.refresh_hover()`. Every graph
  mutation emits `changed` synchronously (B.4), so after a removal, a cut, a heal or a restart (which
  resets ids), `hover` names only machines and belts that exist. Painters and the status line may
  dereference it without checks.
- While the mouse button is held, Godot keeps sending events to the board even outside its rect. That
  is how "release outside the floor" is detected.
- Palette drops use Godot drag-and-drop. The overrides must keep the parent's `Variant` parameter: a
  `data: Dictionary` parameter is a parse error ("The function signature doesn't match the parent",
  verified).
  - `func _can_drop_data(at: Vector2, data: Variant) -> bool` returns `true` when
    `data is Dictionary and data.get("type") == DRAG_TYPE`. It then stores
    `interaction.drop_preview(kind, at)` with `kind = data["kind"]` for drawing (the board draws the
    ghost and the reason).
  - `func _drop_data(at: Vector2, data: Variant) -> void` applies `interaction.drop(kind, at)`.
- `_process`:
  - advances the belt scroll and the icon time, then calls `queue_redraw()`;
  - clears the stored drop preview when `!get_viewport().gui_is_dragging()` or when the mouse is
    outside the board rect.
- `mouse_exited`, when the mode is IDLE, sets `interaction.cursor = Vector2(-1, -1)` and calls
  `refresh_hover()`, so a later graph change cannot re-hover a point the mouse has left.

### E.6 Palette (`PaletteSlot`, 72×88, mouse STOP)

```gdscript
class_name PaletteSlot
extends Control
const SLOT_SIZE: Vector2 = Vector2(72, 88)
var kind: StringName
var count: int = 0
var ever_owned: bool = false
var locked: bool = false
func setup(p_kind: StringName) -> void
func set_state(p_count: int, p_ever_owned: bool, p_locked: bool) -> void   # also cursor shape + tooltip
func can_drag() -> bool                   # not locked and count > 0
func make_drag_data() -> Dictionary       # {"type": FactoryBoard.DRAG_TYPE, "kind": kind}
func _get_drag_data(_at: Vector2) -> Variant:
	if not can_drag():
		return null
	# set_drag_preview errors outside a real drag, and get_viewport() is null off-tree (direct test calls)
	if is_inside_tree() and get_viewport().gui_is_dragging():
		set_drag_preview(MachineGhost.make(kind))
	return make_drag_data()
```

How a slot is drawn:

- A STEEL_DARK box with a 2 px PANEL_EDGE border.
- The icon at (36, 30).
- The short name at y 62.
- The count `×N` at y 80: ACCENT when `N > 0`, TEXT_DIM when `N = 0` (the icon is then drawn at 35%
  alpha).
- **A never-owned kind** draws only a large "?" and "???" in TEXT_DIM.
- Tooltips:
  - owned kind: `display_name` + newline + `description`;
  - never-owned kind: "Not found yet. Clear waves to earn new machines."

`MachineGhost` is the drag preview. It is a `Control`, mouse ignored, that draws the machine at alpha
0.7 in `Rect2(-40, -40, 80, 80)`, so the preview is centred on the cursor.

### E.7 Shot readout (`ShotReadout`, 560×214)

The readout has two parts:

- **Text.** A Label at (8, 6), size 420×204, font size 12, `clip_text = true`, and
  `add_theme_constant_override("line_spacing", 0)`. Its text is `"\n".join(plan.summary_lines())`.
  The font is 17 px high at size 12, and the default theme adds `line_spacing = 3`, so without the
  override each line takes 20 px. `clip_text` clips only horizontally: a taller text grows the label
  past the panel (verified).
- **Fan diagram.** A 120×120 box at (432, 45) with a PANEL_EDGE border and the title "FAN".
  - The origin is at (10, 60) inside the box.
  - For each bullet, draw a 2 px ray, 100 px long, at its `angle_offset`, in its `primary_color()`.
  - At the end of each ray, draw a dot with radius `clamp(spec.radius, 3, 10)`.

`ShotPlan.summary_lines()` returns these lines, in order:

1. A headline. With no bullets it is `"NO PATH: connect the Basic Bullet to the Output"`. Otherwise it is
   `"%d bullet%s/shot · %d shots/s · %.1f dmg/shot"`, for example
   `"2 bullets/shot · 4 shots/s · 14.0 dmg/shot"`.
2. One row per bullet: `"#%d " + describe()`.
3. Up to 2 non-ERROR issue lines, each `"! " + text`.
4. If there are more non-ERROR issues, `"… %d more"`, where `%d` counts the ones not shown.

The worst case is 12 lines (1 + 8 + 2 + 1). With `line_spacing` 0 they measure 204 px, which fits the
204 px label (verified: 11 lines 187 px, 12 lines 204 px, 13 lines 221 px). The longest possible bullet
row measures 415 px at size 12 (verified), so it fits the 420 px label.

### E.8 Status line

One Label, size 12, with `clip_text = true` and
`text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS`. The longest hover text (the Splitter's,
686 px) is wider than the 560 px label; without `clip_text` the label grows to its text width and runs
under the arena (verified). `FactoryPanel._process` rebuilds the text every frame from the message
timer, `board.interaction.hover`, the current plan and the start state, so it is never stale. It shows
the first of these that applies:

1. A message from `show_message(text, is_error)`. It lasts 2.5 s, in ERROR (if `is_error`) or TEXT
   colour. Board refusals and RunState refusals both use it.
2. Something hovered on the board:
   - Machine, or its input port: `"<display_name> #<id>: <description>"`, plus `"  [capped]"`,
     `"  [one-sided]"`, `"  [dead end]"` or `"  [idle]"` when the status is not ACTIVE. The Source and
     Output omit `#id`.
   - Output port (with or without a belt): "Output port: drag to an input port to connect."
   - Belt: "Belt: right-click or X to cut."
3. If Start is disabled in BUILD: `start_reason()`.
4. Otherwise: "Drag machines onto the floor. Drag from an output port to wire. Right-click removes."
   (TEXT_DIM).

### E.9 `FactoryPanel` (Panel 600×900)

```gdscript
class_name FactoryPanel
extends Panel
signal start_wave_requested
const BOARD_POS: Vector2 = Vector2(20, 64)
const PALETTE_POS: Vector2 = Vector2(20, 582)
const SLOT_STEP: float = 78.0
const READOUT_POS: Vector2 = Vector2(20, 678)
var board: FactoryBoard
var start_button: Button
var status_label: Label
var slots: Array[PaletteSlot] = []        # PALETTE_ORDER
var readout: ShotReadout
func bind(graph: FactoryGraph, inventory: Inventory) -> void   # call once; refreshes the palette on inventory.changed
func set_plan(plan: ShotPlan) -> void                          # board + readout
func set_locked(locked: bool, text: String) -> void            # board, palette slots, start button
func set_start_state(wave: int, enabled: bool, reason: String) -> void
func show_message(text: String, is_error: bool) -> void
```

- The panel handles the board's `refused(reason)` itself, as `show_message(reason, true)`.
- `Main` connects directly to the board's five `*_requested` signals and to `start_wave_requested`.
- Clicking the Start button emits `start_wave_requested`.

`FactoryTheme.build() -> Theme` (WP3) builds the theme in code with `StyleBoxFlat`s:

- Default font size 14.
- `Button` normal: STEEL with an OUTLINE border. Hover: STEEL_LIGHT. Pressed: STEEL_DARK with an ACCENT
  border. Disabled: STEEL_DARK with a STEEL border. Focus: `StyleBoxEmpty`.
- Button font colours: TEXT; pressed ACCENT; disabled TEXT_DIM.
- `Label` font colour: TEXT.
- `Panel` and `PanelContainer`: PANEL_BG with a PANEL_EDGE border.
- Every box: border 2, corner radius 2, content margins 8/4.

---

## F. Arena (right side)

### F.1 World and numbers (`SimTuning`, WP2)

The arena is 1000×900. World coordinates equal the local pixel coordinates of the arena control (screen
x 600–1600).

```gdscript
class_name SimTuning
extends RefCounted
const STEP: float = 1.0 / 60.0            # physics ticks are 60/s; tests step with this
const ARENA_SIZE: Vector2 = Vector2(1000, 900)
const PLAYER_SPEED: float = 240.0
const PLAYER_RADIUS: float = 13.0
const PLAYER_INVULN: float = 0.6
const MUZZLE_OFFSET: float = 22.0
const MAX_LIVE_ENEMIES: int = 40          # spawns wait while 40 are alive
const DESPAWN_MARGIN: float = 60.0
const SPAWN_OUTSIDE: float = 30.0         # enemies appear 30 px outside the edge and walk in
const SPAWN_MIN_PLAYER_DIST: float = 260.0
const SPAWN_CANDIDATES: int = 4
const FIRST_SPAWN_DELAY: float = 1.0
const CLEAR_GRACE: float = 1.0
const CONTACT_PUSHBACK: float = 30.0
const SEPARATION: float = 0.5             # fraction of a pair's overlap removed per step, split equally:
                                          # each enemy of the pair moves SEPARATION / 2 · overlap
static func hp_mult(wave: int) -> float         # 1 + 0.15·(wave − 1)
static func speed_mult(wave: int) -> float      # min(1 + 0.03·(wave − 1), 1.4)
static func spawn_interval(wave: int) -> float  # max(0.3, 1.0 − 0.05·(wave − 1))
```

The number of live bullets needs no cap: at most `ceil(1.4 / 0.25) · 8 = 48` bullets exist at once.

### F.2 Player and gun

- The player is a circle of r 13. It starts each wave at the centre (500, 450).
- It moves at 240 px/s from `Input.get_vector(move_left, move_right, move_up, move_down)`, so diagonals
  are normalised. It is clamped to `[13, 987] × [13, 887]`.
- HP carries over between waves (`RunState.player_hp`). Contact damage makes the player invulnerable for
  0.6 s.
- **Aim**: `intent.aim` is an arena-local target point (the mouse position, or the bot's target), not a
  direction. The world sets `aim_dir = (intent.aim − player.pos).normalized()`. When that distance is
  under 1 px, it keeps the previous `aim_dir`.
- **Fire**: while fire is held and `plan.is_valid()`, every 0.25 s the gun fires **all** of the plan's
  bullets at once:
  - Each bullet starts at the muzzle `player.pos + aim_dir·22`.
  - Its velocity is `aim_dir.rotated(spec.angle_offset) · spec.speed`.
  - Its `pierce_left` is `spec.pierce`.
  - The cooldown code is exact (F.4 step 3). It keeps falling while fire is released, and a shot sets
    it rather than adding to it, so holding fire after a pause never fires a burst. From `begin_wave`,
    60 steps of 1/60 s fire on steps 1, 16, 31 and 46: exactly 4 shots per second (verified).

### F.3 Enemies and waves

| Type | HP | Speed | Radius | Contact dmg | Sides | Colour |
|---|---|---|---|---|---|---|
| Grunt | 30 | 70 | 14 | 10 | 6 | `b5502f` |
| Runner | 16 | 130 | 10 | 6 | 3 (points at the player) | `d9a33a` |
| Brute | 150 | 42 | 24 | 22 | 8 | `7d4fb3` |

- **Per-wave scaling:** `max_hp = base · hp_mult(w)` and `speed = base · speed_mult(w)`.
- **Movement:** each enemy moves straight toward the player at `speed · status.speed_multiplier()`.
- **Separation:** for each overlapping pair, push each enemy apart by `SEPARATION / 2` = 25% of the
  overlap per step, so the pair loses half its overlap. This is O(n²), with n ≤ 40.
- **Contact:** an enemy within `r + 13` of the player does `contact_damage` if the player is not
  invulnerable, which also starts the 0.6 s invulnerability. The enemy is always pushed 30 px directly
  away from the player.
- **Wave composition** for wave `w`:
  - Grunts: `4 + 2w`.
  - Runners: `2(w − 1)`.
  - Brutes: `floor((w − 2) / 2)` when `w >= 4`, else 0.
  - `WavePlan.order(w, rng)` shuffles these with Fisher–Yates: `i` from n−1 down to 1,
    `j = rng.randi_range(0, i)`.
  - Spawn `k` is due at `1.0 + k · spawn_interval(w)`.
- **Spawn point:** try up to 4 random points on the rectangle 30 px outside the arena edges. Each
  point is on a random side, at a uniform position along that side. Take the first point at least
  260 px from the player; if none qualifies, take the farthest.
- **Waves are endless.** The run ends only when the player dies.

### F.4 `ArenaWorld.step(delta, intent)` (fixed order)

```
if not running: return []
time += delta
1. spawns   - while next spawn is due and fewer than 40 enemies are alive: spawn it.
2. player   - move, clamp, invuln -= delta, update aim_dir.
3. gun      - cooldown = maxf(cooldown - delta, 0.0)
              if intent.fire and plan.is_valid() and cooldown <= 1e-6:
                  fire every bullet of the plan (F.2), emit one SHOT, cooldown = Tuning.GUN_INTERVAL
4. bullets  - D.4; emit HIT.
5. enemies  - for each live enemy: hp -= status.tick(delta); move toward the player.
              Then separation, then contact (emit PLAYER_HIT on damage).
6. deaths   - remove enemies with hp <= 0 in id order; kills += 1; emit KILL.
7. end      - if player.hp <= 0: hp = 0, finished, emit PLAYER_DIED (death wins over clear).
              elif all spawned and no enemies: clear_timer += delta; at >= 1.0 s: finished, emit WAVE_CLEARED.
return events
```

`enemies` stays sorted by id: new ids only grow, and removal keeps the order.

### F.5 Sim API (WP2, all `extends RefCounted`)

```gdscript
class_name EnemyType          # enum Kind { GRUNT, RUNNER, BRUTE }; display_name, max_hp, speed, radius,
                              # contact_damage, sides, color; static func get_type(kind: Kind) -> EnemyType
class_name WavePlan           # static func counts(wave: int) -> Dictionary[EnemyType.Kind, int]
                              # static func order(wave: int, rng: RandomNumberGenerator) -> Array[EnemyType.Kind]
                              # static func spawn_time(wave: int, index: int) -> float
class_name CollisionMath      # static func first_contact(a: Vector2, b: Vector2, c: Vector2, r: float) -> float
class_name PlayerIntent       # var move: Vector2, aim: Vector2, fire: bool
                              # aim: an arena-local target POINT, not a direction (F.2)
                              # static func make(p_move: Vector2, p_aim: Vector2, p_fire: bool) -> PlayerIntent  (move limited to length 1)
class_name SimEvent           # enum Type { SHOT, HIT, KILL, PLAYER_HIT, WAVE_CLEARED, PLAYER_DIED }
                              # var type: Type, pos: Vector2, color: Color, entity_id: int
                              # static func make(p_type: Type, p_pos: Vector2, p_color: Color = Color.WHITE, p_entity_id: int = -1) -> SimEvent
                              # HIT: colour = bullet primary colour, id = enemy; KILL: colour = enemy colour
class_name PlayerState        # var pos: Vector2, hp: float, invuln: float, aim_dir: Vector2 = Vector2.RIGHT
class_name EnemyState         # var id: int, type: EnemyType, pos: Vector2, hp: float, max_hp: float, speed: float,
                              # status: StatusEffects; func radius() -> float
class_name BulletState        # var id: int, spec: BulletSpec, pos: Vector2, vel: Vector2, pierce_left: int,
                              # life: float, hit_ids: Dictionary[int, bool]

class_name ArenaWorld
var wave: int = 0
var time: float = 0.0
var player: PlayerState
var enemies: Array[EnemyState] = []
var bullets: Array[BulletState] = []
var kills: int = 0
var plan: ShotPlan = ShotPlan.empty()
func begin_wave(p_wave: int, p_plan: ShotPlan, wave_seed: int, player_hp: float) -> void   # resets below
func reset_idle(player_hp: float) -> void        # begin_wave's resets except wave, plan and rng; empty schedule; not running
func is_running() -> bool
func is_finished() -> bool
func enemies_remaining() -> int                  # alive + not yet spawned
func step(delta: float, intent: PlayerIntent) -> Array[SimEvent]
func state_hash() -> int                         # hash([time, player pos/hp/invuln, kills, next spawn, cooldown,
                                                 #       rng.state] + per enemy [id, pos, hp] + per bullet [id, pos, pierce_left])
func spawn_enemy(kind: EnemyType.Kind, pos: Vector2) -> int   # used by step(); public for tests
func cancel_spawns() -> void                     # tests only: drop the remaining schedule
```

The world owns a `RandomNumberGenerator` seeded with `wave_seed`. The same `(wave, plan, seed, hp)` and
the same sequence of intents give the same events and the same `state_hash()`.

`begin_wave` resets everything a wave depends on, so nothing carries over from the previous wave:

- It sets `wave` and `plan`, then `rng.seed = wave_seed` and builds the spawn schedule with
  `WavePlan.order(wave, rng)`.
- It sets `time`, `kills`, `cooldown`, `clear_timer` and the next-spawn index to 0, and the next enemy
  and bullet ids to 1. It empties `enemies` and `bullets`.
- The player is at (500, 450) with `hp = player_hp`, `invuln = 0` and `aim_dir = Vector2.RIGHT`.
- It sets `running = true` and `finished = false`.

`kills` therefore counts this wave only, and `RunState` adds it to `total_kills` (B.8).

### F.6 `ArenaController` (WP2, Control 1000×900)

```gdscript
class_name ArenaController
extends Control
## Glue between engine input, the pure ArenaWorld and the views.
signal wave_cleared(hp_left: float, kills: int)
signal player_died(kills: int)
var world: ArenaWorld = ArenaWorld.new()
var view: ArenaView                       # child, mouse IGNORE, view.world = world
var hud: Hud                              # child, mouse IGNORE
# Both children get set_anchors_preset(Control.PRESET_FULL_RECT) in _init() and never a size (A.4.5).
var intent_override: PlayerIntent = null  # tests set this instead of real input
func start_wave(wave: int, plan: ShotPlan, wave_seed: int, hp: float) -> void   # begin_wave, clear FX, HUD banner "WAVE %d"
func go_idle(hp: float, next_wave: int) -> void                                # reset_idle, clear FX, HUD idle
func is_running() -> bool
func step(delta: float) -> void
func _physics_process(delta: float) -> void:
	step(delta)
```

```gdscript
func step(delta: float) -> void:
	if not world.is_running():
		return
	var intent: PlayerIntent = intent_override if intent_override != null else _read_intent()
	view.add_events(world.step(delta, intent))
	hud.set_stats(world.player.hp, world.enemies_remaining())
	if world.is_finished():               # emitting is the LAST statement: handlers may call go_idle()
		if world.player.hp <= 0.0:
			player_died.emit(world.kills)
		else:
			wave_cleared.emit(world.player.hp, world.kills)

func _read_intent() -> PlayerIntent:
	var aim: Vector2 = get_local_mouse_position()
	var fire: bool = Input.is_action_pressed(InputSetup.FIRE) and Rect2(Vector2.ZERO, size).has_point(aim)
	return PlayerIntent.make(Input.get_vector(InputSetup.MOVE_LEFT, InputSetup.MOVE_RIGHT,
			InputSetup.MOVE_UP, InputSetup.MOVE_DOWN), aim, fire)
```

- The signals are connected synchronously, not deferred. That is safe because emitting is the last thing
  `step()` does, and tests can then drive a whole wave with plain `step()` calls.
- Mouse settings: `clip_contents = true`, `mouse_filter = MOUSE_FILTER_PASS`,
  `mouse_default_cursor_shape = CURSOR_CROSS`.
- `Input.is_action_pressed` keeps working while the GUI handles the click.
- Fire requires the cursor to be over the arena, so clicking the locked editor never shoots.
- **Tests:** call `arena.set_physics_process(false)` first, then drive `step(SimTuning.STEP)`.

### F.7 `ArenaView` (WP2, Control) and `Hud` (WP2, Control)

`ArenaView` draws `world` every frame (`_process` → `queue_redraw()`). Its public API is
`var world: ArenaWorld`, `add_events(events: Array[SimEvent])` and `clear_fx()`. It draws, in order:

1. The floor: ARENA_FLOOR, with ARENA_GRID lines every 50 px and a 2 px PANEL_EDGE border.
2. The player: a PLAYER circle, plus a 5 px gun barrel 22 px long along `aim_dir`. While invulnerable,
   the alpha blinks between 1 and 0.4 every 0.1 s.
3. Enemies: regular polygons with `sides` sides. The Runner is rotated to point at the player.
4. Bullets, FX, statuses, HP bars and the edge flash, as in table D.5.

Transient FX (rings, bursts, muzzle flashes, hit flashes by enemy id, the edge flash) are created from
SimEvents and aged in `_process`. They are purely visual and not part of the sim state.

`Hud` draws a top bar, 1000×36, PANEL_BG at 85% alpha:

- **Left:** `"WAVE %d"` (size 18).
- **Centre:** an HP bar (240×14 at x 380). The fill is OK, or ERROR below 30 HP. Next to it: `"HP %d"`.
- **Right:**
  - while running: `"ENEMIES %d"`;
  - while idle: `"BUILD PHASE"`.
- **Banner:** `show_banner(text)` shows size-40 ACCENT text centred at y 300 for 1.5 s, fading over the
  last 0.5 s.
- **Idle hint:** while idle, `"Build your gun on the left · press SPACE to start"` (size 16, TEXT_DIM)
  at y 860.

API: `set_wave(wave: int, running: bool)`, `set_stats(hp: float, enemies_left: int)` and
`show_banner(text: String)`.

---

## G. Game state machine and `Main`

### G.1 States and transitions (`GameFlow`, driven only through `RunState`)

```
BUILD --start_wave()--> PLAY --complete_wave()--> REWARD --choose_offer(i)--> BUILD (wave + 1)
                         PLAY --fail_wave()------> GAME_OVER --restart(seed)--> BUILD (wave 1)
```

### G.2 Per-state behaviour

| State | Arena | Editor panel | Overlay | Keys |
|---|---|---|---|---|
| BUILD | `go_idle(hp, wave)`: player at the centre, nothing moves, the gun is locked | unlocked; Start enabled iff the plan is valid | none | Space/Enter start; Delete/X; Esc |
| PLAY | `start_wave(wave, active_plan, wave_seed(), hp)` and running | locked: "LOCKED · WAVE %d IN PROGRESS" | none | WASD/arrows; LMB fire |
| REWARD | `go_idle(hp, wave)` | locked: "CHOOSE A REWARD" | RewardOverlay | 1/2/3, or click a card |
| GAME_OVER | frozen on the last frame (not stepped, not reset) | locked: "GAME OVER" | GameOverOverlay | R, or the Restart button |

### G.3 `Main` (WP4)

```gdscript
class_name Main
extends Control

const PANEL_RECT: Rect2 = Rect2(0, 0, 600, 900)
const ARENA_RECT: Rect2 = Rect2(600, 0, 1000, 900)

var run: RunState = RunState.new(randi())   # randi() is allowed outside core/sim
var panel: FactoryPanel = FactoryPanel.new()
var arena: ArenaController = ArenaController.new()
var reward_overlay: RewardOverlay = RewardOverlay.new()
var game_over_overlay: GameOverOverlay = GameOverOverlay.new()


func _ready() -> void:
	InputSetup.ensure_actions()
	theme = FactoryTheme.build()
	_add(panel, PANEL_RECT)
	_add(arena, ARENA_RECT)
	_add(reward_overlay, ARENA_RECT)        # overlays after the arena: drawn on top
	_add(game_over_overlay, ARENA_RECT)
	panel.bind(run.graph, run.inventory)
	run.plan_changed.connect(_on_plan_changed)
	run.flow.state_changed.connect(_on_state_changed)
	panel.start_wave_requested.connect(_try_start_wave)
	panel.board.place_requested.connect(_on_place_requested)       # -> _report(run.try_place_machine(...))
	panel.board.move_requested.connect(_on_move_requested)         # -> _report(run.try_move_machine(...))
	panel.board.remove_requested.connect(_on_remove_requested)     # -> _report(run.try_remove_machine(...))
	panel.board.connect_requested.connect(_on_connect_requested)   # -> _report(run.try_connect(...))
	panel.board.disconnect_requested.connect(_on_disconnect_requested)  # -> _report(run.try_disconnect(...))
	arena.wave_cleared.connect(_on_wave_cleared)                   # -> run.complete_wave(hp_left, kills)
	arena.player_died.connect(_on_player_died)                     # -> run.fail_wave(kills)
	reward_overlay.offer_chosen.connect(_on_offer_chosen)          # -> run.choose_offer(index)
	game_over_overlay.restart_requested.connect(_on_restart)       # -> run.restart(randi())
	_sync(run.flow.state)


func _report(code: GraphError.Code) -> void:
	if code != GraphError.Code.OK:
		panel.show_message(GraphError.describe(code), true)


func _try_start_wave() -> void:
	if run.flow.state == GameFlow.State.BUILD and not run.start_wave():
		panel.show_message(run.start_reason(), true)


func _on_plan_changed(plan: ShotPlan) -> void:
	panel.set_plan(plan)
	panel.set_start_state(run.flow.wave, run.can_start_wave(), run.start_reason())


func _on_state_changed(_previous: GameFlow.State, current: GameFlow.State) -> void:
	_sync(current)


func _sync(state: GameFlow.State) -> void:
	var wave: int = run.flow.wave
	reward_overlay.visible = state == GameFlow.State.REWARD
	game_over_overlay.visible = state == GameFlow.State.GAME_OVER
	match state:
		GameFlow.State.BUILD:
			panel.set_locked(false, "")
			arena.go_idle(run.player_hp, wave)
		GameFlow.State.PLAY:
			panel.set_locked(true, "LOCKED · WAVE %d IN PROGRESS" % wave)
			arena.start_wave(wave, run.active_plan, run.wave_seed(), run.player_hp)
		GameFlow.State.REWARD:
			panel.set_locked(true, "CHOOSE A REWARD")
			arena.go_idle(run.player_hp, wave)
			reward_overlay.show_offers(run.offers, wave)
		GameFlow.State.GAME_OVER:
			panel.set_locked(true, "GAME OVER")
			game_over_overlay.show_result(wave - 1, run.total_kills)
	panel.set_plan(run.plan)
	panel.set_start_state(wave, run.can_start_wave(), run.start_reason())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputSetup.START_WAVE):
		_try_start_wave()
	elif event.is_action_pressed(InputSetup.DELETE_HOVERED):
		panel.board.delete_hovered()
	elif event.is_action_pressed(InputSetup.CANCEL):
		panel.board.cancel_interaction()
	elif event.is_action_pressed(InputSetup.RESTART) and run.flow.state == GameFlow.State.GAME_OVER:
		run.restart(randi())
	else:
		for i: int in InputSetup.PICK.size():
			if event.is_action_pressed(InputSetup.PICK[i]) and run.flow.state == GameFlow.State.REWARD:
				reward_overlay.choose(i)
```

`_add(c, rect)` does `add_child(c)`, then sets `c.position` and `c.size`. The four controls keep their
default anchors, so setting `size` does not warn (A.4.5). All connections go to methods, and Main is a
Node, so there are no reference cycles.

### G.4 Overlays (WP4)

```gdscript
class_name RewardOverlay
extends Control                           # mouse STOP; draws itself
signal offer_chosen(index: int)
var offers: Array[RewardOffer] = []
func show_offers(p_offers: Array[RewardOffer], wave_cleared: int) -> void   # visible = true
func choose(index: int) -> void           # only if visible and index valid: hide, then emit offer_chosen(index)
func card_rect(index: int) -> Rect2       # Rect2(90 + 280*index, 290, 260, 320), overlay-local

class_name GameOverOverlay
extends Control                           # mouse STOP
signal restart_requested
var restart_button: Button                # "RESTART  [R]", 200x44 at (400, 440), FOCUS_NONE
func show_result(waves_cleared: int, kills: int) -> void
```

**Reward overlay drawing:**

- A full-rect dim: black at 55% alpha.
- Title: `"WAVE %d CLEARED"` (size 32, ACCENT) at y 220.
- Subtitle: `"Choose one machine · +25 HP"` (size 16) at y 255.
- Three cards. Each card has:
  - a STEEL_DARK box with a PANEL_EDGE border (ACCENT on hover);
  - the icon at 80 px from the top (`MachinePainter.draw_icon`, s = 26, `t` = the overlay's own time,
    accumulated from `delta` in `_process`, which also calls `queue_redraw()` while visible);
  - the name (size 22) at +150;
  - `"×%d"` (size 28, ACCENT) at +190;
  - the description (`draw_multiline_string`, width 230, size 13) at +220;
  - `"[%d]"` (size 14, TEXT_DIM) at +300.
- A left click inside `card_rect(i)` (`_gui_input`) calls `choose(i)`.

**Game over overlay drawing:**

- The same dim.
- `"GAME OVER"` (size 48, ERROR) at y 330.
- `"Survived %d wave%s · %d kills"` (size 18) at y 390.

---

## H. Progression

### H.1 Inventory rules

- **Start:** the Basic Bullet and the Output are on the floor, wired. The inventory holds Fire ×1 and
  Speed Up ×1.
- **Placing** a machine (a plain place or a splice) takes 1 from the inventory. **Removing** a machine
  refunds 1. Removing happens by right-click, Delete/X, or dragging the machine off the floor.
- `owned(kind) = inventory + on floor` changes **only** through rewards. A fuzz test asserts this (I.6).
- Inventory counts have no cap. Caps apply per bullet path (D.1).

### H.2 Rewards (`RewardGenerator.generate`)

```gdscript
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
rng.seed = Seeds.derive(run_seed, wave_cleared, Seeds.REWARD)
var picked: Array[StringName] = []
if wave_cleared == 1 and not ever_owned.has(MachineCatalog.SPLITTER):
	picked.append(MachineCatalog.SPLITTER)                 # every run can try branching early
while picked.size() < Tuning.OFFER_COUNT:                   # 3 distinct kinds
	var candidates: Array[StringName] = placeable kinds not in picked (palette order)
	var weights: PackedFloat32Array = weight_of(k, wave_cleared) for each candidate
	picked.append(candidates[rng.rand_weighted(weights)])
sort picked by palette index; return RewardOffer.make(k, amount_of(k, wave_cleared)) for each
```

| Kind | `weight_of` | `amount_of` |
|---|---|---|
| Fire, Ice, Poison, Speed Up, Size Up | 10 | 2 |
| Pierce | 6 | 1 (2 from wave 5) |
| Splitter | `min(2 + wave_cleared, 8)` | 1 |

### H.3 Healing, restart, seeds

- `choose_offer(i)` adds the offer and sets `player_hp = min(player_hp + 25, 100)`.
- `restart(seed)` resets the seed, HP 100, kills 0, offers, `active_plan`, the inventory
  (`assign_from(Inventory.from_counts(Tuning.START_INVENTORY))`: a copy, ever-owned reset to the
  starting kinds) and the graph (default). It then calls `flow.restart()`, which
  goes to BUILD wave 1 and always emits.
- Main restarts with `randi()`. Tests call `run.restart(fixed_seed)`.
- Wave and reward randomness use only `Seeds.derive(run_seed, wave, purpose)`.

### H.4 Balance sanity (the design target, not a test)

| Wave | Enemies (G/R/B) | Total enemy HP |
|---|---|---|
| 1 | 6 / 0 / 0 | 180 |
| 2 | 8 / 2 / 0 | 313 |
| 3 | 10 / 4 / 0 | 473 |
| 4 | 12 / 6 / 1 | 879 |
| 5 | 14 / 8 / 1 | 1117 |
| 10 | 24 / 18 / 4 | 3779 |

The default gun does 40 DPS before DoTs. The balance tests in I.6 require only two things: a scripted
bot with the default gun clears waves 1 and 2, and a player who does nothing dies in wave 1.

---

## I. Testing

### I.1 Setup

- **GUT:** copy `/home/claude/bitwes/gut/addons/gut` (GUT 9.5.0, 241 files including `.uid` and
  `.import`) to `addons/gut`, unmodified.
- **Tests:** they live under `res://test`, in subdirectories. Each test file is named `test_*.gd`, says
  `extends GutTest`, and has `test_*` methods.
- **Config:** `.gutconfig.json` enables the post-run hook (I.3).
- **Command:** the CI command, which you also run locally, is
  `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`.
- **One file:**
  `godot --headless -s addons/gut/gut_cmdln.gd -gconfig= -gtest=res://test/unit/core/test_factory_graph.gd -gexit`.
  - Adding `-gtest` to the CI command still runs every file, because `-gdir` collects them too.
  - `-gtest` without `-gconfig=` makes the post-run hook report every other file as "not run" and exit 1.
  - The empty `-gconfig=` skips `.gutconfig.json`, so the hook does not run (all verified: exit 0, 1
    script). Without the hook a file that fails to parse is skipped and the run still exits 0 with
    "Nothing was run." (verified), so check that the summary says `Scripts 1`. Full-suite runs keep the
    default config.

### I.2 Test-writing rules (each one comes from a verified GUT 9.5.0 or Godot 4.5.1 behaviour, see L.1)

1. **Type everything in tests.** GUT loads test scripts with warnings disabled. The sanity test (I.4)
   re-checks them with the project's warnings-as-errors.
2. **No `class_name` in `test/`.** Load helpers with `const Fixtures = preload("res://test/helpers/fixtures.gd")`.
   A `const` without a type annotation is allowed. Never name a helper file `test_*.gd`.
3. **An engine warning or error inside a test body fails that test.** This includes `push_warning`, and
   is GUT's default `failure_error_types = ["engine", "gut", "push_error"]`. Production code therefore
   never warns or errors on any path.
4. **Errors outside test bodies do not fail a test on their own.** This covers `before_each`,
   `after_each`, `after_all`, deferred calls and frees. The post-run hook fails the run for them.
5. **Nodes:** use `add_child_autofree(node)`. RefCounted objects need no cleanup.
6. **Simulations are stepped directly.** Call `ArenaWorld.step` or `ArenaController.step`. Without
   `--fixed-fps`, physics frames run in real time (60 physics frames ≈ 1 s). Process frames are fast.
   So await process frames, never physics frames in bulk.
7. **Never use a bare `await some_signal`.** It can hang the run. Use `wait_for_signal(sig, max_time)`,
   `wait_until(callable, max_time)` or `wait_process_frames(n)`.
8. **Real mouse input** goes through `Input.parse_input_event`, through `test/helpers/mouse.gd`:
   - First call `await Mouse.prepare(self)`. It sets `get_tree().root.size = Vector2i(1600, 900)`,
     because the headless root window is 64×64.
   - Wait one process frame after each event: events are flushed on the next frame, and the headless
     mouse position is updated.
   - Keep every position at **x < 950**: GUT's own panel covers x 963–1595 during a run.
   - The real mouse is needed only for drag-and-drop and board gestures.
9. **Keys:** call `main._unhandled_input(event)` directly with an `InputEventKey` (`physical_keycode`,
   `pressed = true`). This avoids depending on GUT's GUI focus.
10. **Floats:** use `assert_almost_eq(got, expected, 1e-4)`.
11. **Signals:** call `watch_signals(obj)` before acting, then use `assert_signal_emit_count` or
    `assert_signal_emitted_with_parameters`.
12. **Determinism:** fixed seeds only. `hash()`-based state hashes are compared within one run, never
    against stored constants.

### I.3 `test/gut_post_run.gd` (WP0, verbatim, verified)

```gdscript
extends GutHookScript
## Fails the run for two things GUT 9.5.0 lets pass with exit code 0:
## - errors raised outside a test body (before_each, after_each, deferred calls, frees);
## - test files GUT skipped (parse error, or not extending GutTest).
## Only ever call set_exit_code(1): any exit code set here overrides GUT's own.


func run() -> void:
	var problems: PackedStringArray = []
	var stray: Array = gut.error_tracker.errors.items.get(GutUtils.NO_TEST, []).duplicate()
	for e: GutTrackedError in stray:
		problems.append("error outside a test body: %s %s:%d" % [e.code, e.file, e.line])
	var collected: Dictionary[String, bool] = {}
	for s: Object in gut.get_test_collector().scripts:
		collected[s.get("path")] = true
	for path: String in _test_files("res://test"):
		if not collected.has(path):
			problems.append("test file was not run (parse error, or it does not extend GutTest): " + path)
	for p: String in problems:
		print("POST-RUN CHECK FAILED: " + p)
	if not problems.is_empty():
		set_exit_code(1)


func _test_files(dir: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for f: String in DirAccess.get_files_at(dir):
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		out.append_array(_test_files(dir.path_join(d)))
	return out
```

The hook was verified in four cases:

- A clean run exits 0.
- A test file with a syntax error exits 1.
- A `test_*.gd` file that does not extend GutTest exits 1.
- A `push_error` in `before_each` exits 1.

A failing test still exits 1.

The hook assumes a full `-gdir` run: it compares every `test_*.gd` on disk with the collected scripts.
To run one file, skip the hook with `-gconfig=` (I.1) instead of editing it.

**Copy the iterated error list with `.duplicate()` and report with `print`.** Calling `gut.logger.error`
while iterating the live list appends to it and loops forever.

**The hook must never have a parse error.** A broken hook makes GUT print "Something went wrong and the
run was aborted" and then **hang without exiting**. This was verified: no exit after 120 s. Change the
hook only with a local `timeout 300 godot ...` run.

### I.4 `test/test_project_sanity.gd` (WP0)

```gdscript
extends GutTest
## Plugs GUT 9.5.0 blind spots. GUT loads test scripts, and any src script first pulled in while it
## collects tests, with GDScript warnings disabled, so untyped code would pass. Each script is compiled
## again in a fresh `godot --check-only` process, which applies the project's warnings-as-errors to the
## real file, class_name included. In-process recompiles are unsafe or wrong (L.1 #1b). OS.execute is
## fine here: export_presets.cfg excludes test/ from the web export.

const FORBIDDEN_IN_PURE: String = "\\b(Input|InputMap|Time|OS|Engine|DisplayServer|FileAccess|DirAccess|ResourceLoader)\\.|\\b(Node|Node2D|Control|CanvasItem|SceneTree)\\b|\\bget_tree\\(|\\bawait\\b|\\b(print\\w*|push_warning|push_error)\\(|(?<![.\\w])(randi|randf|randi_range|randf_range|randfn|randomize|seed)\\("


func test_every_script_compiles_with_project_warnings() -> void:
	var project: String = ProjectSettings.globalize_path("res://")
	var paths: PackedStringArray = _scripts("res://src") + _scripts("res://test")
	assert_gt(paths.size(), 0)
	for path: String in paths:
		var out: Array = []
		var code: int = OS.execute(OS.get_executable_path(), ["--headless", "--path", project, "--check-only", "-s", path], out, true)
		assert_eq(code, 0, "%s\n%s" % [path, "\n".join(out)])


func test_core_and_sim_are_pure() -> void:
	var forbidden: RegEx = RegEx.create_from_string(FORBIDDEN_IN_PURE)
	var comment: RegEx = RegEx.create_from_string("#.*")
	for path: String in _scripts("res://src/core") + _scripts("res://src/sim"):
		var code: String = comment.sub(FileAccess.get_file_as_string(path), "", true)
		assert_true(code.contains("extends RefCounted"), path + " must extend RefCounted")
		var hit: RegExMatch = forbidden.search(code)
		assert_null(hit, "%s uses %s" % [path, hit.get_string() if hit != null else ""])


func test_input_actions_are_registered() -> void:
	InputSetup.ensure_actions()
	var events_before: int = InputMap.action_get_events(InputSetup.FIRE).size()
	InputSetup.ensure_actions()               # idempotent
	assert_eq(InputMap.action_get_events(InputSetup.FIRE).size(), events_before)
	for a: StringName in [InputSetup.MOVE_LEFT, InputSetup.MOVE_RIGHT, InputSetup.MOVE_UP, InputSetup.MOVE_DOWN,
			InputSetup.FIRE, InputSetup.START_WAVE, InputSetup.DELETE_HOVERED, InputSetup.CANCEL,
			InputSetup.RESTART] + InputSetup.PICK:
		assert_true(InputMap.has_action(a) and not InputMap.action_get_events(a).is_empty(), String(a))


func _scripts(dir: String) -> PackedStringArray:
	var out: PackedStringArray = []
	if not DirAccess.dir_exists_absolute(dir):  # src/sim does not exist until WP2
		return out
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out
```

Comments are stripped before the purity check, so doc comments may mention `Input.` or `Node` and
similar. The `#` inside strings such as `"#%d"` is harmless to strip.

Verified behaviour of the sanity test (Godot 4.5.1, GUT 9.5.0):

- A clean run passes, and the tree stays clean. Each `--check-only` process takes about 0.3–0.6 s, so
  the planned ~80 scripts take roughly 25–50 s locally. GUT has no per-test timeout.
- An untyped test file fails this test with the parse errors, while the file's own tests still run.
- An untyped `src` script used by another test fails this test, and the other test still passes.
- A syntax error fails this test (and the post-run hook).
- Scripts that use their own class and enum inside static functions pass: `PlanIssue.make(p_code: Code, …)`
  assigning `i.code = p_code`, a constructor using a bare `new()`, `return self`, `Foo.takes(self)`.
- An impure sim script (`printerr(`, `var n: Node`) fails `test_core_and_sim_are_pure`; the same words in
  a comment do not.

### I.5 Helpers

**`test/helpers/fixtures.gd` (WP0).** Builds graphs through the public API only. Machine ids are
assigned in order from 3.

```gdscript
extends RefCounted
static func chain(kinds: Array[StringName]) -> FactoryGraph
	# Source -> kinds[0] -> ... -> Output (default belt removed); machine i at chain_cell(i)
static func chain_cell(i: int) -> Vector2i          # Vector2i(3 + 2 * (i % 4), 1 + 3 * (i / 4)): up to 16 machines
static func split(upper: Array[StringName], lower: Array[StringName]) -> FactoryGraph
	# Source -> Splitter (id 3, cell (3,5)); port 0 -> upper[i] at (5 + 2i, 2) -> Output;
	# port 1 -> lower[i] at (5 + 2i, 8) -> Output; an empty branch goes straight to the Output (max 3 per branch)
static func plan_of(specs: Array[BulletSpec]) -> ShotPlan   # ShotPlan.new() with these bullets (no compiler needed)
static func inventory_all(n: int) -> Inventory      # n of every placeable kind
```

**`test/helpers/bot.gd` (WP2).**

```gdscript
extends RefCounted
const KITE_DISTANCE: float = 260.0
const WALL_MARGIN: float = 140.0
const SIDESTEP: float = 0.6
const WALL_PUSH: float = 1.2
static func intent(world: ArenaWorld, fire: bool = true) -> PlayerIntent
	# aim at the nearest enemy's position; if it is closer than KITE_DISTANCE, move away + SIDESTEP
	# sideways; within WALL_MARGIN of a wall, add WALL_PUSH toward the centre; no enemies -> no fire, no move
static func play(world: ArenaWorld, max_seconds: float, fire: bool = true) -> void
	# step(SimTuning.STEP, intent(world, fire)) until not running or max_seconds of sim time.
	# ArenaWorld-only tests. Never call it on an ArenaController's world: the controller emits its
	# signals only from its own step(), so the run would stay in PLAY forever (drive it as in I.6 WP4).
```

If a balance test fails, tune only the four constants above. `Tuning` and `SimTuning` numbers are frozen;
a balance change goes to the orchestrator.

**`test/helpers/mouse.gd` (WP3).** These helpers were verified: a real palette-style drag delivered the
drop at the exact expected local position.

```gdscript
extends RefCounted
## Real mouse input through Input.parse_input_event (the same path as a player, including drag-and-drop).
## Call `await Mouse.prepare(self)` first. Keep positions at x < 950 (GUT's panel covers x 963..1595).

static func prepare(t: GutTest) -> void:
	t.get_tree().root.size = Vector2i(1600, 900)    # the headless root window is 64x64
	await t.wait_process_frames(2)


static func move(pos: Vector2, last: Vector2, mask: int) -> void:
	var e: InputEventMouseMotion = InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = pos - last                          # Godot starts a drag after 10 px of accumulated relative motion
	e.button_mask = mask
	Input.parse_input_event(e)


static func button(pos: Vector2, pressed: bool, index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.position = pos
	e.global_position = pos
	e.button_index = index
	e.pressed = pressed
	var mask: int = 0
	if pressed:
		mask = MOUSE_BUTTON_MASK_LEFT if index == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	e.button_mask = mask
	Input.parse_input_event(e)


static func drag(t: GutTest, from: Vector2, to: Vector2, steps: int = 10) -> void:
	move(from, from, 0)
	await t.wait_process_frames(1)
	button(from, true)
	await t.wait_process_frames(1)
	var last: Vector2 = from
	for i: int in steps:
		var p: Vector2 = from.lerp(to, float(i + 1) / float(steps))
		move(p, last, MOUSE_BUTTON_MASK_LEFT)
		last = p
		await t.wait_process_frames(1)
	button(to, false)
	await t.wait_process_frames(2)


static func click(t: GutTest, pos: Vector2, index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	move(pos, pos, 0)
	await t.wait_process_frames(1)
	button(pos, true, index)
	await t.wait_process_frames(1)
	button(pos, false, index)
	await t.wait_process_frames(1)
```

### I.6 Test list (file → tests; each WP owns the files it lists)

**WP0**

- `test/test_project_sanity.gd`: `test_every_script_compiles_with_project_warnings`,
  `test_core_and_sim_are_pure`, `test_input_actions_are_registered` (I.4).
- `test/unit/core/test_machine_catalog.gd`:
  - `test_nine_kinds_with_ports`: source 0/1, output 1/0, splitter 1/2, modifiers 1/1.
  - `test_caps`: 3, and pierce 4.
  - `test_source_and_output_fixed`: not removable or placeable; `placeable_kinds() == PALETTE_ORDER`.
  - `test_unknown_kind_is_null`.
- `test/unit/core/test_factory_graph.gd`:
  - `test_default_graph`: ids, cells, the one belt `"1:0>2:0"`, 1 path, no invariant problems.
  - `test_add_validation_order`: each code in C.3 order. Ids grow and are not reused after a remove.
  - `test_move_machine_belts_follow`: own cell is OK with no signal.
  - `test_remove_heals_simple_chain`.
  - `test_remove_does_not_heal_merge_or_fork`.
  - `test_remove_refuses_source_and_output`.
  - `test_connect_validation_order`: one crafted case per code, in C.3 order.
  - `test_connect_replaces_busy_output`.
  - `test_input_port_accepts_many_belts`.
  - `test_cycle_refused`.
  - `test_path_count_with_merges`: 2 chained splitters give 4.
  - `test_ninth_bullet_refused_and_graph_unchanged`.
  - `test_splice_keeps_path_count`: a spliced Splitter uses output 0 only.
  - `test_changed_once_per_success_never_on_refusal`.
  - `test_live_ids_excludes_dead_end_and_idle`.
  - `test_assign_from_and_to_dict`.
  - `test_wire_key_and_canonical_order`.
  - Every mutating test also asserts `debug_check_invariants().is_empty()`.
- `test/unit/core/test_bullet_spec.gd`:
  - `test_base_stats`.
  - `test_from_counts_formulas`: Ls 2, Lz 1, S 1 gives dmg 10.5875, spd 984.15, r 7.5.
  - `test_levels_clamped_to_caps`.
  - `test_effect_numbers`.
  - `test_describe_format`.
  - `test_primary_color_priority`.
- `test/unit/core/test_shot_plan.gd`:
  - `test_empty_plan_invalid_with_no_path`.
  - `test_summary_lines_format`: `"1 bullet/shot · 4 shots/s · 10.0 dmg/shot"`.
  - `test_issue_order_and_cap`: 2 issue lines, then `"… N more"`; a plan with 8 bullets and 5 non-ERROR
    issues gives exactly 12 lines.
  - `test_streams_on_returns_typed_array`.
- `test/unit/core/test_inventory.gd`:
  - `test_from_counts_and_count`: built from `Tuning.START_INVENTORY`, Fire and Speed Up count 1 and are
    ever-owned, and `take(MachineCatalog.FIRE)` succeeds (the const was copied); unplaceable kinds and
    counts of 0 are dropped.
  - `test_take_until_empty`.
  - `test_add_rejects_unplaceable_unknown_and_non_positive`.
  - `test_ever_owned_survives_taking_all`.
  - `test_kinds_ever_owned_in_palette_order`.
  - `test_changed_counts`.
- `test/unit/core/test_seeds.gd`:
  - `test_deterministic_and_non_negative`.
  - `test_each_input_changes_the_seed`.

**WP1**

- `test/unit/core/test_factory_compiler.gd`:
  - `test_default_plan`.
  - `test_chain_stacks_modifiers`.
  - `test_order_on_path_does_not_change_stats`.
  - `test_cap_marks_later_machines_capped`.
  - `test_real_split_penalty_and_fan`: bullet 0 is the upper branch at −5°.
  - `test_modifiers_before_split_apply_to_both`: the C.8 golden example.
  - `test_one_sided_splitter_is_free`.
  - `test_merge_gives_one_bullet_per_path`.
  - `test_fan_angles`: n = 0, 1, 2, 4 (clamped to a 10° step), 8 (a 50° span).
  - `test_dead_end_and_idle_statuses_and_issues`: includes Fire #3 → Ice #4 → Output with nothing into
    #3 (default belt kept): 1 bullet, and #3 and #4 are both IDLE, each with an IDLE issue.
  - `test_no_path_plan`.
  - `test_live_wire_keys_and_streams`: the belt after Fire carries fire_level 1.
  - `test_compile_is_deterministic`.
- `test/unit/core/test_reward_generator.gd`:
  - `test_three_distinct_offers_in_palette_order`.
  - `test_same_inputs_same_offers`.
  - `test_first_reward_includes_splitter_unless_owned`.
  - `test_amounts`.
  - `test_weights`.
  - `test_distribution_sanity`: over 2000 seeds at wave 3, Fire is offered more often than Pierce, and
    every kind appears.
- `test/unit/core/test_game_flow.gd`:
  - `test_happy_path_and_wave_counter`.
  - `test_illegal_transitions_return_false_without_signal`.
  - `test_restart_always_emits`.
- `test/unit/core/test_run_state.gd`:
  - `test_initial_state`.
  - `test_place_consumes_remove_refunds`.
  - `test_out_of_stock`.
  - `test_place_with_splice`.
  - `test_edits_locked_outside_build`: every `try_*` in PLAY, REWARD and GAME_OVER.
  - `test_plan_changed_after_each_edit`.
  - `test_start_wave_requires_path_and_reason_text`.
  - `test_start_wave_freezes_active_plan`.
  - `test_complete_wave_offers_then_reward`.
  - `test_choose_offer_adds_heals_capped_and_advances`.
  - `test_fail_wave_game_over`.
  - `test_restart_resets_same_instances`: after `restart()`, also take
    `var refs: Array[WeakRef] = [weakref(run), weakref(run.graph), weakref(run.plan)]`, set `run = null`,
    and assert every `get_ref()` is null (no reference cycle; a leak would otherwise surface only as an
    exit warning that CI does not check, J.3).
  - `test_wave_seed_differs_per_wave`.
- `test/unit/core/test_run_state_fuzz.gd`:
  - `test_random_edits_keep_invariants`: 3 seeds × 400 random `try_*` operations with random arguments,
    including invalid ones.
  - After every operation it asserts: no invariant problems; `owned(k)` is unchanged for every kind;
    `plan.bullets.size() == graph.count_live_paths() <= 8`.

**WP2**

- `test/unit/sim/test_status_effects.gd`:
  - `test_burn_total_is_exact`: level 2 for 5 s of 1/60 steps gives 36.0 ± 1e-4.
  - `test_burn_refresh_keeps_strongest`.
  - `test_chill_slow_and_expiry`.
  - `test_poison_stacks_and_cap`.
  - `test_poison_refresh_all_stacks`.
  - `test_large_delta_is_exact`.
- `test/unit/sim/test_collision_math.gd`:
  - `test_head_on_fraction`.
  - `test_miss`.
  - `test_start_inside_is_zero`.
  - `test_fast_bullet_does_not_tunnel`.
  - `test_zero_length_segment`.
- `test/unit/sim/test_wave_plan.gd`:
  - `test_counts_per_wave`: wave 1 is 6/0/0, wave 4 is 12/6/1, wave 6 is 16/10/2.
  - `test_order_is_seeded_shuffle_of_counts`.
  - `test_scaling_functions`.
- `test/unit/sim/test_arena_world.gd`:
  - `test_idle_world_does_not_step`.
  - `test_player_moves_and_is_clamped`.
  - `test_gun_fires_four_times_per_second`: 60 steps from `begin_wave` with fire held give SHOT on steps
    1, 16, 31 and 46.
  - `test_no_fire_without_valid_plan`.
  - `test_bullets_use_muzzle_and_fan`.
  - `test_hit_applies_damage_and_status`.
  - `test_pierce_hits_n_plus_one_in_order`.
  - `test_bullet_hits_each_enemy_once`.
  - `test_ice_slows_movement`.
  - `test_dot_kills_count`.
  - `test_contact_damage_and_invulnerability`.
  - `test_spawns_outside_and_away_from_player`.
  - `test_live_enemy_cap`.
  - `test_wave_clears_after_grace`.
  - `test_death_wins_over_clear`.
  - `test_determinism_same_seed_same_hash_different_seed_differs`. It also takes weakrefs of the world,
    its player and every live enemy and bullet after some seconds of firing, drops the world, and asserts
    every `get_ref()` is null.
- `test/unit/sim/test_arena_balance.gd`:
  - `test_default_gun_bot_clears_waves_1_and_2`: `Bot.play` within 90 s each, with HP > 0. On failure,
    tune only `bot.gd` (I.5).
  - `test_idle_player_dies_in_wave_1`: step with `PlayerIntent.make(Vector2.ZERO, Vector2.ZERO, false)`
    for at most 60 s of sim time (3600 steps), stop at PLAYER_DIED, and assert it was emitted.
- `test/unit/ui/test_arena_controller.gd`:
  - `test_start_wave_runs_and_updates_hud`.
  - `test_wave_cleared_emitted_once_with_hp_and_kills`.
  - `test_player_died_emitted`.
  - `test_go_idle_resets`.
  - `test_render_smoke`: every enemy type with every status, bullets and FX, drawn for 2 frames with no
    errors.

**WP3**

- `test/unit/ui/test_board_layout.gd`:
  - `test_anchors`.
  - `test_drop_cell_rounds_and_clamps`.
  - `test_hit_test_priority`: includes adjacent machines (`Fixtures.chain([FIRE, ICE])`, ids 3 at (3,1)
    and 4 at (5,1)): the shared anchor (200, 80) hits the output PortRef of #3, and `secondary()` on that
    hit gives DISCONNECT of `3:0>4:0`.
  - `test_belt_at_and_input_magnet`.
- `test/unit/ui/test_belt_router.gd`:
  - `test_straight`.
  - `test_z_route_snapped_and_clamped`.
  - `test_backward_route_goes_around`.
  - `test_splitter_lanes_differ`: `lane_offset` is exactly −4.0 and +4.0 for a Splitter's ports, and 0.0
    for a single output.
  - `test_distance_to`.
- `test/unit/ui/test_board_interaction.gd`:
  - `test_drag_machine_moves_it`.
  - `test_small_motion_is_not_a_drag`.
  - `test_invalid_move_refused_with_reason`.
  - `test_release_outside_removes`.
  - `test_release_outside_refused_for_source`.
  - `test_wire_drag_connects_with_magnet`.
  - `test_ninth_bullet_refusal_text`.
  - `test_wire_drag_without_target_is_silent`.
  - `test_secondary_actions`: belt and output-with-belt cut; machine, input port and beltless output port
    remove; a wheel press (`MOUSE_BUTTON_WHEEL_UP`) returns `none()` with no refusal over a machine,
    unlocked and locked; a right press during DRAG_WIRE and during DRAG_MACHINE cancels to IDLE with
    `none()`.
  - `test_drop_preview_place_splice_and_reasons`.
  - `test_locked_refuses_everything`.
- `test/unit/ui/test_factory_panel.gd`:
  - `test_render_smoke_all_statuses`.
  - `test_palette_states`.
  - `test_start_button_state_and_text`.
  - `test_message_expires`.
  - `test_hover_refreshes_after_graph_change`: hover machine #3 through `board.interaction.motion()`,
    remove it through the graph with no motion, then assert `interaction.hover` no longer names #3 and a
    redraw (`await wait_process_frames(2)`) raises no error. The same after `assign_from` (restart).
  - Real mouse:
    - `test_palette_drag_places_on_board`: drag slot 0 (Fire) to board cell (5,1), giving
      `place_requested(MachineCatalog.FIRE, Vector2i(5, 1), null)`.
    - `test_palette_drag_onto_belt_splices`.
    - `test_wire_drag_emits_connect`.
    - `test_machine_drag_off_floor_emits_remove`.
    - `test_right_click_belt_emits_disconnect`.

**WP4**

- `test/unit/ui/test_overlays.gd`:
  - `test_reward_overlay_shows_and_chooses`.
  - `test_reward_card_click`: a synthesized `_gui_input` at a local position.
  - `test_game_over_text_and_restart_signal`.
- `test/integration/test_main.gd`:
  - `test_boot_layout_and_initial_state`.
  - `test_no_path_disables_start_with_reason`.
  - `test_space_starts_wave_and_locks_editor`: a board press is refused and the graph is unchanged.
  - `test_full_loop_build_play_reward_build`:
    - place via the board signal;
    - start;
    - drive the controller, never `Bot.play`: call `main.arena.set_physics_process(false)`, then loop
      `main.arena.intent_override = Bot.intent(main.arena.world)` and `main.arena.step(SimTuning.STEP)`
      while `main.run.flow.state == GameFlow.State.PLAY`, for at most 5400 steps (90 s);
    - check REWARD with 3 offers including a Splitter;
    - key `1` picks;
    - check BUILD wave 2, the inventory updated and HP healed.
  - `test_death_then_restart`: the same loop with `intent_override` fixed to
    `PlayerIntent.make(Vector2.ZERO, Vector2.ZERO, false)`, at most 3600 steps, until GAME_OVER; the
    overlay is visible; `R` restarts into BUILD wave 1 with the default factory.

---

## J. CI

### J.1 Existing workflow

The existing workflow is `.github/workflows/ci.yml` on master. Its job id is `ci`. Keep the job id
`ci`, do not add a `name:` override, and keep the "Validate JSON" step. Its steps run in this order:

1. "Validate JSON"
2. "Install Godot" (`GODOT_VERSION: 4.5.1`, downloaded to `/usr/local/bin/godot`; the zip is deleted)
3. "Import project": `godot --headless --import`
4. "Run GUT tests": `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`

Steps 2–3 run only when `project.godot` exists; step 4 only when `addons/gut/gut_cmdln.gd` exists. Do
not add another workflow file. `pages.yml` (the web export to GitHub Pages on push to master) belongs to
another workstream; do not touch it.

### J.2 The one appended step (WP0)

Append this step after "Run GUT tests", at the same indentation. Change nothing else.

```yaml
      - name: Check generated files and boot the game
        if: hashFiles('project.godot') != ''
        run: |
          set -o pipefail
          if [ -n "$(git status --porcelain)" ]; then
            git status --porcelain
            echo "::error::Import or tests changed the tree. Commit the generated .uid files."
            exit 1
          fi
          godot --headless --quit-after 300 2>&1 | tee "$RUNNER_TEMP/boot.log"
          if grep -nE 'SCRIPT ERROR|Parse Error|^ERROR:|^WARNING:' "$RUNNER_TEMP/boot.log"; then
            echo "::error::The game printed errors or warnings while booting."
            exit 1
          fi
```

Notes on this step:

- GitHub's default `run` shell is `bash -e` **without** pipefail, so the step sets it.
- The boot log goes to `$RUNNER_TEMP`, so the step never dirties the tree it checks.
- The stub main boots in about 2.3 s with a clean log (verified).

### J.3 What catches what

| Failure | Caught by |
|---|---|
| A failing assert, or an engine error or warning inside a test body | GUT (exit 1) |
| Untyped code, or a parse error in any `src` or `test` script | `test_every_script_compiles_with_project_warnings` (one fresh `--check-only` process per file) |
| A test file GUT silently skipped | the post-run hook (file check) |
| Errors in `before_each`/`after_each`/deferred calls/frees | the post-run hook (stray errors) |
| core/sim importing engine state | `test_core_and_sim_are_pure` |
| Uncommitted `.uid` files, or anything import or tests write into the repo | the appended step (clean tree) |
| A broken Main wiring, a missing class, or a leak at exit of objects created while booting Main idle in BUILD (`WARNING: ObjectDB instances leaked`, `ERROR: N resources still in use`) | the appended step (boot smoke) |
| A reference cycle in `RunState` (restart path) or in `ArenaWorld` entities (play path) | the weakref asserts in `test_restart_resets_same_instances` and `test_determinism_…` (I.6). Leaks on other paths print only after GUT exits 0 and are **not** caught. |
| The web export breaking | `pages.yml` on master only. WP4 checks the Pages run after its merge (K.5). |

### J.4 PR flow (CLAUDE.md)

1. Every WP is its own branch from the latest `origin/master`.
2. Before pushing, run `godot --headless --import`, the GUT command and the boot smoke locally (each
   under `timeout`).
3. Open a PR into `master` with auto-merge enabled. It merges when `ci` passes.
4. **Before relying on auto-merge, the orchestrator must confirm that `ci` is a required status check
   on `master`.** The reviews disagreed on whether a ruleset exists. Without one, auto-merge merges
   immediately.

---

## K. Work packages

```
WP0 (infra + kernel) ──► WP1 (rules) ──┐
                     ├─► WP2 (arena) ──┼──► WP4 (overlays, Main, integration)
                     └─► WP3 (editor) ─┘
```

**Rules that apply to every WP:**

- Edit only the files you own (A.2). If you need a change to another WP's file, make it in a separate
  small PR first.
- New scripts carry their committed `.uid` files.
- Every non-trivial function has a test (I.6).
- The API signatures in B–G are frozen. Private helpers are free.
- A WP is done when:
  - its tests and all earlier tests pass locally;
  - CI `ci` is green;
  - the PR has merged.

### K.1 WP0: infra and kernel (first, alone)

- **Branch:** rebase onto `origin/master` (0d8baf0). That commit brings `export_presets.cfg` and
  `pages.yml`. The old base (830a8e8) lacks both.
- **Files:** `docs/DESIGN.md` (this file), `project.godot`, `.gitignore`, `.gutconfig.json`,
  `addons/gut/**`, the appended step in `.github/workflows/ci.yml`, `src/main/main.tscn`, the stub
  `src/main/main.gd`, `src/main/input_setup.gd`, `src/ui/theme/ui_colors.gd`, and in `src/core/`: `tuning`,
  `machine_def`, `machine_catalog`, `machine_instance`, `wire`, `graph_error`, `factory_graph`,
  `bullet_spec`, `plan_issue`, `shot_plan`, `inventory` and `seeds`. Plus `test/gut_post_run.gd`,
  `test/test_project_sanity.gd`, `test/helpers/fixtures.gd`, and the WP0 tests in I.6.
- **Provides:** everything in B.1–B.7, B.9 and B.10, the test infrastructure, and CI.
- **Done also means:**
  - Locally, breaking a test file (syntax error) makes the GUT command exit 1. Revert that test change.
  - The appended CI step passes.

### K.2 WP1: rules (after WP0; parallel with WP2 and WP3)

- **Files:** `src/core/factory_compiler.gd`, `reward_offer.gd`, `reward_generator.gd`, `game_flow.gd`,
  `run_state.gd`, and the WP1 tests in I.6.
- **Consumes:** the WP0 kernel.
- **Provides:** B.8, used by WP4 (Main) and by WP4's overlays (`RewardOffer`).
- **Key behaviours:** C.6–C.8, the RunState rules in B.8, and H.

### K.3 WP2: arena (after WP0; parallel)

- **Files:** all of `src/sim/*`, `src/ui/arena/arena_view.gd`, `hud.gd`, `arena_controller.gd`,
  `test/helpers/bot.gd`, and the WP2 tests in I.6.
- **Consumes:** `Tuning`, `BulletSpec`, `ShotPlan`, `Seeds`, `UiColors`, `InputSetup`, and
  `MachineCatalog` colours. In tests, it builds `ShotPlan`s with `Fixtures.plan_of`, not the compiler.
- **Provides:** F.5–F.7 (`ArenaController` with its two signals, `start_wave`, `go_idle`, `step` and
  `intent_override`).

### K.4 WP3: editor (after WP0; parallel)

- **Files:** all of `src/ui/editor/*`, `src/ui/theme/factory_theme.gd`, `test/helpers/mouse.gd`, and
  the WP3 tests in I.6.
- **Consumes:** the WP0 kernel. In tests, it builds graphs with `Fixtures` and plans by hand (setting
  `statuses`, `live_wire_keys` and `wire_streams` directly).
- **Provides:** E.3–E.9 (the `FactoryPanel` API, the `FactoryBoard` request signals, `FactoryTheme`),
  and `MachinePainter.draw_icon` for WP4.

### K.5 WP4: overlays, Main, integration (last)

- **Files:** `src/ui/overlays/reward_overlay.gd`, `game_over_overlay.gd`, `src/main/main.gd` (replacing
  the stub), `README.md`, `test/unit/ui/test_overlays.gd`, and `test/integration/test_main.gd`.
- **Consumes:** everything.
- **README:** what the game is, the controls, how to run it and the tests (the commands in J.1), and a
  link to this file.
- **Done also means:** the `pages.yml` run on the merge commit succeeded with **both** jobs `success`
  (not `skipped`). Check it with
  `gh run list -R frostblooded/FactoryGun --workflow pages.yml --commit <full merge sha> --json databaseId,conclusion`
  and `gh run view <id> -R frostblooded/FactoryGun --json jobs --jq '.jobs[] | {name, conclusion}'`
  (verified through the agent proxy, which blocks `*.github.io` itself). The build job already runs
  `test -f build/web/index.wasm`. A failure that shows only in a browser and comes from
  `export_presets.cfg` (it sets `variant/thread_support=true`, so the page relies on the PWA service
  worker for cross-origin isolation headers) goes to the orchestrator. WP4 does not edit that file.

### K.6 Interface contracts at a glance

| Producer → consumer | Contract |
|---|---|
| WP0 → all | `FactoryGraph` (B.4), `BulletSpec.from_counts` (B.5), `ShotPlan` fields and `summary_lines` (B.6), `Inventory` (B.7), `MachineCatalog` (B.2), `UiColors`, `InputSetup`, `Fixtures` |
| WP1 → WP4 | `RunState` methods, signals and fields (B.8); `GameFlow.State`; `RewardOffer` |
| WP2 → WP4 | `ArenaController.start_wave(wave, plan, seed, hp)`, `go_idle(hp, wave)`, `step(delta)`, `intent_override`, `set_physics_process(false)` in tests; signals `wave_cleared(hp_left, kills)`, `player_died(kills)`; `world` |
| WP3 → WP4 | `FactoryPanel.bind/set_plan/set_locked/set_start_state/show_message`, `start_wave_requested`; `panel.board.*_requested` (E.5); `board.delete_hovered()`, `cancel_interaction()`; `FactoryTheme.build()`; `MachinePainter.draw_icon` (typed signature in E.2.1) |

---

## L. Risks and pitfalls

### L.1 Verified facts (Godot 4.5.1 binary, class XML, GUT 9.5.0 source)

| # | Fact | How it matters here |
|---|---|---|
| 1 | GUT loads test scripts with warnings disabled (`warnings_when_loading_test_scripts = {enable = false}`). A `src` script first loaded during test collection also escapes `untyped_declaration`. | The sweep compiles every script in a fresh `--check-only` process (I.4, #27). |
| 1b | Recompiling inside the GUT process is unsafe or wrong. `ResourceLoader.load(path, "", CACHE_MODE_IGNORE)` recompiles the **cached** GDScript in place: the running test then dies ("Internal script error! Opcode: 31"), and a failed reload **hangs the run**. A `GDScript.new()` copy must drop its `class_name` line ("hides a global script class"), and the copy then rejects valid code that uses its own class with its own enum: `PlanIssue.make(p_code: Code, …)` doing `i.code = p_code` fails with `Value of type "<id>.gd.Code" cannot be assigned to a variable of type "PlanIssue.Code"`. | Never recompile project scripts in process. Use a fresh process (#27). |
| 2 | A test file with a syntax error is skipped ("Ignoring script … does not extend GutTest") and the run can still exit 0. | The post-run hook compares files on disk with the collected scripts (I.3). |
| 3 | `push_warning` (any engine `WARNING:`) inside a test body fails that test, under the default `failure_error_types = ["engine","gut","push_error"]`. | No warnings anywhere in `src`. |
| 4 | Errors in `before_each`/`after_each`/`after_all` do not fail the test; they are tracked under `GutUtils.NO_TEST` (`"NONE"`). | The post-run hook. |
| 5 | A post-run hook exit code overrides GUT's exit code. A hook that does not parse makes GUT hang forever. | Only `set_exit_code(1)`; keep the hook tiny and verified. |
| 6 | Leaks print `WARNING: ObjectDB instances leaked at exit` after GUT finishes, and GUT still exits 0. A leak can also print `ERROR: N resources still in use at exit`. | The boot smoke greps for both, for boot-time objects only. Weakref asserts cover the restart and play paths (I.6). No lambdas on a RefCounted object's own signals (A.4). |
| 7 | The headless root window is 64×64. After setting `root.size = Vector2i(1600, 900)`, GUT's panel covers x 963–1595, y 5–895. | `Mouse.prepare`; real-mouse tests stay at x < 950. |
| 8 | `Input.parse_input_event` events are flushed on the next frame and update the headless mouse position. `Viewport.push_input` alone leaves `get_mouse_position()` at (0,0). | Await 1 frame per event; use `parse_input_event`. |
| 9 | Without `--fixed-fps`, physics frames run in real time (about 60 per second); process frames are fast. | Step sims directly in tests. |
| 10 | `Viewport.gui_is_dragging()` is true inside a real `_get_drag_data`. `set_drag_preview` outside a drag errors, and setting a preview while returning `null` is an error. `get_viewport()` returns `null` for a node outside the tree. | The `is_inside_tree()` guards in `PaletteSlot._get_drag_data` (E.6) and `FactoryBoard.set_locked` (E.5). |
| 11 | A drag starts after more than 10 px of accumulated `relative` motion with the button held. | The mouse helper sets `relative` and moves in 10 steps. |
| 12 | Static typing in 4.5.1, with `untyped_declaration=2`: an unannotated `for` over an untyped Array/Dictionary is an error, while typed or packed arrays and `range` infer the type; `var x := variant` is a hard error; lambdas need typed params and returns; an untyped `const` is allowed. | Rule A.4.1. |
| 13 | `Array.filter()` returns the same typed array; `Array.map()` returns an untyped `Array`; a typed `Dictionary`'s `keys()`/`values()` are typed; `Array[Vector2].sort()` is lexicographic (x, then y). | `assign()` after `map()`; hit sorting in D.4 relies on the sort order. |
| 14 | Warn-level GDScript warnings (for example an unused variable) are not printed at runtime load. Only the error-level ones (`untyped_declaration`, `inference_on_variant`) matter in CI. | No other warning settings are needed. |
| 15 | GraphEdit, GraphNode and GraphElement are marked **experimental** in the 4.5 class reference. | The custom `FactoryBoard`. |
| 16 | The default font is Open Sans SemiBold. It has `× · ° — − …`; it lacks `▶ ► ═ → ✕`. At size 12 the font is 17 px high, and a Label adds the theme constant `line_spacing = 3` between lines: 12 lines need 237 px, or 204 px with `line_spacing` 0. `clip_text` clips only horizontally; a Label without it grows to its text width (the Splitter hover text is 686 px). | The UI text rule; readout sizing (E.7); status line clipping (E.8). |
| 17 | `Geometry2D.segment_intersects_circle` returns the exit fraction when the segment starts inside the circle, and −1 when the segment stays inside. | `CollisionMath.first_contact` instead (D.4). |
| 18 | `String.hash()` is djb2-like, so adjacent inputs give adjacent seeds. `sha256_text().substr(0, 15).hex_to_int()` gives well-mixed, non-negative seeds. | `Seeds.derive`. |
| 19 | `godot --headless --import` creates a `.gd.uid` file for every new script and does not modify `project.godot`, a uid-less `main.tscn`, or the vendored GUT files. | Commit the `.uid` files; the clean-tree check. |
| 20 | `_draw()` runs headless, so render-smoke tests and the boot smoke exercise drawing code. | Render-smoke tests in WP2, WP3 and WP4. |
| 21 | Static-var caches of RefCounted objects, and signal connections to methods, do not leak at exit. | `MachineCatalog` and `EnemyType` caches; RunState listens to `graph.changed`. |
| 22 | GitHub's default `run` shell is `bash -e` without `pipefail`. | `set -o pipefail` in J.2. |
| 23 | Two calls print an engine `WARNING:`: setting `size` on a Control with unequal opposite anchors ("Nodes with non-equal opposite anchors will have their size overridden after _ready()"), even off-tree; and `draw_rect(r, c, true, width)` ("The draw_rect() "width" argument has no effect when "filled" is "true"."). A child given `PRESET_FULL_RECT` off-tree fills its parent once the parent is sized. | Rule A.4.5. |
| 24 | `_can_drop_data(at: Vector2, data: Dictionary)` is a parse error ("The function signature doesn't match the parent"); `data: Variant` compiles. | The exact overrides in E.5. |
| 25 | A `const` Dictionary is read-only: writing through a stored reference fails ("Dictionary is in read-only state"). `duplicate()`, `assign()` and a key-by-key copy all give a writable typed dictionary. | `Inventory.from_counts` copies (B.7). |
| 26 | GUT: `-gdir` plus `-gtest` still runs every collected file; `-gtest` alone makes the post-run hook fail on every other file; `-gconfig=` skips `.gutconfig.json` and so the hook. | The one-file command (I.1). |
| 27 | `godot --headless --path <project> --check-only -s res://x.gd` compiles the real script with the project's warnings-as-errors: exit 1 for untyped or broken code, exit 0 otherwise, including GutTest scripts, the post-run hook, `main.gd` and classes that use their own class and enums. About 0.3–0.6 s per call. | The compile sweep (I.4). |
| 28 | During a GUI drag, Escape (`ui_cancel`) makes Godot cancel the drag and consume the key; without a drag, Escape reaches `_unhandled_input`. Wheel steps arrive as `InputEventMouseButton` presses (`MOUSE_BUTTON_WHEEL_UP`/`DOWN`). | E.4: no code for Escape in a palette drag; `press()` ignores the wheel. |

### L.2 Project risks

| Risk | Mitigation |
|---|---|
| Branch protection is unknown, so auto-merge might merge before CI finishes. | The orchestrator confirms `ci` is a required check before enabling auto-merge (J.4). |
| The GUT run hangs: a broken hook, or a bare `await`. | Rules I.2.7 and I.3. Run locally under `timeout 300`. The existing job has no `timeout-minutes` (another workstream's file). |
| Web export problems. The export is only checked by `pages.yml` after merge. | Use only web-safe APIs in `src/`: no `Thread`, `OS.execute`, file writes, pointer lock or window management; no audio; the built-in font only. (`test/` uses `OS.execute`, but `export_presets.cfg` excludes `test/*`.) Right-click works (the web shell suppresses the context menu). Keys avoid browser shortcuts. WP4 checks the Pages run (K.5). |
| Parallel WPs drift from the contracts. | Signatures in B–G are frozen. WP2 and WP3 tests use `Fixtures` instead of WP1 code. WP4 integration tests catch any mismatch. |
| A `.uid` file is missing from a PR. | The clean-tree step fails with an explicit message. |
| Readout overflow in extreme builds. | The worst-case row fits at 415 px. At most 2 issue lines, then "… N more", so at most 12 lines: 204 px with `line_spacing` 0, the label's exact height (E.7). |
| GUT's GUI has keyboard focus during integration tests. | Keys are sent via `main._unhandled_input(event)` (I.2.9). |
| Space or Enter presses a focused button. | `FOCUS_NONE` on every button (A.4.8). |

### L.3 Deliberately cut from v1 (do not build)

- Undo and redo, and reset layout.
- A boss enemy, knockback, spawn telegraphs, damage numbers, the "brittle" ice bonus, and screen shake.
- Auto-fire, a spatial grid, and an in-game autopilot or `--autoplay`.
- Save/load, JSON graph codecs, and settings.
- Shot pulses on belts, a fan preview in the arena, and picking up belt ends or reverse wiring.
- Audio, `.gitattributes`, and a desktop window-size override.
- Pause, a victory condition (waves are endless), and selection or multi-select in the editor.
