Create one horizontal animation strip for Codex pet `pixel-doraemon-v4`, state `waving`.

Use the attached canonical base for identity. Use the attached layout guide only for slot count, spacing, centering, and padding; do not draw the guide.

Output exactly 4 full-body frames in one left-to-right row on flat pure user-selected #FF00FF. Treat the row as 4 invisible equal-width slots: one centered complete pose per slot, evenly spaced, with no overlap, clipping, empty slots, labels, or borders.

Identity: same pet in every frame: Preserve the recognizable compact Doraemon identity from the current v3 atlas while redrawing every row for coherent animation. Follow qa/pixel-doraemon-v4-design-brief.md: corrected Take-copter lift, physically weighted Earth-destruction bomb heave, coherent Anywhere Door hinge, expressive anticipation/peak/follow-through/recovery, stable face and body proportions, and natural 16-direction head-eye mechanics.. Preserve silhouette, face, proportions, markings, palette, material, style, and props.
Style: Pet-safe sprite: compact full-body mascot, readable in a 192x208 cell, clear silhouette, simple face, stable palette/materials, and crisp edges for chroma-key extraction. Style `pixel`: Pixel-art-adjacent digital mascot with a chunky silhouette, simple dark outline, limited palette, flat cel shading, and visible stepped edges. User style notes: Crisp hand-placed retro game pixel art, limited saturated palette, consistent 2-3 pixel dark outline, no antialiasing, no gradients, stable 192x208-cell model proportions, readable at 85 percent app scale..
Animation continuity: keep apparent pet scale and baseline stable within the row unless the state itself intentionally changes vertical position, such as `jumping`. Move the pose within the slot instead of redrawing the pet larger or smaller frame to frame.

State action: Greeting loop: paw or limb down, raised, tilted, and returning in a friendly attention gesture.

State requirements:
- Show the greeting through paw, hand, wing, or limb pose only.
- Do not draw wave marks, motion arcs, lines, sparkles, symbols, or floating effects around the gesture.

V4 director notes: exact four-pose arc: friendly anticipation with the waving-side shoulder lifting and paw near the cheek; paw reaches high with open cheerful smile; paw crosses slightly outward at the peak with cheek squash and bell lag; arm settles halfway toward the first pose with a small overshoot. The paw must stay attached through a readable shoulder-elbow arc and the body must counter-lean subtly rather than remaining rigid.

Clean extraction: crisp opaque edges, safe padding, no scenery, text, guide marks, checkerboard, shadows, glows, motion blur, speed lines, dust, detached effects, stray pixels, or chroma-key colors inside the pet.
