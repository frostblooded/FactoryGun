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
| Remove a machine (refund) | Drag it off the floor, right-click it, or hover it and press Delete or X. |
| Connect a belt | Drag from an output port (right edge) to an input port (left edge). |
| Cut a belt | Right-click it, or hover it and press Delete or X. |
| Cancel a gesture | Escape, or right-click while dragging. |
| Start the wave | Space, Enter, or the START WAVE button. |
| Move | W A S D or the arrow keys. |
| Aim and fire | Mouse to aim, hold the left button to fire. |
| Pick a reward | 1, 2 or 3, or click a card. |
| Restart after game over | R, or the RESTART button. |

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

To run one file, skip the post-run hook with an empty `-gconfig=`:

```sh
godot --headless -s addons/gut/gut_cmdln.gd -gconfig= -gtest=res://test/integration/test_main.gd -gexit
```

## Design

The full design (rules, numbers, architecture and test plan) is in [docs/DESIGN.md](docs/DESIGN.md).
