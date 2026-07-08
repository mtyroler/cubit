# Assembling "Cheeky Tape" in Icon Composer

These four SVGs share the same 512×512 viewBox as the master (`../cubit-icon.svg`)
and stack in numeric order, back to front, to reproduce it exactly:

1. `01-background.svg` — teal-to-orange squircle, top glow, ground shadow.
2. `02-case.svg` — the glass case stack, belt clip, bolt.
3. `03-face.svg` — eyes, blush, mouth slot.
4. `04-tape.svg` — the tape tongue, its chin shadow, and lip-bend shading.

## Steps

1. Create a new Icon Composer document at 512×512 (or 1024×1024, scaling
   coordinates ×2).
2. Import each layer as a separate group/artboard layer, in the order above
   (background at the back, tape at the front).
3. Keep each layer's native blend mode (normal) and opacity as authored —
   nothing in these SVGs relies on non-default blending.
4. If Icon Composer applies its own specular/Liquid Glass material to a
   layer, prefer disabling it on `02-case.svg` and `04-tape.svg` — both
   already bake in their own highlight/shadow gradients, and doubling the
   glass effect will overexpose them.
5. Export the composed icon at the standard Apple sizes; compare against
   `../preview.png` to confirm color and proportions match.
