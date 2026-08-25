#!/usr/bin/env python3
"""레퍼런스(Taur 스크린샷) 구도로 지형을 짜서 layout/terrain_edit.json 을 굽는다.

구도
  · 화면 **왼쪽 위**가 높은 고원 — 성이 그 위에 앉는다 (레퍼런스의 어두운 절벽 덩어리)
  · 화면 **오른쪽 아래**는 낮고 트인 벌판 — 벌레가 몰려오는 쪽 (레퍼런스의 주황 마을터)
  · 둘 사이를 **비스듬한 절벽**이 가르고, 그 절벽을 **지그재그 비탈길**이 하나 뚫고 올라간다
  · 절벽 중턱에 **선반(shelf)** 을 하나 둬서 절벽이 한 장의 벽으로 보이지 않게 한다

좌표는 전부 **화면 기준**(레이아웃 템플릿과 같은 축). 저장 격자는 월드 기준이라 45도 변환해서 쓴다.

python3 tools/make_terrain.py
"""
import json
import math
import os

CELL = 4.0          # scripts/ground.gd 의 CELL 과 같아야 한다
HALF = 160.0        # 〃 HALF
STEP = 2.0          # 〃 STEP (계단 한 칸)
VIEW_YAW = 45.0

N = int(HALF * 2.0 / CELL) + 1

TOP = 8.0           # 고원 높이 = 계단 4칸
SHELF = 4.0         # 중턱 선반 높이 = 2칸

BASE = (-25.0, -25.0)
BASE_PAD = 13.0     # 성 앞마당 (평평)

# 고원과 벌판을 가르는 경계선. 이 선의 **왼쪽 위**가 고원이다.
# ⚠️ 처음엔 성이 경계에서 10유닛밖에 안 떨어져 있어서, 아래 선반 띠에 성이 걸려
#    고원 위가 아니라 중턱에 놓였다. 성은 경계에서 **30유닛 넘게** 안쪽이어야 한다.
EDGE_A = (-80.0, 34.0)
EDGE_B = (56.0, -30.0)
## ⚠️ 이 값이 곧 "절벽이냐 비탈이냐"를 정한다. 7 로 뒀더니 8유닛 낙차가 14유닛에 걸쳐
##    퍼져서, 길찾기 격자(4유닛) 기준으로는 한 칸에 2씩 오르는 **계단**이 됐고 벌레가
##    절벽을 그냥 걸어 올라갔다 (길찾기 검증에서 잡힘 — 닿는 칸 100%).
##    낙차가 한두 칸 안에서 끝나야 길찾기가 벽으로 인식한다.
EDGE_SOFT = 1.5

# 벌판에서 고원 위 성까지 올라가는 비탈길 (지그재그, 꺾임 3번).
# 앞의 두 점은 벌판(평지)이고, 경계를 넘은 뒤부터 고원을 파고들며 올라간다.
## ⚠️ 비탈길을 **지도 한가운데**로 내면 우회가 안 생긴다. 아래쪽 스폰에서 성으로 가는
##    직선이 비탈길을 거의 그대로 타서, 길찾기 검증에서 우회 1.03배(=사실상 직진)가 나왔다.
##    올라가는 구간을 **오른쪽으로 밀어야** 아래쪽에서 온 벌레가 오른쪽으로 돌아가게 된다.
RAMP = [(70.0, 22.0), (40.0, 6.0), (18.0, -14.0), (-8.0, -30.0), BASE]
## 길이 평지에서 출발해 **후반부에서** 고원 높이까지 오르게 하는 구간 (진행도 0~1).
RAMP_RISE = (0.38, 1.0)
RAMP_HALF = 9.0     # 길 반폭
RAMP_SOFT = 5.0     # 길 어깨 (여기서 길과 절벽이 이어진다)

# 중턱 선반 — 절벽 **아래쪽(벌판 쪽)** 에 붙는 한 단. 절벽이 한 장의 벽으로 보이지 않게
# 중간 높이를 하나 끼워 넣는다. ⚠️ 고원 안쪽에 넣었더니 고원을 가르는 도랑이 됐다.
SHELF_BAND = (3.0, 15.0)    # 경계선에서 벌판 쪽으로 이만큼 떨어진 띠


