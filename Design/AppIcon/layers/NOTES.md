# Assembling "Cheeky Tape" in Icon Composer

These four SVGs share the same 512×512 viewBox as the master (`../cubit-icon.svg`)
and stack in numeric order, back to front, to reproduce it exactly:

1. `01-background.svg` — teal-to-orange squircle, top glow, ground shadow.
2. `02-case.svg` — the glass case stack, belt clip, bolt.
3. `03-face.svg` — eyes and blush only.
4. `04-tape.svg` — chin shadow, tape tongue, **mouth slot**, and lip-bend
   shading, in that order.

The mouth slot lives in `04-tape.svg`, not `03-face.svg` — in the master, the
slot is painted *after* the tape tongue so it reads as sitting on top of it
(the tape appears to poke out from underneath the slot's lower lip). Layer
order **01 → 02 → 03 → 04** reproduces the master's paint order element for
element; this has been verified by rendering all four layers independently,
stacking them, and confirming the composite is visually identical to a
direct render of `../cubit-icon.svg`.

## Icon Composer: use the PNGs

Icon Composer doesn't render the master SVGs correctly — gradients and
`feGaussianBlur` filters aren't supported, so the glass layers come in as
flat ghost outlines, and because Icon Composer documents are commonly
1024pt, importing our 512-viewBox SVGs directly can size them at half the
canvas. To sidestep both problems, use the pre-rendered PNG layers in
`../layers-png/` instead of the SVGs:

(a) **Import the four PNGs from `layers-png/`** as layers, back to front,
    in the same order as above: `01-background.png`, `02-case.png`,
    `03-face.png`, `04-tape.png`. Each is a full-bleed, transparent
    1024×1024 render of its corresponding SVG (no icon-grid inset baked
    in — Icon Composer applies its own grid/margin), so at a 1024pt canvas
    they line up 1:1 with no scaling needed.

(b) **Alternative:** skip importing `01-background.png` and instead set the
    Icon Composer document's background to a custom linear gradient,
    `#FFD6AE` (top) → `#F97243` (bottom), letting the system own the base
    squircle shape and corner radius. The other three PNG layers still
    stack on top unchanged.

(c) **Turn Liquid Glass Effects OFF** for the `02-case` and `04-tape`
    layers — both already bake in their own highlight/shadow gradients and
    blur, so Icon Composer's own glass material will overexpose them.
    Taste-test the effect on `03-face` (it's just flat eye strokes and
    blush, so the system glass material may read fine there, but it's not
    load-bearing either way).

(d) Export the composed icon at the standard Apple sizes; compare against
    `../preview.png` to confirm color and proportions match.
