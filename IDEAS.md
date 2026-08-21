# Blaze and Heat — IDEAS.md

*Brainstorm output, 2026-07-16. Next step: build M0 from this file in a fresh session (Sonnet is fine — direction lives here).*

## Pitch

A physics-true combat robotics game: BattleBots where damage isn't hit points and canned animations — it's actual kinetic energy. A vertical spinner stores real angular momentum and dumps it into whatever it touches; armor panels shear off when the impulse says they should; a flipper only lands if its impulse beats the opponent's effective mass. Built by someone who actually builds combat robots (CRC), which is the unfair advantage: the sim will *feel* right, and the club is a built-in playtest group.

## Decisions made (locked for v1)

- **Goal:** portfolio + learning. Optimize for demoable physics/graphics moments and skills acquired. Demo-sized scope is fine; polish where visible.
- **Stack:** Godot 4 (4.4+) with the built-in **Jolt** physics backend (Project Settings → Physics → 3D → Physics Engine → Jolt Physics). GDScript first; drop to C# / GDExtension only if profiling demands it.
- **First playable:** single-player vs AI — one match, one arena, win by knockout.
- **Core loop:** *drive* pre-made archetypes, not build them. Garage/builder editor is explicitly v2.

## Design pillars

1. **The physics is the content.** No damage tables. Every spark, dent, and detached panel traces back to a real collision impulse. If a mechanic can't be expressed physically, cut it.
2. **Readable spectacle.** A spectator who knows nothing should understand the story of a hit: spin-up whine → impact → sparks → panel tumbling across the arena → slow-mo replay.
3. **Hand-tuned archetypes.** Few bots, each lovingly tuned, each teaching a different physics system (spinner = angular momentum, flipper = impulse, wedge = friction and geometry).
4. **Honest, not simulationist.** Real-bot knowledge informs the feel; it does not mandate realism. Fun wins every argument (the CRC-accuracy mode can be a v2 toggle).

## Physics design

**Bot structure.** Chassis = one `RigidBody3D`. Armor panels = separate `RigidBody3D`s "welded" on via joints (`Generic6DOFJoint3D` locked stiff). Godot has no native breakable joints, so breaking is ours: monitor contact impulses on each panel, accumulate structural damage, and when it passes the panel's threshold, free the joint — the panel becomes debris with whatever velocity it already had. This "pre-authored breakpoints" approach is the tractable 90% of destruction; do **not** attempt runtime mesh fracture.

**Damage model.** On collision, read the contact impulse (Jolt exposes it via body contact reports). Damage ∝ impulse magnitude above a per-panel tolerance — so a slow shove does nothing and a spinner strike at full RPM is catastrophic, with no special-casing. Weapons aren't flagged as weapons; they're just very good at delivering impulse.

**Spinner energy storage.** Spinner blade = its own rigid body on a `HingeJoint3D` with motor. Spin-up takes seconds (readable: rising whine pitch, motion blur). All the interesting behavior — gyroscopic precession when the bot turns, recoil kicking both bots apart on impact, the weapon stalling after a big hit — falls out of Jolt for free. This is the signature system; tune it first and hardest.

**Flipper.** Impulse applied over a short joint-motor stroke. Whether the opponent actually flies is pure mass/leverage — getting under them matters, exactly like the real sport.

**Knockout rule (from the real sport).** A bot is counted out if it's commanded to move but its velocity stays under a threshold for ~10 seconds (immobilized/dead weapon doesn't count). Physically checkable, no referee logic.

## Graphics showcase list (Godot specifics)

