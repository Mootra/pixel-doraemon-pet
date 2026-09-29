# Pixel Doraemon v4 visual direction

## Identity lock

- One consistent compact Doraemon model in every row: round blue head, white face field, one centered red nose, three whiskers per cheek, red collar with yellow bell, white belly and centered four-dimensional pocket, short white paws and feet, small red tail.
- Friendly late-1980s/1990s game-sprite feeling with clean hand-placed pixel clusters, a limited saturated palette, crisp black/dark-navy outlines, no antialiasing, no gradients, no soft glow, and no vector-smooth edges.
- Keep head/body proportions, pocket size, bell position, eye spacing, nose size, outline weight, pixel density, baseline, and overall volume stable across all actions.
- Faces must remain structurally consistent: the eyes sit together above the nose, the nose stays attached to the face centerline, the mouth does not migrate across the muzzle, and whiskers follow cheek perspective.

## Expression bible

- `idle`: warm small smile, relaxed eyelids, one natural blink, quiet breathing and a tiny tail/bell follow-through.
- `running-right` / `running-left`: cheerful determination; alternating foot contacts, opposite arm swing, modest head and bell bob, readable side-facing travel.
- `waving`: bright greeting; shoulder lifts first, paw opens through a clear arc, cheeks rise, then the arm overshoots slightly and settles.
- `jumping`: delighted but physically grounded Take-copter flight; crouch/prepare, rotor spin-up, lift, airborne apex, hover, controlled descent and soft landing.
- `failed`: escalating mouse-triggered panic and heavy Earth-destruction bomb action; startled reach, pocket pull, two-handed load, squat/wind-up, strained overhead peak, recoil and shaken recovery. The bomb remains physically attached to the hands in every visible bomb frame.
- `waiting`: expectant and polite, not idle duplication; hands clasp, weight shifts, eyes check the user, ears/eyelids and bell give a restrained follow-through.
- `running` (task work): one coherent Anywhere Door interaction; summon/brace the door, open it on a consistent hinge, peek/step through, then emerge and settle. Door dimensions and perspective stay fixed.
- `review`: concentrated reading/thinking without a new floating prop; lean in, narrow eyes, paw to chin, small head tilt, realization, and calm return.

## Prop physics

- Take-copter: short stem planted at the exact top-center of the head; rotor is a flattened elliptical disc whose perspective changes coherently. Body hangs below the lift point, feet trail slightly on ascent, and landing compresses the body. No detached rotor, no golden crown, no floor shadow.
- Earth-destruction bomb: one heavy dark cylindrical barrel with two end caps and a central hazard-like emblem shape but no readable text. It visibly weighs more than Doraemon's arms can casually hold. Use two-handed contact, bent knees, backward lean, cheek strain and a brief overhead hold; never teleport it between waist and head.
- Anywhere Door: stable pink-red rectangular door, consistent knob and hinge side, no changing width or impossible panel perspective. Doraemon always contacts or passes through it physically.

## Motion and impact

- Every action has a readable sequence: anticipation, action, peak/impact, follow-through, recovery.
- Use pose silhouette, facial expression, squash/stretch within volume, held-frame timing and attached prop motion for impact. Avoid detached speed lines, floating particles, dust, floor shadows, glow, blur or loose explosion fragments.
- A strong action may hold its peak pose longer, but adjacent frames must still progress along one continuous body/prop arc.

## Look mechanics

- Feet, belly and pocket stay registered. Eyes lead; nose/face and head follow; whiskers, bell and upper torso lag subtly.
- Horizontal cardinals reveal the corresponding side of the face and move nose/pupils across the head center. Vertical cardinals use eyes, eyelids and modest head pitch without crushing or stretching the skull.
- The 16 directions form one clockwise family. No whole-sprite rotation, no replacement eyes, no face-size popping and no sudden occlusion jumps.
