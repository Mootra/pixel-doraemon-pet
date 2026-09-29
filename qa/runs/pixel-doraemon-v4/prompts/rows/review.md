Create one horizontal animation strip for Codex pet `pixel-doraemon-v4`, state `review`.

Use the attached canonical base for identity. Use the attached layout guide only for slot count, spacing, centering, and padding; do not draw the guide.

Output exactly 6 full-body frames in one left-to-right row on flat pure user-selected #FF00FF. Treat the row as 6 invisible equal-width slots: one centered complete pose per slot, evenly spaced, with no overlap, clipping, empty slots, labels, or borders.

Identity: same pet in every frame: Preserve the recognizable compact Doraemon identity from the current v3 atlas while redrawing every row for coherent animation. Follow qa/pixel-doraemon-v4-design-brief.md: corrected Take-copter lift, physically weighted Earth-destruction bomb heave, coherent Anywhere Door hinge, expressive anticipation/peak/follow-through/recovery, stable face and body proportions, and natural 16-direction head-eye mechanics.. Preserve silhouette, face, proportions, markings, palette, material, style, and props.
Style: Pet-safe sprite: compact full-body mascot, readable in a 192x208 cell, clear silhouette, simple face, stable palette/materials, and crisp edges for chroma-key extraction. Style `pixel`: Pixel-art-adjacent digital mascot with a chunky silhouette, simple dark outline, limited palette, flat cel shading, and visible stepped edges. User style notes: Crisp hand-placed retro game pixel art, limited saturated palette, consistent 2-3 pixel dark outline, no antialiasing, no gradients, stable 192x208-cell model proportions, readable at 85 percent app scale..
Animation continuity: keep apparent pet scale and baseline stable within the row unless the state itself intentionally changes vertical position, such as `jumping`. Move the pose within the slot instead of redrawing the pet larger or smaller frame to frame.

State action: Ready-review loop: focused inspection of completed output with lean, blink, narrowed eyes, head tilt, or paw pose.

State requirements:
- Show review through lean, blink, narrowed eyes, head tilt, or paw/hand position.
- Do not add magnifying glasses, papers, code, UI, punctuation, symbols, or other new props unless they already exist in the base pet identity.

V4 director notes: exact six-pose focused thought arc: calm attentive stance; upper body leans in while eyes narrow; one paw reaches the chin and eyebrows focus; head tilts slightly with eyes tracking across an imagined result; small realization with brighter eyes and lifted cheek; paw lowers and the body returns smoothly to calm confidence. Preserve skull width, eye spacing, red nose attachment and muzzle shape; expression changes must not morph the face or slide it across the head.

Clean extraction: crisp opaque edges, safe padding, no scenery, text, guide marks, checkerboard, shadows, glows, motion blur, speed lines, dust, detached effects, stray pixels, or chroma-key colors inside the pet.