- **Sparks:** `GPUParticles3D` bursts emitted at contact points, scaled by impulse. Cheapest, highest-value effect — do it in M1.
- **Metal denting:** damage-mask texture per panel driving vertex displacement in the shader. Panels look progressively beaten up before they shear off.
- **Slow-mo kill cam:** on knockout blow, `Engine.time_scale` ramp + orbiting replay camera. Portfolio gold.
- **Arena mood:** `WorldEnvironment` with SDFGI, volumetric fog, hot arena spotlights; polished-metal PBR so bots reflect the lights.
- **Spinner blur:** velocity-stretched trail mesh or particle trail once RPM passes a threshold; doubles as the "weapon is hot" readability cue.
- **Persistent debris:** detached panels stay in the arena and keep interacting. Sell it — debris getting kicked around mid-fight is free spectacle.

## AI (the chosen first-playable differentiator — keep it small)

Utility/state-machine driver, per archetype, no ML, no pathfinding beyond "arena is an open box":

- **Spinner AI:** keep weapon facing the enemy, spin up before closing, disengage to re-spin after big hits, avoid exposing sides.
- **Wedge AI:** drive at the enemy's wheels, get under, push toward walls/hazards.
- v0 is literally "face enemy + drive at them," which is already a credible arena opponent. Cheat invisibly (perfect aim with reaction delay) rather than simulating perception.

## Milestones

- **M0 — drivable sandbox (a weekend):** Godot project, Jolt enabled, one arena box, one wedge bot (chassis + 4 wheels, arcade-ish tank drive), chase camera. *Success: driving feels good.*
- **M1 — the damage model:** contact-impulse logging, breakable panels on a static test dummy, sparks on impact. *Success: you can knock a panel off and it tumbles convincingly.*
- **M2 — the signature hit:** vertical-spinner bot with motorized blade + energy storage; spinner vs wedge, both fully panelled. Hand-tune until one full-RPM strike is genuinely thrilling. *Success: a clip worth posting.*
- **M3 — first playable (the chosen milestone):** AI drivers for both archetypes, match loop with countdown, knockout detection, win screen. *Success: a stranger plays a full match unaided.*
- **M4 — spectacle pass:** slow-mo kill cam, denting shader, arena lighting/volumetrics, sound (motor whine pitch = stored energy).
- **M5 — ladder:** 4 archetypes (add flipper + hammer), simple bracket/tournament wrapper.
- **v2 parking lot:** garage builder, online multiplayer, CRC-accuracy mode (real units, export a design report), workshop bot sharing.

## Risks

- **Destruction is the hardest system.** Mitigation: pre-authored breakpoints only; panels are rigid bodies from frame one so "breaking" is just deleting a joint.
- **Realism trap.** Knowing real bots invites simulating them past the fun. Mitigation: pillar 4; every realism feature must buy spectacle or readability.
- **Incumbent:** Robot Rumble 2.0 owns "combat robots sim." Differentiate on destruction spectacle and physics honesty, not roster size.
- **AI scope creep.** It was flagged as a real subproject; the mitigation is the milestone order above — AI lands at M3, *after* the sandbox and damage model exist, and stays utility-simple.

## Open questions — answered

- **Art style: stylized-PBR.** Confirmed by what shipped. Primitive forms, polished-metal
  PBR, a world-space grid floor, glow and volumetric fog. The recommendation held: it hides
  the solo-art limits and reads well in clips.
- **Panel damage: accumulated impulse above a per-panel tolerance — but denominated in force
  (N), not impulse.** This is the "small HP abstraction" in practice, except the units are
  physical, so it never needs a lookup table. Measuring force rather than raw impulse was
  forced by two findings: contact impulse arrives spread over many points and many ticks, so
  a per-point threshold registered *zero* damage on eight consecutive full-speed rams; and an
  impulse threshold silently means something different at 60 Hz than at 120 Hz. Thresholds
  were then set from a measured distribution rather than by feel (shove peaks ~140 N, a
  full-speed wedge ram ~700 N, so tolerance sits at 250 N).
- **Arena hazards: the pit is in v1; kill saws are deferred.** The pit earns its place because
  it costs almost nothing conceptually — a hole in the floor and a depth check — and it stays
  honest to pillar 1: nothing tags it as a hazard, nothing scores it, the geometry simply has
  a hole and gravity does the rest. Kill saws need slots cut through the floor *and* would
  have to be balanced against the panel damage model, which is a tuning job rather than a
  build job. They are the obvious first addition once the archetype balance settles.
