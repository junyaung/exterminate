#!/usr/bin/env python3
"""레이아웃 맵 템플릿 생성기.

유저가 그림으로 지형을 지시하기 위한 캔버스를 굽는다 (유저 요청 2026-08-16:
"글보다 그림이 나을 것 같은데").

규칙
  · 캔버스 축 = **화면 축**이다. 게임에서 보이는 그대로 x 는 오른쪽, z 는 아래.
    (월드 축은 카메라 yaw 45도만큼 돌아가 있지만, 그 변환은 게임이 알아서 한다)
  · 1 유닛 = PX_PER_UNIT 픽셀.
  · 안내선(회색 계열)은 **임포터가 전부 무시한다**. 그 위에 그냥 칠하면 된다.
  · 임포터가 알아보는 건 legend.py 의 정확한 색뿐이다.

python3 tools/make_layout_template.py
"""
from PIL import Image, ImageDraw, ImageFont
import math
import os

PX = 3                      # 1 유닛당 픽셀
X_HALF, Z_HALF = 120, 85    # 캔버스가 덮는 화면 범위 (유닛)
W, H = X_HALF * 2 * PX, Z_HALF * 2 * PX

# 화면에 실제로 보이는 지면 (카메라 size 75.5, 피치 -50 기준)
VIEW_X, VIEW_Z = 67, 49

# 게임이 쓰는 값 (main.gd / scatter.gd 와 같아야 한다)
BASE_SCREEN = (-25.0, -25.0)  # 유저 지시 2026-08-16 (월드 (-35.355, 0, 0))
BASE_KEEP = 26.0
LANE_HALF = 16.0
ZONE_PAD = 8.0
SPAWN_ZONES = [
    (72.98, 90.60, 10.07, 40.27),
    (-20.13, 40.27, 57.88, 75.50),
]

# --- 안내선 색 (임포터가 무시하는 회색 계열) ---
C_BG = (59, 59, 59)
C_KEEP = (106, 106, 106)   # 높은 것(나무·풀·돌멩이) 금지. 낮은 것(잎·자갈)은 칠해도 된다
C_GRID = (74, 74, 74)
C_AXIS = (138, 138, 138)
C_FRAME = (154, 154, 154)

# --- 임포터가 알아보는 색 (칠하는 색) ---
# ⚠️ 라벨은 **영어로만** 적는다 — PIL 기본 폰트에 한글 글리프가 없어서 네모로 깨진다
#    (유저 지적 2026-08-16).
TERRAIN = [
    ("#734c44", "DAMP SOIL - dark base earth"),
    ("#c28569", "DRY SOIL - light patches"),
    ("#3e8948", "MOSS"),
    ("#265c42", "DEEP MOSS - shaded"),
    ("#bcad9f", "SAND - exposed ground"),
]
PROPS = [
    ("#ff0000", "TREE TRUNK - one dot = one trunk"),
    ("#ff8800", "TWIG - one dot = one twig"),
    ("#ffee00", "DRY LEAVES - fills painted area"),
    ("#00e5ff", "GRAVEL - fills painted area"),
    ("#ff00ff", "GRASS TUFT - fills painted area"),
    ("#ffffff", "PEBBLE - fills painted area"),
    ("#000000", "KEEP CLEAR - place nothing here"),
]


def to_px(x, z):
    return (int((x + X_HALF) * PX), int((z + Z_HALF) * PX))


