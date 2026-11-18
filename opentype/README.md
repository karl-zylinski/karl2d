Package for reading `.otf`, `.ttf` and `.ttc` files and rasterizing them. These formats can contain both TrueType glyph contours and CFF (Compact Font Format) contours. This package only cotains the features that Karl2D needs, it's not as general as stb_truetype.

---

This package is a heavily modified port of stb_truetype. The rasterization is different, it uses the accumulation approach from font-rs by Raph Levien.

Since the stb_truetype parts began as straight ports, this falls under its license, which you can read in LICENSE.