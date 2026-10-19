#!/usr/bin/env python3
# ==============================================================================
# AllGlider Live Linux - Boot Splash (Plymouth) Asset Generator
# Generates:
#   1. OpenGlider watermark.png ("Powered by OpenGlider...")
#   2. AllGlider bgrt-fallback.png (Center badge: AllGlider Logo + "AllGlider Linux")
#   3. AllGlider background.png (1920x1080 centered background)
# ==============================================================================
import os
import subprocess
from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO_ROOT, "branding", "plymouth")
os.makedirs(OUT_DIR, exist_ok=True)

OG_SVG = "/home/alexander/Projects/openglider/server-aspnet/src/AllGlider.Server/wwwroot/images/openglider.svg"
AG_SVG = os.path.join(REPO_ROOT, "branding", "icons", "allglider.svg")

FONT_REG = "/usr/share/fonts/abattis-cantarell-fonts/Cantarell-Regular.otf"
FONT_BOLD = "/usr/share/fonts/abattis-cantarell-fonts/Cantarell-Bold.otf"

print("=== [1/3] Generating OpenGlider 'Powered by OpenGlider...' Watermark ===")
subprocess.run(["magick", "-background", "none", OG_SVG, "-resize", "42x42", "/tmp/og-watermark-icon.png"], check=True)
og_icon = Image.open("/tmp/og-watermark-icon.png")

wm_w, wm_h = 360, 52
watermark = Image.new("RGBA", (wm_w, wm_h), (0, 0, 0, 0))
watermark.paste(og_icon, (4, 5), og_icon)

draw_wm = ImageDraw.Draw(watermark)
font_wm = ImageFont.truetype(FONT_REG, 21)
draw_wm.text((56, 13), "Powered by OpenGlider...", font=font_wm, fill=(235, 240, 250, 230))
watermark.save(os.path.join(OUT_DIR, "watermark.png"))
print(f"Saved: {OUT_DIR}/watermark.png ({watermark.size})")

print("=== [2/3] Generating Center AllGlider Linux Badge (bgrt-fallback.png) ===")
subprocess.run(["magick", "-background", "none", AG_SVG, "-resize", "220x220", "/tmp/ag-badge-icon.png"], check=True)
ag_icon = Image.open("/tmp/ag-badge-icon.png")

bw, bh = 420, 320
badge = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
bx = (bw - ag_icon.width) // 2
by = 10
badge.paste(ag_icon, (bx, by), ag_icon)

draw_b = ImageDraw.Draw(badge)
font_ag = ImageFont.truetype(FONT_BOLD, 34)
text = "AllGlider Linux"
bbox = font_ag.getbbox(text)
tw = bbox[2] - bbox[0]
tx = (bw - tw) // 2
ty = by + ag_icon.height + 18
draw_b.text((tx, ty), text, font=font_ag, fill=(255, 255, 255, 255))
badge.save(os.path.join(OUT_DIR, "bgrt-fallback.png"))
print(f"Saved: {OUT_DIR}/bgrt-fallback.png ({badge.size})")

print("=== [3/3] Generating 1920x1080 Splash Background (background.png) ===")
subprocess.run(["magick", "-background", "none", AG_SVG, "-resize", "260x260", "/tmp/ag-bg-icon.png"], check=True)
ag_bg_icon = Image.open("/tmp/ag-bg-icon.png")

bg = Image.new("RGBA", (1920, 1080), (0, 0, 0, 255))
cx = 1920 // 2
bg_logo_x = cx - ag_bg_icon.width // 2
bg_logo_y = 280
bg.paste(ag_bg_icon, (bg_logo_x, bg_logo_y), ag_bg_icon)

draw_bg = ImageDraw.Draw(bg)
font_bg = ImageFont.truetype(FONT_BOLD, 40)
bbox_bg = font_bg.getbbox(text)
tw_bg = bbox_bg[2] - bbox_bg[0]
draw_bg.text((cx - tw_bg // 2, bg_logo_y + ag_bg_icon.height + 22), text, font=font_bg, fill=(255, 255, 255, 255))
bg.save(os.path.join(OUT_DIR, "background.png"))
print(f"Saved: {OUT_DIR}/background.png ({bg.size})")

print("=== Plymouth Assets Generation Complete ===")
