# Brand

- Name: Opaque. Wordmark is lowercase "opaque" in a mono face.
- Ticker: $OPA (fallbacks $OPAQ, $OPQ).
- Domain: opaque.sh
- GitHub: opaque-sh (backup opaque-protocol)
- X: @opaque_sh, display name "Opaque"

## Taglines

- Everything on-chain, except you.
- Transparent protocol. Opaque balances.
- Get paid to disappear.

Headline: the privacy coin that pays you to stay private.

## Look

- Fluted glass, halftone and dither, grain.
- Near-black background. One teal accent, used only for reveal or yield.
- Mono type.

## Logo

Two concepts, drawn as SVG in `brand/logo/` (preview: `brand/logo/preview.png`). Regenerate with `python3 tools/gen_logos.py`.

1. **Dissolving disc** (`disc-*.svg`): a solid circle breaking into halftone dots, so the dither texture is the mark. `disc-icon.svg` has bigger dots for token and favicon use. The teal dots mark the dissolve front.
2. **Sliced o** (`o-*.svg`, `lockup-*.svg`): a ring cut into horizontal slats like reeded glass. The lockup swaps it in for the `o` of `opaque`, set in Geist Mono Medium. The teal line sits in one gap only.

Variants: `full` (dark tile with teal), `mono-white` and `mono-black` (transparent, no teal).

Notes:
- The wordmark is outlined from Geist Mono (SIL Open Font License, copy in `brand/fonts/`), so the SVGs need no font installed.
- The earlier Gemini slat-and-disc image was only a sketch and is not used.
- Check small sizes before picking a final. At 16px the disc becomes a smudge, so the sliced ring is the safer favicon.
