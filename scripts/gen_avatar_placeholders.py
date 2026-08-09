#!/usr/bin/env python3
import math
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

STATES = {
    "idle":     ("待機",   (139, 108, 255), (34, 24, 70)),
    "thinking": ("思考中", (255, 190, 92),  (58, 34, 16)),
    "talking":  ("說話中", (92, 214, 255),  (16, 38, 60)),
    "happy":    ("開心",   (255, 150, 170), (58, 22, 34)),
    "shy":      ("害羞",   (255, 140, 184), (52, 20, 44)),
    "sad":      ("難過",   (112, 132, 196), (14, 17, 40)),
    "angry":    ("生氣",   (255, 112, 92),  (58, 18, 14)),
    "excited":  ("興奮",   (255, 205, 82),  (58, 42, 12)),
}

W, H = 720, 1280
FPS = 30
DURATION = 4.0
FRAMES = int(FPS * DURATION)
LABEL_SIZE = 118
SUB_SIZE = 40

FONT_PATHS = [
    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
]


def load_font(size):
    for path in FONT_PATHS:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                continue
    return ImageFont.load_default(size)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def draw_text(draw, x, y, text, font, fill):
    bbox = draw.textbbox((0, 0), text, font=font)
    draw.text((x - bbox[0], y - bbox[1]), text, font=font, fill=fill)
    return bbox[2] - bbox[0], bbox[3] - bbox[1]


def render_frame(label, english, top, bottom, t):
    grad = Image.new("RGB", (1, H))
    for y in range(H):
        grad.putpixel((0, y), lerp(top, bottom, y / (H - 1)))
    img = grad.resize((W, H))

    cx = W // 2
    wave = math.sin(2 * math.pi * t / DURATION * 0.6)
    orb_cy = int(H * 0.40 + wave * 22)
    orb_r = int(W * 0.34)

    draw = ImageDraw.Draw(img, "RGBA")
    for i in range(44):
        r = int(orb_r * (1.35 - i / 44))
        alpha = int(56 * (1 - i / 44))
        draw.ellipse((cx - r, orb_cy - r, cx + r, orb_cy + r), fill=(255, 255, 255, alpha))

    pulse = 0.5 + 0.5 * math.sin(2 * math.pi * t / DURATION * 0.8)
    draw.ellipse(
        (cx - orb_r, orb_cy - orb_r, cx + orb_r, orb_cy + orb_r),
        outline=(255, 255, 255, int(140 + 70 * pulse)),
        width=6,
    )

    label_font = load_font(LABEL_SIZE)
    sub_font = load_font(SUB_SIZE)
    _, lh = draw_text(draw, cx, int(H * 0.70), label, label_font, (255, 255, 255, 240))
    draw_text(draw, cx, int(H * 0.70) + int(lh * 0.55), english, sub_font, (255, 255, 255, 150))
    return img


def encode_clip(label, english, top, bottom, out_path):
    cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS),
        "-i", "-", "-an", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "26",
        "-movflags", "+faststart", out_path,
    ]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for i in range(FRAMES):
        t = i / FPS
        proc.stdin.write(render_frame(label, english, top, bottom, t).tobytes())
    proc.stdin.close()
    return proc.wait()


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "assets/videos"
    os.makedirs(out_dir, exist_ok=True)
    for state_id, (label, top, bottom) in STATES.items():
        out_path = os.path.join(out_dir, f"placeholder-{state_id}.mp4")
        rc = encode_clip(label, state_id.upper(), top, bottom, out_path)
        print(f"{out_path}: {'ok' if rc == 0 else 'FAILED'}")
        if rc != 0:
            sys.exit(rc)


if __name__ == "__main__":
    main()
