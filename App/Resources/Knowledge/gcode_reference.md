# G-code quick reference

## G0 — Rapid positioning

Moves at the machine's maximum travel speed in a straight line (or
per-axis independently, depending on the controller) with the spindle
assumed to not be cutting. Never used for a cutting move — a G0 that
intersects the stock at cutting depth is exactly the "rapid into stock"
danger case this app's G-code analyzer flags.

## G1 — Linear interpolation (cutting move)

Moves in a straight line at the feed rate set by the `F` word (or the last
`F` word seen, since feed rate is modal — it carries over from the
previous line if not repeated). This is the standard cutting move for
straight lines, slots, and profiles.

## G2 / G3 — Circular interpolation (clockwise / counter-clockwise)

Cuts an arc at the feed rate, defined either by an `I`/`J` center offset
(relative to the arc's start point) or an `R` radius value depending on the
controller/post-processor. G2 is clockwise, G3 is counter-clockwise, as
viewed looking down the tool axis from above (standard right-hand
convention on the XY plane).

## G17 / G18 / G19 — Working plane selection

Selects which two axes an arc (G2/G3) or other plane-dependent command
operates in: G17 is the XY plane (the default, and by far the most common
for 2.5D routing/milling), G18 is XZ, G19 is YZ.

## G20 / G21 — Units

G20 selects inches, G21 selects millimeters, for all subsequent distance
and feed rate values in the program. Mixing G20/G21 assumptions between the
CAM software and the machine controller is a classic source of a program
running 25.4x too large or too small.

## G28 — Return to reference/home position

Sends the machine to its stored reference (home) position, typically used
at the start or end of a program. Some controllers require the machine to
have been homed via limit switches earlier in the session for G28 to be
meaningful.

## G54–G59 — Work coordinate offsets

Selects one of several stored work offsets, letting the operator define
"part zero" (X0 Y0, and often a Z0 at the stock top) without changing the
machine's own absolute (0,0,0). Most hobby G-code is written relative to a
G54 offset centered on or at a corner of the part, not the machine's own
origin — this is why the G-code analyzer's machine-limits check needs the
actual work offset to be meaningful and is opt-in rather than checking
against machine (0,0,0) directly by default.

## G90 / G91 — Absolute / incremental positioning

G90 means every coordinate word (X/Y/Z) is an absolute position relative to
the current origin/work offset. G91 means every coordinate word is a
delta relative to the current position. Most CAM-generated G-code is G90;
G91 shows up more in hand-written or repetitive-pattern programs.

## M3 / M4 / M5 — Spindle control

M3 starts the spindle clockwise, M4 starts it counter-clockwise (rare on
a router; more common on a lathe), M5 stops the spindle. A cutting move
(G1/G2/G3) appearing before any M3/M4 in the program is exactly the
"missing spindle start" danger case the G-code analyzer flags — it usually
means a real program had its spindle-start line accidentally deleted or
never inserted.

## M6 — Tool change

Signals a tool change, pausing the program (on most hobby setups this
means the operator manually swaps the bit) — the program typically resumes
after the operator confirms the new tool is loaded and, ideally, re-zeroed
in Z.

## M8 / M9 — Coolant on / off

M8 turns on coolant/mist (if the machine has it fitted), M9 turns it off.
Most hobby CNC routers don't have automatic coolant and either ignore these
codes or use them to trigger an air-blast/dust-collection relay instead.
