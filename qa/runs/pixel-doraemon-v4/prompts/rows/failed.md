Create one horizontal animation strip for Codex pet `pixel-doraemon-v4`, state `failed`.

Use the attached canonical base for identity. Use the attached layout guide only for slot count, spacing, centering, and padding; do not draw the guide.

Output exactly 8 full-body frames in one left-to-right row on flat pure user-selected #FF00FF. Treat the row as 8 invisible equal-width slots: one centered complete pose per slot, evenly spaced, with no overlap, clipping, empty slots, labels, or borders.

Identity: same pet in every frame: Preserve the recognizable compact Doraemon identity from the current v3 atlas while redrawing every row for coherent animation. Follow qa/pixel-doraemon-v4-design-brief.md: corrected Take-copter lift, physically weighted Earth-destruction bomb heave, coherent Anywhere Door hinge, expressive anticipation/peak/follow-through/recovery, stable face and body proportions, and natural 16-direction head-eye mechanics.. Preserve silhouette, face, proportions, markings, palette, material, style, and props.
Style: Pet-safe sprite: compact full-body mascot, readable in a 192x208 cell, clear silhouette, simple face, stable palette/materials, and crisp edges for chroma-key extraction. Style `pixel`: Pixel-art-adjacent digital mascot with a chunky silhouette, simple dark outline, limited palette, flat cel shading, and visible stepped edges. User style notes: Crisp hand-placed retro game pixel art, limited saturated palette, consistent 2-3 pixel dark outline, no antialiasing, no gradients, stable 192x208-cell model proportions, readable at 85 percent app scale..
Animation continuity: keep apparent pet scale and baseline stable within the row unless the state itself intentionally changes vertical position, such as `jumping`. Move the pose within the slot instead of redrawing the pet larger or smaller frame to frame.

State action: Blocked/failed loop: slumped or deflated reaction with sad or closed eyes.

State requirements:
- Show failure through slumped pose, drooping ears/limbs, closed or sad eyes, and lower body position.
- Tears, small smoke puffs, or tiny stars are allowed only if attached to or overlapping the pet silhouette and kept inside the same frame slot.
- Do not draw red X marks, floating symbols, detached stars, separated smoke clouds, falling tear drops, dust, or other loose effects.

V4 director notes: replace the generic slump with Doraemon's signature mouse-triggered panic and one coherent heavy Earth-destruction bomb action. Exact eight poses: startled wide-eyed recoil; one paw reaches into the belly pocket while the other braces; a single heavy dark cylindrical bomb emerges with both hands attached; Doraemon bends knees and leans back under its weight; heaves upward along one continuous arc; maximum two-handed overhead hold with clenched teeth, squashed legs and strongest silhouette; bomb lowers only slightly as the body overshoots and trembles; shaken recovery with the bomb still physically supported near the body. The bomb has consistent barrel size, two end caps and one simple central emblem shape without text. Never teleport, duplicate, float, drop, fire or explode the bomb; impact comes from weight, face, pose and peak hold.

Clean extraction: crisp opaque edges, safe padding, no scenery, text, guide marks, checkerboard, shadows, glows, motion blur, speed lines, dust, detached effects, stray pixels, or chroma-key colors inside the pet.
