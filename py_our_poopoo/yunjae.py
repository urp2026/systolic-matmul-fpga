# =====================================================================
#  compute_golden.py
#   all_A.mem, all_B.mem을 읽어 numpy로 golden(정답) 행렬곱 계산
#   결과를 C_golden.mem 으로 저장 (tb가 이 파일과 하드웨어 결과를 비교)
# =====================================================================
import numpy as np

SIZE = 4

def s8(byte_val):
    """8비트 부호 정수 해석 (0x80~0xFF는 음수)"""
    return byte_val - 256 if byte_val >= 128 else byte_val

def load_mem(path):
    """한 줄 = 한 케이스(16 hex). signed 4x4 행렬 리스트로 반환"""
    mats = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            vals = [s8(int(x, 16)) for x in line.split()]
            mats.append(np.array(vals, dtype=np.int64).reshape(SIZE, SIZE))
    return mats

A_list = load_mem("cases/all_A.mem")
B_list = load_mem("cases/all_B.mem")
assert len(A_list) == len(B_list), "A, B 케이스 수 불일치"

# golden 계산 + 저장 (C[i][j]를 32비트 2의보수 8자리 hex로)
with open("cases/C_golden.mem", "w") as fc:
    for idx, (A, B) in enumerate(zip(A_list, B_list)):
        C = A @ B                      # numpy 행렬곱 = golden
        row = []
        for i in range(SIZE):
            for j in range(SIZE):
                v = int(C[i][j]) & 0xFFFFFFFF   # 32비트 2의보수
                row.append(f"{v:08X}")
        fc.write(" ".join(row) + "\n")

print(f"golden 계산 완료 : {len(A_list)}개 케이스 -> cases/C_golden.mem")
# 확인용 출력
for idx, (A, B) in enumerate(zip(A_list, B_list)):
    C = A @ B
    print(f" case {idx:2d}: C 범위 {C.min():6d} ~ {C.max():6d}  (C[0][0]={C[0][0]})")
