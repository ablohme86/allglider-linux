#!/usr/bin/env python3
# ==============================================================================
# AllGlider Live Linux - Desktop Wallpaper & Splash Generator
# Creates a gradient background matching the AllGlider night sky (#1c1040 -> #090514),
# with the centered AllGlider logo + "AllGlider Linux", and bottom OpenGlider watermark.
# ==============================================================================
import os
import subprocess
from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WP_OUT = os.path.join(REPO_ROOT, "branding", "wallpapers", "allglider-wallpaper.png")
SPLASH_OUT = os.path.join(REPO_ROOT, "branding", "plymouth", "background.png")
os.makedirs(os.path.dirname(WP_OUT), exist_ok=True)
os.makedirs(os.path.dirname(SPLASH_OUT), exist_ok=True)

width, height = 1920, 1080
cx, cy = width // 2, height // 2

print("=== Generating 1920x1080 Radial Gradient Background ===")
# Generate deep cosmic indigo radial gradient using ImageMagick
grad_tmp = "/tmp/allglider-radial-gradient.png"
subprocess.run([
    "magick", "-size", f"{width}x{height}",
    "radial-gradient:#201248-#090514",
    grad_tmp
], check=True)

bg = Image.open(grad_tmp).convert("RGBA")

print("=== Rendering AllGlider Logo ===")
ag_svg = os.path.join(REPO_ROOT, "branding", "icons", "allglider.svg")
logo_tmp = "/tmp/allglider-logo-280.png"
subprocess.run(["magick", "-background", "none", ag_svg, "-resize", "280x280", logo_tmp], check=True)
ag_logo = Image.open(logo_tmp)

logo_x = cx - ag_logo.width // 2
logo_y = 260
bg.paste(ag_logo, (logo_x, logo_y), ag_logo)

print("=== Drawing 'AllGlider Linux' Typography ===")
draw = ImageDraw.Draw(bg)
font_path = "/usr/share/fonts/abattis-cantarell-fonts/Cantarell-Bold.otf"
font = ImageFont.truetype(font_path, 42)
text = "AllGlider Linux"
bbox = font.getbbox(text)
tw = bbox[2] - bbox[0]
text_x = cx - tw // 2
text_y = logo_y + ag_logo.height + 22
draw.text((text_x, text_y), text, font=font, fill=(255, 255, 255, 255))

# Save Plymouth boot splash background WITHOUT watermark (Plymouth renders watermark dynamically at bottom)
bg.save(SPLASH_OUT)
print(f"Saved Plymouth Splash Background: {SPLASH_OUT}")

print("=== Pasting OpenGlider 'Powered by OpenGlider...' Watermark at Bottom of Desktop Wallpaper ===")
wm_path = os.path.join(REPO_ROOT, "branding", "plymouth", "watermark.png")
if os.path.exists(wm_path):
    wm = Image.open(wm_path)
    wm_x = cx - wm.width // 2
    wm_y = height - wm.height - 40
    bg.paste(wm, (wm_x, wm_y), wm)

# Save desktop wallpaper
bg.convert("RGB").save(WP_OUT, quality=96)
print(f"Saved Desktop Wallpaper: {WP_OUT}")

# Create fallback symlink / copies for Xfce & LightDM
for name in ["default.png", "allglider-wallpaper.jpg"]:
    dest = os.path.join(REPO_ROOT, "branding", "wallpapers", name)
    bg.convert("RGB").save(dest, quality=96)

print("=== Wallpaper and Splash Generation Complete ===")
