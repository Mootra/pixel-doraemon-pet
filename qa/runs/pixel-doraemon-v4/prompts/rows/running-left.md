Create one horizontal animation strip for Codex pet `pixel-doraemon-v4`, state `running-left`.

Use the attached canonical base for identity. Use the attached layout guide only for slot count, spacing, centering, and padding; do not draw the guide.

Output exactly 8 full-body frames in one left-to-right row on flat pure user-selected #FF00FF. Treat the row as 8 invisible equal-width slots: one centered complete pose per slot, evenly spaced, with no overlap, clipping, empty slots, labels, or borders.

Identity: same pet in every frame: Preserve the recognizable compact Doraemon identity from the current v3 atlas while redrawing every row for coherent animation. Follow qa/pixel-doraemon-v4-design-brief.md: corrected Take-copter lift, physically weighted Earth-destruction bomb heave, coherent Anywhere Door hinge, expressive anticipation/peak/follow-through/recovery, stable face and body proportions, and natural 16-direction head-eye mechanics.. Preserve silhouette, face, proportions, markings, palette, material, style, and props.
Style: Pet-safe sprite: compact full-body mascot, readable in a 192x208 cell, clear silhouette, simple face, stable palette/materials, and crisp edges for chroma-key extraction. Style `pixel`: Pixel-art-adjacent digital mascot with a chunky silhouette, simple dark outline, limited palette, flat cel shading, and visible stepped edges. User style notes: Crisp hand-placed retro game pixel art, limited saturated palette, consistent 2-3 pixel dark outline, no antialiasing, no gradients, stable 192x208-cell model proportions, readable at 85 percent app scale..
Animation continuity: keep apparent pet scale and baseline stable within the row unless the state itself intentionally changes vertical position, such as `jumping`. Move the pose within the slot instead of redrawing the pet larger or smaller frame to frame.

State action: Dragging-left loop: show directional movement to the left through body and limb poses only.

State requirements:
- Show directional drag movement to the left through body, limb, and prop movement only.
- The row must unmistakably face and travel left.
- The movement cadence must alternate visibly across the 8 frames instead of repeating one nearly static stride.
- Do not draw speed lines, dust clouds, floor shadows, motion trails, or detached motion effects.

V4 director notes: draw one complete eight-pose left-facing run cycle with two distinct contact poses, two down/compression poses, two passing poses and two airborne/up poses. Opposite paw and foot alternate; the round torso leans slightly left; the head and bell bob less than the hips; feet never slide backward; the smile becomes cheerful determination. Maintain the same side-facing face construction and body volume in all eight frames.

Clean extraction: crisp opaque edges, safe padding, no scenery, text, guide marks, checkerboard, shadows, glows, motion blur, speed lines, dust, detached effects, stray pixels, or chroma-key colors inside the pet.
