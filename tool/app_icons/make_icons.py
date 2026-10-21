"""Makes every app icon and in-app logo from one square logo image.

Usage (needs Pillow), from the repository root:
  python3 tool/app_icons/make_icons.py path/to/logo.png

Overwrites the iOS, macOS, Android, web, Linux and Windows icons in place,
keeping each file's size and each platform's existing shape (full-bleed
squares on iOS, inset rounded squares on macOS and Linux), plus the
home-screen widget logos and assets/images/puddingcup_logo.png.
"""

import glob, os, sys
from PIL import Image, ImageDraw

src = Image.open(sys.argv[1]).convert('RGB')

def square(size):
    return src.resize((size, size), Image.LANCZOS)

def rounded(size, inset=0.0, radius=0.225):
    """Logo on a rounded square, inset by a fraction of the canvas."""
    big = size * 4
    pad = round(big * inset)
    inner = big - 2 * pad
    canvas = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    mask = Image.new('L', (inner, inner), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, inner - 1, inner - 1), radius=round(inner * radius), fill=255)
    canvas.paste(src.resize((inner, inner), Image.LANCZOS), (pad, pad), mask)
    return canvas.resize((size, size), Image.LANCZOS)

# iOS: full-bleed squares, no alpha (iOS rounds them itself).
for p in glob.glob('ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png'):
    n = Image.open(p).size[0]
    square(n).save(p, optimize=True)

# macOS: rounded square inset like the existing icons (100/1024, r 185/824).
for p in glob.glob('macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png'):
    n = Image.open(p).size[0]
    rounded(n, inset=100 / 1024, radius=185 / 824).save(p, optimize=True)

# Android launcher: full-size rounded square (r 29/192).
for p in glob.glob('android/app/src/main/res/mipmap-*/ic_launcher.png'):
    n = Image.open(p).size[0]
    rounded(n, radius=29 / 192).save(p, optimize=True)

# Web: plain and maskable (full bleed).
for n in (192, 512):
    square(n).save(f'web/icons/Icon-{n}.png', optimize=True)
    square(n).convert('RGBA').save(f'web/icons/Icon-maskable-{n}.png', optimize=True)
fav = Image.open('web/favicon.png').size[0]
rounded(fav, radius=0.2).save('web/favicon.png', optimize=True)

# Linux: rounded square inset like the existing one (25/256, r 40/206).
rounded(256, inset=25 / 256, radius=40 / 206).save('linux/packaging/jellybox.png', optimize=True)

# Windows .ico with the same sizes as before.
ico = rounded(256, radius=0.2)
ico.save('windows/runner/resources/app_icon.ico',
         sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

# Home-screen widgets: iOS clips its own corners, Android doesn't.
for scale, n in [(1, 128), (2, 256), (3, 384)]:
    square(n).save(
        f'ios/NowPlayingWidget/Assets.xcassets/Logo.imageset/logo@{scale}x.png',
        optimize=True)
os.makedirs('android/app/src/main/res/drawable-nodpi', exist_ok=True)
rounded(384, radius=0.225).save(
    'android/app/src/main/res/drawable-nodpi/ic_widget_logo.png', optimize=True)

# In-app logo.
rounded(512, radius=0.225).save('assets/images/puddingcup_logo.png', optimize=True)
print('done')
