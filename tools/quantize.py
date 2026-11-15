#!/usr/bin/env python3
"""Palette-quantise RGBA PNGs for the Roku package.

The whole channel must fit in 4 MB (Roku certification 3.7), so sprite atlases
are stored as 8-bit palette PNGs with per-entry alpha (PLTE + tRNS), which Roku
decodes natively. Uses libimagequant when the `imagequant` module is installed
(pip install imagequant) and falls back to Pillow's octree quantiser.

    quantize.py <in.png> <out.png> [--colors 256] [--dither 0.0] [--jpeg 82]
"""
import sys

from PIL import Image


def quantize(img, colors=256, dither=0.0):
    img = img.convert("RGBA")
    try:
        import imagequant
        return imagequant.quantize_pil_image(img, dithering_level=dither, max_colors=colors, min_quality=0, max_quality=100)
    except ImportError:
        return img.quantize(colors=colors, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)


def main(argv):
    src, dst = argv[1], argv[2]
    colors, dither, jpeg = 256, 0.0, 0
    i = 3
    while i < len(argv):
        if argv[i] == "--colors":
            colors = int(argv[i + 1])
        elif argv[i] == "--dither":
            dither = float(argv[i + 1])
        elif argv[i] == "--jpeg":
            jpeg = int(argv[i + 1])
        i += 2
    img = Image.open(src)
    if jpeg:
        img.convert("RGB").save(dst, "JPEG", quality=jpeg, optimize=True, progressive=False, subsampling=2)
    elif colors <= 0:
        img.save(dst, "PNG", optimize=True)
    else:
        quantize(img, colors, dither).save(dst, "PNG", optimize=True)


if __name__ == "__main__":
    main(sys.argv)
