# FactoryGun

A top-down shooter where you build your gun as a small factory.

The screen has two halves:

- **Left: the factory.** A Factorio-style floor. Drag machines onto it and connect them with belts. Every
  route from the Basic Bullet to the Output is one bullet of each shot (8 at most), and the machines on
  that route change it: Fire burns, Ice slows, Poison stacks, Speed Up and Size Up boost the bullet,
  Pierce passes through enemies, and a Splitter forks the stream into a fan of bullets.
- **Right: the arena.** Endless waves of enemies. Your gun fires whatever the factory builds, and every
  effect shows on the enemies it hits.

Each round: build, press Start Wave, survive. Clear a wave to pick 1 of 3 new machines and heal 25 HP,
then build again. If you die, the run is over: restart and try a different factory.

## Controls

| Action | Input |
|---|---|
| Place a machine | Drag it from the palette onto the floor. Drop it on a belt to splice it in. |
| Move a machine | Drag it to another spot. Its belts follow. |
| Remove a machine (refund) | Drag it onto the REMOVE bin (or anywhere off the floor), right-click it, or hover it and press Delete or X. |
| Connect a belt | Drag from an output port (right edge) to an input port (left edge). Dragging from an output port that already has a belt re-routes it. |
| Cut a belt | Tap or click it (or its output port), then press CUT. Or right-click it, or hover it and press Delete or X. |
| Cancel a gesture | Escape, or right-click while dragging. |
| Start the wave | Space, Enter, or the START WAVE button. |
| Move | W A S D or the arrow keys. On a touch screen, put a finger anywhere in the arena and drag: a stick appears under it. |
| Aim and fire | Automatic: the gun aims at the nearest enemy and fires on its own. |
| Pick a reward | 1, 2 or 3, or click or tap a card. |
| Restart after game over | R, or the RESTART button. |

On a phone, play in landscape: holding it upright pauses the game behind a "rotate your phone" notice.

The factory is locked while a wave is running. The readout under the palette shows what one trigger
pull fires.

## Running

The game needs [Godot 4.5.1](https://github.com/godotengine/godot/releases/tag/4.5.1-stable). Open
`project.godot` in the editor and press Play, or run it from this folder:

```sh
godot --headless --import   # first time only: imports the project and caches its classes
godot
```

## Tests

The tests use [GUT 9.5.0](https://github.com/bitwes/Gut), vendored in `addons/gut`. These are the
commands CI runs:

```sh
godot --headless --import
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit
```

The run should end with every test passing and 1 pending (see below). CI then checks that import and the
tests left the tree clean (commit any new `.gd.uid` files), and boots the game headless for 300 frames with
no errors or warnings:

```sh
git status --porcelain              # must print nothing
godot --headless --quit-after 300   # must print no ERROR, WARNING, SCRIPT ERROR or Parse Error lines
```

To run one file, skip the post-run hook with an empty `-gconfig=`:

```sh
godot --headless -s addons/gut/gut_cmdln.gd -gconfig= -gtest=res://test/integration/test_main.gd -gexit
```

The pending test, `test_default_board_stays_in_its_draw_call_budget`, needs a renderer: a headless run
counts no draw calls. Run it alone with one, for example under Xvfb:

```sh
xvfb-run -a -s '-screen 0 1600x900x24' godot --rendering-driver opengl3 -s addons/gut/gut_cmdln.gd \
  -gconfig= -gtest=res://test/integration/test_main.gd -gunit_test_name=draw_call_budget -gexit
```

Run only that test with a renderer. The real-mouse tests hold only in headless runs: under X11, Godot
drops a drag where the real pointer is.

## Design

The full design (rules, numbers, architecture and test plan) is in [docs/DESIGN.md](docs/DESIGN.md).