- **Project/game name: Blaze and Heat.**

## Status

M0–M5 are built. Four archetypes (wedge, spinner, flipper, hammer), the impulse damage model
with shearing panels and persistent debris, AI drivers, a match loop with countdown and
knockout, the full spectacle list, a pit, and a four-bot single-elimination ladder that runs
end to end and decides every bout on a knockout or the pit rather than the clock.

Each system has a headless bench under `tests/` that drives the real scenes and prints the
numbers that define its feel — run those before and after touching anything physical. Note
that `godot --headless --import` does *not* compile GDScript; only a script run or a game
boot does.

A readability pass followed (2026-08-20). Three things the footage made obvious that
playing it had not:

- **The arena was lit into a milky grey.** Fog and volumetric density were high enough to
  wash the far wall and everything in front of it, which desaturated the one thing carrying
  each bot's identity -- its hull colour. Ambient and fog came down, glow threshold went
  below 1.0, and the light rig moved into `scenes/ArenaMood.tscn`.
- **The ladder looked worse than a single bout.** `Tournament.tscn` had grown its own bare
  `WorldEnvironment` -- no sky, fog, glow or spotlights -- so the mode that plays itself,
  and is therefore the one most likely to be watched, was the ugliest thing in the project.
  Both scenes now instance the same rig.
- **The pit was invisible.** A near-black 3 m hole in a dark floor cannot be seen until
  something falls in it, which makes the only instant-loss feature unreadable. There is now
  hazard paint around the lip: four meshes on the floor, no collider, nothing tagging it as
  a hazard. Pillar 1 is intact -- the geometry has a hole and gravity does the rest; pillar 2
  finally holds too.

Also fixed: the kill cam orbited through the wall whenever the loser was pinned against one,
which is most of the time, so the finishing blow played as several seconds of flat red. The
orbit is now clamped to the wall inner faces and lifts by whatever reach it gives up.

### Why the damage model never fires: nobody ever gets pinned

Found 2026-08-21 while chasing why a full-speed ram banks nothing. Three separate
things, each hiding the next.

**The calibration numbers were read off the wrong body.** `tolerance` was set from
"a shove peaks ~140 N, a full-speed ram ~700 N" -- but those were the *attacker's*
chassis force, not the force on the *defender's* panel, and the tolerance is only ever
compared against the second. `DriveBench` printed the same mismatch, attacker force
next to defender damage, which made the model look broken rather than mis-aimed. It now
prints both, labelled.

**The plow never touches armour at all.** Re-measured on the panel itself: a full-speed
wedge ram is 426-453 N at the attacker and **0 N** at the armour. Not "below tolerance"
-- zero. The plow passes under the panels and drives into the core. The old comment
claiming "roughly 4.5 N·s per ram, three or four solid hits" was never measured; the
intent in the same breath ("a plow is a ramp... it should struggle to shear armour") was
right, and understated -- it never touches it.

**Every archetype is armoured only where it does not get hit.** All four carry exactly
`PanelTop` and `PanelRear`. Nothing on the front, nothing on the flanks. The AI drives
straight at its enemy, so every engagement lands on the plow, the blade or the bare
chassis. `PanelDummy` is the only object in the project with front and side panels --
which is why it is the only thing that has ever taken damage, and why the model looked
healthy in `SpinnerBench` while doing nothing in `MatchBench`.

**And that is the whole answer.** The dummy weighs 150 kg and does not drive away. A 54 kg
machine that is free to be thrown mostly *is* thrown -- the blade's 4302 J goes into
launching it 791 mm up and 3.95 m across rather than into denting it. Back the same bot
against a wall and the blade has to spend its energy through the armour instead:

    spinner at 4302 J, free bot                 69 N on the panel, nothing
    spinner at 4302 J, bot pinned on a wall   1779 N on the panel, SHEARS in one
    wedge shove, bot pinned on a wall             5 N on the panel, nothing

