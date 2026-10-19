# The Shifting Abyss — approved direction and scope freeze

## Approved creative direction

Dungeon15 is an original dark-fantasy action roguelite starring a lone samurai
trapped in an enormous supernatural castle inhabited by demons. The castle is
an antagonist: impossible architecture and changing connections resist escape.
The player can ultimately discover a legitimate way out. This direction does
not prescribe character names, a mythology, boss identities or the ending's details.

Intended gameplay loop: explore and orient yourself; fight demons; discover
clues; activate mechanisms or unlock routes; observe and investigate event-driven
spatial changes; make progress toward escape. This is the long-term game loop,
not a claim that these features exist in the current 3D demo.

Create original visual language, mythology, characters and environments. Do not
reproduce Demon Slayer's Infinity Castle, its locations, recognizable designs or
characters. Legacy 2D campaign notes (including Queen/King and fifteen-depth
ideas) remain historical context; they do not automatically become canon for
this newly approved 3D direction. No replacement lore is invented here.

## Locked architectural behavior

Transformations are **event-driven**, not continuously or randomly rearranged.
Possible future triggers are defeating important demons, activating ancient
mechanisms, finding hidden passages and reaching progression milestones. These
are approved trigger categories, not implemented encounters or scripts.

Each transformation must preserve a valid route toward progression or escape.
Use predefined valid connection states. Check player occupancy, collision,
clearance and reachability before committing a state change. Never trap, crush
or permanently softlock the player. If a proposed change is unsafe, defer it or
keep the last valid state. Do not invent a random fallback that breaks the route.

Spatial changes should be discoverable: provide understandable landmarks and
evidence that a connection changed, so the player can investigate uncertainty.
The timing comes from meaningful events; deterministic selection may choose a
valid outcome for the same event/state/seed, but may not introduce timer-driven
unconstrained shuffling. Exact telegraphs and interaction design remain future work.

## Long-term world vision versus October 25 release candidate

The long-term vision includes monumental interconnected vertical architecture,
progressive bounded world extension, inexpensive distant structures, demons,
clues and mechanisms, and safe event-driven changes. It does not promise infinite
memory or geometry. These remain staged work requiring approval.

October 25 is the stated playable release-candidate target, not an authorization
to implement the entire vision. No owner-approved content/platform/performance
release checklist was found in the repository. The following is the current
technical scope baseline; a complete game release scope still needs owner
confirmation. The target date is not evidence that an RC is ready.

| Area | Current playable baseline / RC acceptance work | Long-term work outside this task |
|---|---|---|
| World | Bounded, seeded Stage 3 graybox; entry-to-exit exploration | Streaming, distant castle dressing, richer spatial modules |
| Player | Validated capsule, fixed isometric camera, keyboard/analog/D-pad | Samurai art, animation, combat and character progression |
| Seed testing | Inspector World Seed and buttons for 12345, 42, 7 | Persistent run/progression state and replay systems |
| Castle changes | Static layout throughout each playthrough | Event-driven, validated connection-state transitions |
| Narrative | Approved premise and intended loop documented | Demons, clues, mechanisms, dialogue, escape story implementation |
| Acceptance | Automated generation/traversal regressions plus owner play-test | Production hardware budgets, packaging and broader game-release gates |

For this task, delivery is documentation and seed-test usability only. Do not
expand the October 25 scope into combat, assets, Stage 4 or transformations.
Manual generated-layout acceptance and physical GP325 checks are still needed.
The unchanged 2D game is a separate preserved baseline, not evidence of a 3D
samurai/demon gameplay implementation.

## Future connection to the spatial composer — design only

Keep the current composer responsible for the initial seed/config/profile layout.
Its room IDs, connection IDs, graph roles and entry/exit sockets provide stable
references for future event targets within that layout. A seed/config change
creates a new run identity; IDs must not be reused across unrelated runs.

A future event controller can consume an event record containing run/layout
identity, unique event ID, progression state, and affected room/connection IDs.
It can select a predefined transition using a separate versioned seed namespace,
construct a candidate graph/spatial state, and validate progression reachability,
socket alignment, geometry clearance and occupancy before applying it. Record
applied event IDs/state to make replay deterministic and prevent duplicate events.

The current spatial validator checks static structure and all-room reachability;
it has no occupancy, transition sweep, progression-state or atomic runtime-swap
contract. Those validations and safe transition application must be designed and
tested in their approved stage. Do not simply regenerate a different whole layout
under an occupied player. Preserve the last valid state on rejection.

The seed buttons explicitly restart the demo, resetting player position and exit
completion. They are test controls, not a prototype of an event-driven castle
transformation. No event bus, transformation controller, streaming or demon
implementation is added by this document.