def smoothstep(a, b, x):
    if a == b:
        return 0.0 if x < a else 1.0
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def seg_dist(p, a, b):
    ax, az = a
    bx, bz = b
    vx, vz = bx - ax, bz - az
    l2 = vx * vx + vz * vz
    t = 0.0 if l2 < 1e-6 else max(0.0, min(1.0, ((p[0] - ax) * vx + (p[1] - az) * vz) / l2))
    cx, cz = ax + vx * t, az + vz * t
    return math.hypot(p[0] - cx, p[1] - cz), t


def edge_side(p):
    """경계선에서의 부호 있는 거리. 음수 = 고원 쪽, 양수 = 벌판 쪽."""
    ax, az = EDGE_A
    bx, bz = EDGE_B
    vx, vz = bx - ax, bz - az
    n = math.hypot(vx, vz)
    # 왼쪽 법선(-vz, vx) 기준 부호
    return ((p[0] - ax) * (-vz) + (p[1] - az) * vx) / n


def ramp_profile(p):
    """비탈길 위에서의 (거리, 그 자리 바닥 높이). 길 밖이면 dist 가 크다."""
    best = (1e9, 0.0)
    # 구간별 누적 길이로 진행도를 재야 길이가 다른 구간에서도 경사가 일정하다
    lens = [math.dist(RAMP[i], RAMP[i + 1]) for i in range(len(RAMP) - 1)]
    total = sum(lens)
    acc = 0.0
    for i in range(len(RAMP) - 1):
        d, t = seg_dist(p, RAMP[i], RAMP[i + 1])
        if d < best[0]:
            prog = (acc + lens[i] * t) / total
            best = (d, TOP * smoothstep(RAMP_RISE[0], RAMP_RISE[1], prog))
        acc += lens[i]
    return best


def height(p):
    # 1) 고원 — 경계선 왼쪽 위가 높다
    h = TOP * smoothstep(EDGE_SOFT, -EDGE_SOFT, edge_side(p))

    # 2) 중턱 선반 — 절벽 아래 벌판 쪽에 한 단을 끼워 절벽을 두 단으로 쪼갠다
    s = edge_side(p)
    if SHELF_BAND[0] < s < SHELF_BAND[1]:
        band = smoothstep(SHELF_BAND[0], SHELF_BAND[0] + 3.0, s) * \
            smoothstep(SHELF_BAND[1], SHELF_BAND[1] - 4.0, s)
        h = max(h, SHELF * band)

    # 3) 비탈길 — 고원을 파고 들어가 벌판에서 성까지 이어진다
    d, rh = ramp_profile(p)
    if d < RAMP_HALF + RAMP_SOFT:
        w = smoothstep(RAMP_HALF + RAMP_SOFT, RAMP_HALF, d)
        h = h * (1.0 - w) + min(h, rh) * w

    # 4) 성 앞마당 — 고원 꼭대기에서 평평하게
    bd = math.dist(p, BASE)
    if bd < BASE_PAD + 6.0:
        w = smoothstep(BASE_PAD + 6.0, BASE_PAD, bd)
        h = h * (1.0 - w) + TOP * w
    return h


def to_screen(wx, wz):
    t = math.radians(-VIEW_YAW)
    return (math.cos(t) * wx + math.sin(t) * wz,
            -math.sin(t) * wx + math.cos(t) * wz)


def smooth_mask(p):
    """비탈길 마스크 — 길 위는 계단화를 끄고 매끈한 비탈로 둔다.
    이게 있어야 '길로만 올라올 수 있는 지형'이 성립한다 (계단은 밟고 오를 수 있으므로)."""
    d, _ = ramp_profile(p)
    return smoothstep(RAMP_HALF + RAMP_SOFT, RAMP_HALF - 2.0, d)


def main():
    out = []
    mask = []
    for gz in range(N):
        for gx in range(N):
            wx = gx * CELL - HALF
            wz = gz * CELL - HALF
            p = to_screen(wx, wz)
            out.append(round(height(p), 2))
            mask.append(round(smooth_mask(p), 2))
    path = os.path.join(os.path.dirname(__file__), "..", "layout", "terrain_edit.json")
    with open(path, "w") as f:
        json.dump({"cell": CELL, "half": HALF, "n": N, "h": out, "s": mask}, f)
    touched = sum(1 for v in out if abs(v) > 0.01)
    ramped = sum(1 for v in mask if v > 0.5)
    print(f"{N}x{N} 격자 / 손댄 칸 {touched} / 비탈길 칸 {ramped} / "
          f"최고 {max(out):.1f} 최저 {min(out):.1f}")


if __name__ == "__main__":
    main()
