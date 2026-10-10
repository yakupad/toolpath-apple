# Troubleshooting common problems

## Chatter (vibration marks / rough surface with a repeating pattern)

Chatter is self-exciting vibration between the tool and the workpiece,
visible as a regular rippled pattern on the cut surface and often audible
as a harsh buzzing/screeching sound rather than a clean cutting sound.
Common causes on a hobby machine: too much stickout (tool extending too
far from the collet), a dull tool, insufficient workholding rigidity, or a
depth of cut that's too aggressive for the tool diameter and machine
rigidity combined. Fixes, roughly in order of what to try first: reduce
depth of cut, shorten how far the tool sticks out of the collet, tighten
down the workpiece more (add extra clamps/tabs), and check the tool isn't
dull or chipped. Chatter is a strong sign to reduce depth of cut before
increasing feed rate — it almost never means "go slower", since going
slower without addressing the underlying rigidity issue usually makes
chatter worse (more time per revolution for the vibration to build).

## Tool breakage

Sudden snapping usually traces to one of: a depth of cut that's too
aggressive for the tool diameter (a common cause with small-diameter
tools, e.g. under 3mm, which have very little cross-section to resist
side load), a feed rate that's too slow relative to spindle speed (the
tool rubs instead of cutting cleanly, builds heat, and the edge fails), a
plunge move straight down instead of a ramped/helical entry (most end
mills aren't designed to plunge like a drill), or the tool hitting a clamp,
screw, or the spoilboard due to a Z-height/work-offset mistake. Reducing
the feed rate to "be safer" without checking these is a common mistake —
feed that's too slow relative to RPM is itself a common breakage cause,
not just a comfort setting.

## Burning or melting (dark/discolored wood, melted/re-solidified plastic)

In wood, dark scorch marks mean the tool is rubbing rather than cutting
cleanly — usually a dull tool, a feed rate too slow for the RPM, or a
finishing pass with almost no material left to actually cut. In plastics,
melting (stringy chips, a shiny/glassy melted surface) means heat is
building up faster than it's being carried away by the chips — increase
feed rate and/or reduce spindle speed, and make sure a plastic-appropriate
single-flute bit is being used for good chip clearance.

## Poor surface finish (fuzzy edges, visible tool marks, inconsistent texture)

Fuzzy/torn edges in wood are usually a tear-out issue tied to grain
direction and bit choice (see the up-cut/down-cut/compression note in
tooling) rather than a feeds/speeds problem. Visible stepping/scalloping on
a contoured surface usually means the stepover between passes was too
large for the tool's radius. A generally rough, inconsistent finish across
an otherwise correct setup often points to a dull or damaged cutting edge
— inspect the tool under good light or a loupe before changing any numbers.

## Workholding failure (part shifts or lifts mid-job)

If a part shifts, most of the applied cutting force at that moment was
lateral (sideways) rather than being absorbed by clamping — add more
hold-down points, especially near the end of a cutout where the part
becomes free to move once fully separated (tabs left uncut until a final
pass are the standard fix for that specific case). Double-sided tape and
vacuum holddown both lose grip if there's dust/debris between the tape or
the workpiece and the spoilboard — clean both surfaces before applying.