def build_canvas(path):
    img = Image.new("RGB", (W, H), C_BG)
    d = ImageDraw.Draw(img)

    # 20유닛 격자
    for u in range(-X_HALF, X_HALF + 1, 20):
        d.line([to_px(u, -Z_HALF), to_px(u, Z_HALF)], fill=C_GRID)
    for u in range(-Z_HALF, Z_HALF + 1, 20):
        d.line([to_px(-X_HALF, u), to_px(X_HALF, u)], fill=C_GRID)
    # 원점 축
    d.line([to_px(0, -Z_HALF), to_px(0, Z_HALF)], fill=C_AXIS)
    d.line([to_px(-X_HALF, 0), to_px(X_HALF, 0)], fill=C_AXIS)

    # 비워둬야 할 곳: 기지 원 + 행군 통로 + 스폰 존
    lanes = []
    for (x0, x1, z0, z1) in SPAWN_ZONES:
        lanes += [((x0 + x1) / 2, (z0 + z1) / 2), (x0, z0), (x0, z1), (x1, z0), (x1, z1)]
    for lane in lanes:
        steps = 60
        for i in range(steps + 1):
            t = i / steps
            cx = BASE_SCREEN[0] + (lane[0] - BASE_SCREEN[0]) * t
            cz = BASE_SCREEN[1] + (lane[1] - BASE_SCREEN[1]) * t
            p0 = to_px(cx - LANE_HALF, cz - LANE_HALF)
            p1 = to_px(cx + LANE_HALF, cz + LANE_HALF)
            d.ellipse([p0, p1], fill=C_KEEP)
    p0 = to_px(BASE_SCREEN[0] - BASE_KEEP, BASE_SCREEN[1] - BASE_KEEP)
    p1 = to_px(BASE_SCREEN[0] + BASE_KEEP, BASE_SCREEN[1] + BASE_KEEP)
    d.ellipse([p0, p1], fill=C_KEEP)
    for (x0, x1, z0, z1) in SPAWN_ZONES:
        d.rectangle([to_px(x0 - ZONE_PAD, z0 - ZONE_PAD),
                     to_px(x1 + ZONE_PAD, z1 + ZONE_PAD)], fill=C_KEEP)

    # 성 자리 표시 (5×5)
    d.rectangle([to_px(BASE_SCREEN[0] - 2.5, BASE_SCREEN[1] - 2.5),
                 to_px(BASE_SCREEN[0] + 2.5, BASE_SCREEN[1] + 2.5)], outline=C_FRAME)

    # 통로 위에는 "낮은 것만" 이라는 표시 — 빗금을 그어 구분한다
    for i in range(-W, W, 14):
        d.line([(i, 0), (i + H, H)], fill=(122, 122, 122), width=1)
    # 빗금이 캔버스 전체에 그어졌으니 통로 밖은 다시 배경으로 덮는다
    mask = Image.new("RGB", (W, H), C_BG)
    md = ImageDraw.Draw(mask)
    for lane in lanes:
        steps = 60
        for i in range(steps + 1):
            t = i / steps
            cx = BASE_SCREEN[0] + (lane[0] - BASE_SCREEN[0]) * t
            cz = BASE_SCREEN[1] + (lane[1] - BASE_SCREEN[1]) * t
            md.ellipse([to_px(cx - LANE_HALF, cz - LANE_HALF),
                        to_px(cx + LANE_HALF, cz + LANE_HALF)], fill=(255, 255, 255))
    md.ellipse([to_px(BASE_SCREEN[0] - BASE_KEEP, BASE_SCREEN[1] - BASE_KEEP),
                to_px(BASE_SCREEN[0] + BASE_KEEP, BASE_SCREEN[1] + BASE_KEEP)],
               fill=(255, 255, 255))
    for (x0, x1, z0, z1) in SPAWN_ZONES:
        md.rectangle([to_px(x0 - ZONE_PAD, z0 - ZONE_PAD),
                      to_px(x1 + ZONE_PAD, z1 + ZONE_PAD)], fill=(255, 255, 255))
    img = Image.composite(img, Image.new("RGB", (W, H), C_BG),
                          mask.convert("L").point(lambda v: 255 if v > 200 else 0))
    d = ImageDraw.Draw(img)
    # 격자·축을 다시 얹는다 (위에서 덮였다)
    for u in range(-X_HALF, X_HALF + 1, 20):
        d.line([to_px(u, -Z_HALF), to_px(u, Z_HALF)], fill=C_GRID)
    for u in range(-Z_HALF, Z_HALF + 1, 20):
        d.line([to_px(-X_HALF, u), to_px(X_HALF, u)], fill=C_GRID)
    d.line([to_px(0, -Z_HALF), to_px(0, Z_HALF)], fill=C_AXIS)
    d.line([to_px(-X_HALF, 0), to_px(X_HALF, 0)], fill=C_AXIS)

    # 화면 프레임 (여기 안쪽이 실제로 보이는 범위)
    d.rectangle([to_px(-VIEW_X, -VIEW_Z), to_px(VIEW_X, VIEW_Z)], outline=C_FRAME, width=2)

    # 눈금 숫자
    for u in range(-100, 101, 20):
        d.text((to_px(u, 0)[0] + 2, to_px(0, 0)[1] + 2), str(u), fill=C_AXIS)
    for u in range(-80, 81, 20):
        d.text((to_px(0, 0)[0] + 2, to_px(0, u)[1] + 2), str(u), fill=C_AXIS)

    img.save(path)
    return img


def build_legend(path):
    rows = [("TERRAIN - paint as areas", None)] + \
           [(name, hexs) for hexs, name in TERRAIN] + \
           [("PROPS", None)] + \
           [(name, hexs) for hexs, name in PROPS] + \
           [("NOTE: paint with antialiasing OFF", None),
            ("Grey guide marks are ignored by the importer", None),
            ("Hatched area: low props only (leaves, gravel)", None)]
    try:
        font = ImageFont.load_default(17)
    except TypeError:
        font = ImageFont.load_default()
    rh, pad = 30, 14
    img = Image.new("RGB", (620, rh * len(rows) + pad * 2), (24, 24, 24))
    d = ImageDraw.Draw(img)
    for i, (name, hexs) in enumerate(rows):
        y = pad + i * rh
        if hexs:
            d.rectangle([pad, y + 4, pad + 46, y + 24], fill=hexs, outline=(90, 90, 90))
            d.text((pad + 60, y + 8), f"{hexs}   {name}", fill=(224, 224, 224), font=font)
        else:
            d.text((pad, y + 8), name, fill=(150, 150, 150), font=font)
    img.save(path)


if __name__ == "__main__":
    out = os.path.join(os.path.dirname(__file__), "..", "layout")
    os.makedirs(out, exist_ok=True)
    build_canvas(os.path.join(out, "layout_template.png"))
    build_legend(os.path.join(out, "layout_legend.png"))
    print(f"{W}x{H}px / 1유닛 = {PX}px / 화면범위 x±{X_HALF} z±{Z_HALF}")
