#!/usr/bin/env python3
"""
Generate a macOS App Icon for "Lightning".
Renders a 1024x1024 master icon and generates all required iconset sizes,
then compiles them into Lightning.icns via iconutil.
"""

import math
import os
import subprocess
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

def create_master_icon(size=1024):
    scale = 2  # Super-sample at 2x (2048x2048) for ultra-sharp anti-aliased curves
    w = size * scale
    h = size * scale

    # Master RGBA image
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))

    # Squircle parameters in 1024 space (scaled by `scale`)
    # Standard macOS icon grid: 824x824 icon placed in 1024x1024 canvas
    box_x0 = 100 * scale
    box_y0 = 100 * scale
    box_x1 = 924 * scale
    box_y1 = 924 * scale
    box_w = box_x1 - box_x0
    box_h = box_y1 - box_y0
    radius = int(185 * scale)

    # 1. Cast shadow onto canvas underneath squircle
    shadow_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow_layer)

    # Ambient deep shadow (dy = +28px, large blur)
    amb_dy = int(24 * scale)
    s_draw.rounded_rectangle(
        [box_x0, box_y0 + amb_dy, box_x1, box_y1 + amb_dy],
        radius=radius,
        fill=(0, 0, 0, 110)
    )
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(int(26 * scale)))

    # Direct contact shadow (dy = +10px, sharper blur)
    contact_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    c_draw = ImageDraw.Draw(contact_layer)
    contact_dy = int(10 * scale)
    c_draw.rounded_rectangle(
        [box_x0, box_y0 + contact_dy, box_x1, box_y1 + contact_dy],
        radius=radius,
        fill=(0, 0, 0, 140)
    )
    contact_layer = contact_layer.filter(ImageFilter.GaussianBlur(int(10 * scale)))

    # Composite shadows
    img = Image.alpha_composite(img, shadow_layer)
    img = Image.alpha_composite(img, contact_layer)

    # 2. Render Squircle Background Surface
    squircle_mask = Image.new("L", (w, h), 0)
    mask_draw = ImageDraw.Draw(squircle_mask)
    mask_draw.rounded_rectangle(
        [box_x0, box_y0, box_x1, box_y1],
        radius=radius,
        fill=255
    )

    # Background gradient: Deep space navy / midnight slate
    # Gradient from (18, 22, 34) at top-left to (8, 10, 18) at bottom-right
    bg = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    bg_draw = ImageDraw.Draw(bg)

    for y in range(box_y0, box_y1):
        t = (y - box_y0) / float(box_h)
        # Deep space gradient
        r = int(22 * (1.0 - t) + 9 * t)
        g = int(28 * (1.0 - t) + 12 * t)
        b = int(45 * (1.0 - t) + 22 * t)
        bg_draw.line([(box_x0, y), (box_x1, y)], fill=(r, g, b, 255))

    # Radial ambient energy glow behind the bolt (centered at 512, 500)
    cx = 512 * scale
    cy = 500 * scale
    glow_bg = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_bg)
    glow_radius = int(320 * scale)

    # Soft radial gradient for electric backdrop
    for r_i in range(glow_radius, 0, -int(4 * scale)):
        t_glow = 1.0 - (r_i / float(glow_radius))
        alpha = int(75 * (t_glow ** 2.2))
        glow_draw.ellipse(
            [cx - r_i, cy - r_i, cx + r_i, cy + r_i],
            fill=(40, 70, 160, alpha)
        )
    glow_bg = glow_bg.filter(ImageFilter.GaussianBlur(int(16 * scale)))
    bg = Image.alpha_composite(bg, glow_bg)

    # Background subtle tech speed accent lines / code brackets
    tech_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    tech_draw = ImageDraw.Draw(tech_layer)
    bracket_color = (255, 255, 255, 18)
    line_w = int(6 * scale)

    # Left chevron `<` hint
    tech_draw.line(
        [(240 * scale, 430 * scale), (190 * scale, 500 * scale)],
        fill=bracket_color,
        width=line_w
    )
    tech_draw.line(
        [(190 * scale, 500 * scale), (240 * scale, 570 * scale)],
        fill=bracket_color,
        width=line_w
    )

    # Right chevron `>` hint
    tech_draw.line(
        [(784 * scale, 430 * scale), (834 * scale, 500 * scale)],
        fill=bracket_color,
        width=line_w
    )
    tech_draw.line(
        [(834 * scale, 500 * scale), (784 * scale, 570 * scale)],
        fill=bracket_color,
        width=line_w
    )

    bg = Image.alpha_composite(bg, tech_layer)

    # 3. Outer rim highlight / stroke on squircle
    rim_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    rim_draw = ImageDraw.Draw(rim_layer)
    rim_stroke_w = int(2.5 * scale)
    rim_draw.rounded_rectangle(
        [box_x0, box_y0, box_x1, box_y1],
        radius=radius,
        outline=(255, 255, 255, 38),
        width=rim_stroke_w
    )
    bg = Image.alpha_composite(bg, rim_layer)

    # 4. Lightning Bolt Geometry
    # Defined in 1024 coordinate space:
    # Sharp, iconic, aerodynamic bolt:
    # P0: Top point
    # P1: Upper-left notch
    # P2: Inner jog left
    # P3: Bottom dagger tip
    # P4: Right edge jog
    # P5: Inner jog right
    pts_1024 = {
        "P0": (585, 210),   # Top sharp tip
        "P1": (390, 490),   # Left outer point
        "P2": (480, 490),   # Left inner notch
        "P3": (430, 810),   # Bottom dagger tip
        "P4": (634, 435),   # Right outer point
        "P5": (544, 435),   # Right inner notch
        "C":  (512, 462),   # Central ridge inflection point
    }
    # Scale coordinates
    pts = {k: (v[0] * scale, v[1] * scale) for k, v in pts_1024.items()}

    full_polygon = [pts["P0"], pts["P1"], pts["P2"], pts["P3"], pts["P4"], pts["P5"]]
    left_facet  = [pts["P0"], pts["P1"], pts["P2"], pts["C"]]
    bottom_left = [pts["P2"], pts["P3"], pts["C"]]
    right_facet = [pts["P0"], pts["C"], pts["P4"], pts["P5"]]
    bottom_right= [pts["C"], pts["P3"], pts["P4"]]

    # 4a. Ambient electric bloom & glow beneath the bolt
    glow_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    glow_bolt_draw = ImageDraw.Draw(glow_layer)

    # Wide diffuse electric gold/amber aura
    glow_bolt_draw.polygon(full_polygon, fill=(255, 175, 0, 200))
    wide_glow = glow_layer.filter(ImageFilter.GaussianBlur(int(42 * scale)))

    # Intense electric core bloom
    intense_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    intense_draw = ImageDraw.Draw(intense_layer)
    intense_draw.polygon(full_polygon, fill=(255, 225, 60, 230))
    intense_glow = intense_layer.filter(ImageFilter.GaussianBlur(int(18 * scale)))

    bg = Image.alpha_composite(bg, wide_glow)
    bg = Image.alpha_composite(bg, intense_glow)

    # 4b. Draw Chiseled 3D Facets of the Bolt
    bolt_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    b_draw = ImageDraw.Draw(bolt_layer)

    # Left upper facet: Lit by top-left key light (Brilliant Electric Gold -> Radiant Yellow)
    # Gradient rendering using vertical stripes clipped to polygon
    poly_mask_left = Image.new("L", (w, h), 0)
    ImageDraw.Draw(poly_mask_left).polygon(left_facet, fill=255)
    ImageDraw.Draw(poly_mask_left).polygon(bottom_left, fill=255)

    left_surf = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ls_draw = ImageDraw.Draw(left_surf)
    for y in range(int(pts["P0"][1]), int(pts["P3"][1]) + 1):
        t = (y - pts["P0"][1]) / float(pts["P3"][1] - pts["P0"][1])
        # Warm golden highlight
        r = int(255)
        g = int(248 * (1.0 - t) + 215 * t)
        b = int(120 * (1.0 - t) + 30 * t)
        ls_draw.line([(0, y), (w, y)], fill=(r, g, b, 255))
    left_surf.putalpha(poly_mask_left)
    bolt_layer = Image.alpha_composite(bolt_layer, left_surf)

    # Right facet: Beveled shaded facet (Deep Electric Amber -> Tangy Orange)
    poly_mask_right = Image.new("L", (w, h), 0)
    ImageDraw.Draw(poly_mask_right).polygon(right_facet, fill=255)
    ImageDraw.Draw(poly_mask_right).polygon(bottom_right, fill=255)

    right_surf = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    rs_draw = ImageDraw.Draw(right_surf)
    for y in range(int(pts["P0"][1]), int(pts["P3"][1]) + 1):
        t = (y - pts["P0"][1]) / float(pts["P3"][1] - pts["P0"][1])
        # Rich deep amber-orange shadow facet
        r = int(255 * (1.0 - t) + 245 * t)
        g = int(195 * (1.0 - t) + 130 * t)
        b = int(40 * (1.0 - t) + 10 * t)
        rs_draw.line([(0, y), (w, y)], fill=(r, g, b, 255))
    right_surf.putalpha(poly_mask_right)
    bolt_layer = Image.alpha_composite(bolt_layer, right_surf)

    # 4c. Center Ridge Razor Highlight (White-Hot Core Line)
    ridge_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ridge_draw = ImageDraw.Draw(ridge_layer)
    ridge_w = int(3.5 * scale)

    # Draw white highlight along ridge P0 -> C -> P3
    ridge_draw.line([pts["P0"], pts["C"]], fill=(255, 255, 255, 240), width=ridge_w)
    ridge_draw.line([pts["C"], pts["P3"]], fill=(255, 255, 255, 240), width=ridge_w)
    ridge_layer = ridge_layer.filter(ImageFilter.GaussianBlur(int(1.2 * scale)))
    bolt_layer = Image.alpha_composite(bolt_layer, ridge_layer)

    # 4d. Crisp outer border around the bolt for punchy contrast
    bolt_outline = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    bo_draw = ImageDraw.Draw(bolt_outline)
    bo_draw.polygon(full_polygon, outline=(255, 255, 255, 180), width=int(1.5 * scale))
    bolt_layer = Image.alpha_composite(bolt_layer, bolt_outline)

    # Composite bolt over squircle background
    bg = Image.alpha_composite(bg, bolt_layer)

    # 5. Top Glass/Gloss Reflection on Squircle Upper Edge
    glass_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    g_draw = ImageDraw.Draw(glass_layer)
    glass_h = int(160 * scale)
    for y in range(box_y0, box_y0 + glass_h):
        t = (y - box_y0) / float(glass_h)
        alpha = int(35 * (1.0 - t) ** 1.5)
        g_draw.line([(box_x0, y), (box_x1, y)], fill=(255, 255, 255, alpha))

    # Mask gloss to squircle shape
    glass_layer.putalpha(Image.composite(glass_layer.getchannel("A"), Image.new("L", (w, h), 0), squircle_mask))
    bg = Image.alpha_composite(bg, glass_layer)

    # Mask entire squircle background with rounded squircle mask
    bg.putalpha(squircle_mask)

    # Merge squircle onto canvas with drop shadows
    final_canvas = Image.alpha_composite(img, bg)

    # Downsample using high-quality Lanczos resampling to requested target size (1024x1024)
    master = final_canvas.resize((size, size), Image.Resampling.LANCZOS)
    return master

def main():
    os.makedirs("assets/icons/lightning.iconset", exist_ok=True)
    master_png = "assets/icons/lightning_1024.png"
    print("⚡ Generating master 1024x1024 icon for Lightning...")
    master = create_master_icon(1024)
    master.save(master_png, "PNG")
    print(f"   Saved master icon to {master_png}")

    # Standard macOS icon sizes for .iconset
    icon_specs = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    iconset_dir = "assets/icons/lightning.iconset"
    for filename, sz in icon_specs:
        out_path = os.path.join(iconset_dir, filename)
        resized = master.resize((sz, sz), Image.Resampling.LANCZOS)
        resized.save(out_path, "PNG")
        print(f"   Generated {filename} ({sz}x{sz})")

    icns_path = "assets/icons/Lightning.icns"
    print(f"⚡ Compiling {iconset_dir} -> {icns_path} via iconutil...")
    res = subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", icns_path], capture_output=True, text=True)
    if res.returncode != 0:
        print(f"Error compiling icns: {res.stderr}", file=sys.stderr)
        sys.exit(res.returncode)

    print(f"✅ Successfully built {icns_path} ({os.path.getsize(icns_path)} bytes)")

if __name__ == "__main__":
    main()