So the model is not broken and 250 N is not mis-set -- it separates a 5 N shove from a
1779 N strike with margin on both sides, exactly as intended. What was missing is the
tactic. Damage requires taking the opponent's escape away first, which is the sport, and
no driver in the game ever did it: `BotAI._plan()` returned "drive straight at the enemy"
and the enemy simply flew away. This file specified the missing half from the start --
"Wedge AI: drive at the enemy's wheels, get under, push toward walls/hazards" -- and only
the first half was ever built.

**Built now.** The AI aims *through* the enemy at whichever wall is nearest to it, inside
a range where that reads as a shove rather than a detour. One number, `wall_push`, and it
is a straight lever on how violent a bout is:

    wall_push   bout    blade bites   hardest on armour (bar is 250 N)
    0.0        34.9 s        1        wedge 107 N   spinner 185 N
    2.5        27.7 s        2        wedge 138 N   spinner 165 N
    4.0        23.4 s        4        wedge 435 N   spinner 277 N

At 4.0 both machines are driven past tolerance in an ordinary bout and the wedge banks
real damage for the first time -- 2 N·s, against the 14 N·s a panel survives, so plates
now dent and discolour in play even though shearing still wants a cleaner hit. Bouts got
a third shorter, because a fight where someone is being worked into a wall ends sooner
than one where both machines skate around open floor.

Ladder balance moved with it: the hammer, which used to flip itself out of its semi-final,
is now champion.

Tried and reverted: side skirts outboard of the wheels on all four archetypes. They work
-- flank hits went from 0 N to 69 N, and they protect the wheels, which are the real
vulnerability. But they cut the spinner's signature launch from 791 mm to 265 mm and made
the hammer's backflip worse (204 mm of self-lift to 337 mm). Trading the best moment in
the game for a damage model that still would not fire is a bad deal. The measurements are
in `tests/ImpactBench.gd`; the design call is open.

Known soft spots, in priority order:

1. **The hammer no longer beats itself, but still does no armour damage.** The backflip
   was measured rather than guessed at (`ArmBench` now reports peak pitch and where the
   bot settles): a dry stroke reared it to **85 degrees and left it lying at 81** — a bout
   lost to its own weapon every time it fired, which is why it looked like a damage
   problem. Shao's call was to keep the rear-up rather than design it out, so it is now
   bounded by geometry instead of by a rule: a wheelie bar behind the rear axle that meets
   the floor part-way through the stroke. Nothing checks an angle and nothing cancels a
   torque; there is simply something back there to land on. It now rears to **29 degrees
   and settles flat**, and in the ladder it beats the flipper and reaches the final
   instead of going out in its semi. Still open: it delivers nothing to armour — but that
   is the placement problem above, not the hammer's.
2. **Armour costs a lot of agility** — the wedge's pivot roughly halved once panels went on,
   because they sit far from the yaw axis. That trade-off is real and arguably good; the
   current 2 kg panels are a compromise, not a settled answer.
3. **Bench numbers vary run to run** — pivot rate has read anywhere from 96 to 213 deg/s on
   identical code, depending on how the bot settled. Average before tuning against it.

### A bug worth remembering

Three separate times, something read state during node construction that was not set yet:
the AI cached the spinner's full-energy yardstick before the blade's inertia existed; the
match's opening bout was announced before anything could subscribe; and the tournament wired
each driver's enemy *after* `add_child`, which had already run `_ready` and cached a null.

That last one was the expensive one. Every tournament bout was two idle machines running out
the clock, and it looked exactly like a balance problem — it was written up here as "fights
stalemate, bots lock up rather than finishing each other" before the cause was found. In
Godot, `add_child` runs `_ready` immediately; anything a node reads there must be set before
it, or passed in afterwards through a setter. The ladder bench now asserts that bouts end
decisively, so an idle AI cannot masquerade as a design problem again.
