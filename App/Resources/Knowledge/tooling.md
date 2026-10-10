# Tooling: geometry and coatings

## Flute count tradeoffs

Fewer flutes (1-2) leave more open space (gullet) around the cutting edge
for chip evacuation, which matters most in materials that produce large or
sticky chips — aluminum, plastics, wood. More flutes (3-4+) put more
cutting edges in contact per revolution, allowing a faster feed rate at the
same chip load, but at the cost of smaller gullets that clog more easily on
a hobby machine's weaker chip evacuation (no flood coolant, often no
vacuum). As a rule of thumb for a hobby router/mill: 1-2 flutes for wood
and plastics, 2 flutes for aluminum, and it's fine to go to 3-4 flutes for
steel/stainless finishing passes where chip volume per revolution is
naturally lower.

## Up-cut, down-cut, and compression bits for wood/sheet goods

An up-cut bit pulls chips upward and out of the cut — best chip clearance,
but it also pulls the top surface fibers upward, causing tear-out on the
top face. A down-cut bit pushes chips downward, giving a clean top surface
but packing chips into the cut (worse for deep slots) and risking
tear-out/splintering on the bottom face where it exits. A compression bit
combines both in one tool (down-cut flutes near the tip, up-cut flutes
above) specifically to get a clean top AND bottom surface on sheet goods
like plywood and veneered MDF — at the cost of needing the correct
transition depth to actually be in the workpiece, so compression bits are
poorly suited to very thin material where the transition point may not
land inside the stock.

## Ball-nose vs. flat end mill vs. V-bit

A flat (square) end mill cuts a flat-bottomed pocket/slot and is the
default choice for 2.5D work — pockets, slots, profiles at a constant
depth. A ball-nose end mill has a rounded tip and is used for 3D contoured
surfaces (reliefs, curved surfaces) where a flat bottom would leave visible
stepping; it's a poor choice for flat-bottomed pockets since the rounded
tip leaves a scalloped/rounded floor unless heavily overlapped. A V-bit
(pointed, various included angles like 60°/90°/120°) is used for V-carving
(engraving letters/designs with a tapered profile) and for chamfering
edges — not a general-purpose cutting tool.

## Tool coatings

Bare (uncoated) carbide is fine for wood, plastics, and aluminum at hobby
feeds — coatings mostly earn their cost in harder, more abrasive, or
higher-heat cutting. TiN (titanium nitride, gold-colored) is a general
all-purpose coating that modestly extends tool life in steel and reduces
built-up-edge risk. AlTiN/TiAlN (aluminum titanium nitride, often
dark grey/purple) handles higher heat than TiN and is the better choice
for stainless steel and harder alloys, since it resists the heat buildup
that drives work hardening. Coatings add cost and are rarely worth it for
softwoods, MDF, or acrylic, where an uncoated bit already lasts a long
time and the coating adds nothing except cost.
