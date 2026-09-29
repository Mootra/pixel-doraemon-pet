Create one horizontal animation strip for Codex pet `pixel-doraemon-v4`, state `idle`.

Use the attached canonical base for identity. Use the attached layout guide only for slot count, spacing, centering, and padding; do not draw the guide.

Output exactly 6 full-body frames in one left-to-right row on flat pure user-selected #FF00FF. Treat the row as 6 invisible equal-width slots: one centered complete pose per slot, evenly spaced, with no overlap, clipping, empty slots, labels, or borders.

Identity: same pet in every frame: Preserve the recognizable compact Doraemon identity from the current v3 atlas while redrawing every row for coherent animation. Follow qa/pixel-doraemon-v4-design-brief.md: corrected Take-copter lift, physically weighted Earth-destruction bomb heave, coherent Anywhere Door hinge, expressive anticipation/peak/follow-through/recovery, stable face and body proportions, and natural 16-direction head-eye mechanics.. Preserve silhouette, face, proportions, markings, palette, material, style, and props.
Style: Pet-safe sprite: compact full-body mascot, readable in a 192x208 cell, clear silhouette, simple face, stable palette/materials, and crisp edges for chroma-key extraction. Style `pixel`: Pixel-art-adjacent digital mascot with a chunky silhouette, simple dark outline, limited palette, flat cel shading, and visible stepped edges. User style notes: Crisp hand-placed retro game pixel art, limited saturated palette, consistent 2-3 pixel dark outline, no antialiasing, no gradients, stable 192x208-cell model proportions, readable at 85 percent app scale..
Animation continuity: keep apparent pet scale and baseline stable within the row unless the state itself intentionally changes vertical position, such as `jumping`. Move the pose within the slot instead of redrawing the pet larger or smaller frame to frame.

State action: Calm low-distraction resting loop: subtle breathing, tiny blink, slight head/body bob, and only quiet persona-preserving motion.

State requirements:
- CRITICAL: idle is the low-distraction baseline state and the first frame is also used as the reduced-motion static pet.
- Use only subtle idle motion: gentle breathing, a tiny blink, a slight head or body bob, a very small material sway, or another quiet motion that fits the pet persona.
- Keep the pet essentially in the same pose, facing direction, silhouette, markings, palette, and prop state across all 6 frames.
- Idle variation must stay calm but still read as animation; do not repeat effectively identical copies across the loop.
- Do not show waving, walking, running, jumping, talking, working, reviewing, emotional reactions, large gestures, item interactions, or new props.
- Feet, base, body, or object anchor should remain planted or nearly planted.
- The first and last frames should be very close visually so the loop feels calm and does not pop.

V4 director notes: use this exact emotional arc left to right: relaxed small smile and neutral breath; chest and belly expand by only a few pixels while the bell lags; eyelids begin a blink; eyes fully close with cheeks gently lifting; eyes reopen with a tiny head rebound; return almost exactly to frame 1. Keep both feet planted and preserve one centered red nose and three whiskers per cheek.

Clean extraction: crisp opaque edges, safe padding, no scenery, text, guide marks, checkerboard, shadows, glows, motion blur, speed lines, dust, detached effects, stray pixels, or chroma-key colors inside the pet.
