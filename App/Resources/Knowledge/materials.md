# Material machinability notes

Qualitative notes to go with the numeric feeds/speeds catalog
(`CuttingMaterial.catalog`). These cover coolant/lubrication needs, chip
evacuation, and common pitfalls per material — the "why" behind the
calculator's numbers, not a replacement for them.

## Aluminum 6061

Machines very well on hobby routers and is one of the most forgiving metals
to cut. Use a mist coolant or cutting fluid (WD-40 or a dedicated aluminum
cutting fluid works in a pinch) to prevent chips from welding back onto the
flutes, which is the most common cause of a ruined finish or a snapped
tool in aluminum. Clear chips aggressively — a shallow full-depth slot with
no chip evacuation will re-cut chips and generate heat fast. 2-flute
uncoated or ZrN-coated carbide end mills are the standard choice; 3-4 flute
tools are more prone to clogging in a full slot on a low-power hobby
spindle.

## Brass (free-machining)

Among the easiest materials to cut — free-machining brass alloys are
formulated to produce short, brittle chips that clear themselves. Usually
run dry (no coolant needed) since brass doesn't generate much heat at
hobby feeds. Watch for "grabbing" with sharp single-flute or 2-flute bits;
a slightly duller edge or reduced rake angle actually cuts brass more
predictably than a very sharp edge, which can dig in.

## Mild Steel (1018)

Requires noticeably more rigidity and power than most hobby routers
comfortably provide — expect to run conservative depths of cut and accept
a slower job. Cutting fluid or at minimum a spray mist is strongly
recommended; dry cutting in steel accelerates tool wear dramatically. Use
sharp carbide (not HSS if avoidable) and never run a dull tool — steel does
not forgive a dull edge the way wood or plastic does, and a dull tool will
overheat and dull further in a runaway cycle.

## Stainless Steel (303/304)

Work-hardens quickly, meaning if the tool rubs instead of cuts (too light a
chip load, or a pass that stalls), the surface becomes harder and even more
difficult to cut on the next pass. Keep a consistent, adequate chip load
and avoid dwelling in one spot. Cutting fluid is important both for tool
life and for controlling the heat that drives work hardening. This is one
of the more demanding materials for a hobby machine — expect to push the
limits of what a small spindle/router can rigidly hold.

## Acrylic (cast)

The single biggest risk is melting rather than cutting — acrylic has a low
melt point and re-solidifies as ugly melted-and-refrozen edges or clogs the
flutes entirely if chip evacuation and feed rate aren't matched to the
spindle speed. Single-flute "O-flute" bits designed for plastics clear
chips far better than a generic 2-flute end mill. If you see stringy,
melted chips instead of small chips flying clear, reduce spindle speed
and/or increase feed rate rather than lowering feed rate (a slower feed at
the same RPM dwells longer per chip and makes melting worse, not better).

## HDPE / Delrin (POM)

Similar melting risk to acrylic but more forgiving — Delrin (POM) in
particular is one of the best-machining plastics available and produces
clean, curly chips at correct settings. HDPE is softer and can lift off the
spreadboard if workholding isn't solid, since it's low-friction and light.
Single-flute or 2-flute plastic-specific bits again outperform general
purpose end mills for chip clearing.

## MDF

Produces very fine dust rather than chips — dust collection at the source
is essential both for tool life (fine dust packs into flutes and generates
heat) and for health (MDF dust contains resin binders and is a respiratory
irritant). Standard 2-flute up-cut router bits work well for through-cuts;
consider a down-cut or compression bit for a cleaner top surface as MDF
tends to fuzz/tear-out on the top edge with a pure up-cut.

## Plywood

The layered structure means grain direction changes between plies, which
is exactly why a compression bit (up-cut lower flutes, down-cut upper
flutes) exists — it pulls the bottom plies down and pushes the top plies
down simultaneously, avoiding the top-surface tear-out and bottom-face
splintering that a pure up-cut or down-cut bit each cause on their own on
plywood specifically. Cheaper plywood with voids in the inner plies can
cause a bit to suddenly grab or chatter when it hits a void — this is
normal and not a machine problem.

## Hardwood (oak/maple)

Grain direction matters a lot more than in sheet goods — cutting against
the grain on a profile pass increases tear-out risk noticeably. Take
lighter finishing passes on the final outline for a clean edge, and expect
more tool wear than softwood or sheet goods over a long job. Good dust/chip
extraction matters for visibility of the cut line as much as for tool life.

## Softwood (pine)

The most forgiving wood to machine and the best material to test new
feeds/speeds settings on before moving to a more expensive or less
forgiving material. Soft resinous woods like pine can gum up flutes with
sap/resin on longer jobs — an occasional pause to clean the bit with a
brush or bit cleaner keeps cut quality consistent through a long program.

## Copper
Gummy and prone to built-up edge. Use sharp, uncoated or polished carbide with 2 flutes, a light depth of cut and plenty of chip clearing (air blast or a mist of lubricant). Avoid rubbing: if chips come out as dust, feed is too low. Burrs are common — plan a light finishing pass.

## Polycarbonate (Lexan)
Tough and forgiving, but melts if the chips stay in the cut. Single- or 2-flute O-flute bits work best; keep the feed up so it cuts rather than rubs. Leave the protective film on, and expect a fuzzy edge that needs a light finishing pass. Do not use solvents to clean it.

## ABS
Cuts easily but softens quickly with heat. Use a single-flute or O-flute bit, a high feed and air blast to clear chips. Melted, re-welded chips in the slot mean the feed is too low or the spindle too fast.

## Nylon
Tough and stringy; chips tend to wrap around the tool. Use sharp single- or 2-flute bits, high feed, and clear chips often. It is hard to get a crisp edge — plan a deburring step.

## PVC foam board (Forex, Sintra)
Very easy to cut; the closed-cell foam machines cleanly with a single-flute bit at a high feed. Heat makes the edges melt and string, so keep the feed high. PVC dust and smoke are harmful — use dust collection and never let it burn.

## Solid surface (Corian)
Machines like a dense, slightly gummy plastic. Carbide 2-flute bits, moderate feed and good dust collection give a clean edge that sands to a polish. The dust is fine — wear a respirator.

## Machinable wax
Ideal for testing new toolpaths and mold making: it cuts like butter and is reusable. Feeds can be very high and depth of cut generous. Chips can stick in deep pockets — clear them with air.

## FR4 / PCB
Glass-fibre epoxy board used for printed circuits. Very abrasive: use carbide engraving V-bits or small end mills and expect them to wear. Keep depths shallow (a few hundredths of a millimetre for isolation routing), level the board with a probe or height map, and never breathe the dust — it is glass fibre. Use a vacuum and a respirator.

## Carbon fiber / G10
Abrasive composite sheets. Use carbide (ideally diamond-coated or compression) bits, shallow passes and good dust extraction. The dust is conductive and harmful — vacuum at the cutter, wear a respirator, and keep it away from electronics.

## XPS foam
Extruded polystyrene (insulation board) used for prototypes and molds. Cuts with almost no force at very high feed and deep passes; long single-flute or ball-nose bits work well. Heat and slow feeds melt it — keep the feed high.

## Bamboo
Behaves like a dense hardwood with long fibres that splinter at edges. Use a sharp compression or down-cut bit for clean top edges, moderate depth per pass, and support thin parts with tabs.
