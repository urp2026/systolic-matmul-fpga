# Systolic Array 기반 정수 행렬곱 가속기 — 곱셈기 구조 및 데이터 폭에 따른 비용·정확도 분석

> **2026 하계 URP (Undergraduate Research Program)**
> 지도교수 김율화 (성균관대학교 반도체시스템공학과)
> 배윤재 · 이예준 · 주형능 · 이재현

---

## 1. 연구 배경 및 목표

행렬곱은 신경망 추론 연산의 대부분을 차지하며, 이를 전용 하드웨어로 가속할 때 설계자는 두 가지 독립적인 선택에 직면한다.

첫째는 **곱셈기 내부 구조**다. 부분곱을 순차적으로 더하는 array 방식과, CSA(Carry-Save Adder) 트리로 압축한 뒤 최종 가산하는 Wallace tree 방식이 대표적이다. 교과서적으로 Wallace tree는 가산 단수가 O(log n)이므로 더 빠르다고 알려져 있다.

둘째는 **데이터 폭**이다. 32비트 부동소수점 대신 INT8이나 INT4 같은 좁은 정수를 쓰면 면적과 전력이 줄지만, 반올림에 의한 정밀도 손실이 발생한다.

본 프로젝트는 이 두 축을 FPGA 상에서 **실측**하여 정량화하는 것을 목표로 한다. 구체적으로는 다음 질문에 답한다.

1. FPGA에서 Wallace tree는 array 곱셈기 대비 실제로 이득이 있는가? 있다면 어느 지표에서인가?
2. 데이터 폭을 줄일 때 정밀도 손실과 자원 절감은 어떤 비율로 교환되는가?
3. 두 축은 서로 독립인가?

- **Target Board**: Digilent Nexys A7-100T (Xilinx Artix-7 XC7A100T, `xc7a100tcsg324-1`)
- **HDL / Tools**: Verilog, Vivado 2025.2, Icarus Verilog, Python/NumPy

---

## 2. 설계

### 2.1 아키텍처

4×4 weight-stationary systolic array를 기본 구조로 한다. 16개의 PE(Processing Element)가 격자로 배치되며, 각 PE는 곱셈기 하나와 누산 레지스터를 갖는다. 데이터 폭 `DW`와 곱셈기 종류만 교체하고 나머지 데이터플로우는 전 조합에서 동일하게 유지하여, 측정된 차이가 곱셈기·데이터 폭에서만 기인하도록 통제하였다.

```
matmul_top_ws
 └ systolic_array_ws (u_sa)      ← 전 조합 동일
    └ pe_ws × 16                 ← 전 조합 동일
       └ u_mul                   ← 이 부분만 교체
          array_multiplier_signed  ⇄  wallace_multiplier_signed
```

### 2.2 주요 설계 결정

| 항목 | 선택 | 근거 |
|---|---|---|
| Signed 곱셈 | Baugh-Wooley | 부호 확장 없이 부분곱 배열 내에서 부호 처리 |
| 곱셈기 대안 | Wallace tree (CSA) | 부분곱 압축에 의한 가산 단수 감소 효과 검증 |
| 누산기 폭 | `AW = 4×DW` | INT4/8/16 각각 16/32/64bit — 필요 폭(10/18/34bit) 대비 안전 |
| Top 모듈 분리 | `fpga_top_bram` / `power_bench_wrapper` | 보드 검증용과 측정용 분리 |
| 전력 측정 자극 | LFSR 기반 의사난수 입력 | 정적 입력 시 스위칭이 없어 동적 전력이 측정되지 않음 |

**측정 경계 설정.** 전력·자원은 `power_bench_wrapper` 기준으로 측정하였다. LFSR 자극 생성 로직의 오버헤드는 INT8 기준 8 slice(전체의 2.8%)로, 조합 간 상대 비교에 영향을 주지 않는 수준이다. 반면 `fpga_top_bram`은 7-segment 표시부의 BCD 변환 로직이 전체 LUT의 절반 이상을 차지하여 측정 대상으로 부적합하다.

---

## 3. 검증 방법

본 연구는 성격이 다른 두 종류의 검증을 수행하였다. 이를 혼동하면 결과 해석이 왜곡되므로 명확히 구분한다.

### 3.1 검증 ① — RTL 정합성 (구현 정확성)

**묻는 것**: 하드웨어가 주어진 정수 행렬곱을 정확히 계산하는가?

```
정수 케이스 생성 → .mem 파일 → RTL 시뮬레이션 → 골든과 비교
    (Python)                      (tb_golden_compare)
```

테스트 케이스는 Python에서 **정수로 직접 생성**하였다. FP32에서 정밀도를 축소하여 만들 경우 대칭 스케일링 특성상 최솟값(INT4의 −8 등)이 출현하지 않아 경계 검증에 구멍이 생기기 때문이다. 케이스 구성은 sparse 5 / boundary 5 / random 5이며, boundary는 각 정밀도의 극값(INT4: −8/+7, INT8: −128/+127, INT16: −32768/+32767) 조합으로 채웠다.

골든 값은 DUT과 완전히 독립된 NumPy에서 계산하였다. Verilog 내부에서 골든을 계산하면 DUT과 골든에 동일한 오류가 전파될 수 있어, 검증이 무의미해진다.

**결과**: INT4/8/16 × Array/Wallace 전 조합에서 15케이스 × 16원소 = **240/240 비트 단위 일치**.

### 3.2 검증 ② — 정밀도 손실 (SQNR)

**묻는 것**: 데이터 폭을 줄이면 결과가 FP32 대비 얼마나 부정확해지는가?

$$\mathrm{SQNR} = 10\log_{10}\frac{\sum x^2}{\sum (x-\hat{x})^2}\ \ [\mathrm{dB}]$$

여기서 `x`는 FP32 원본, `x̂`은 정밀도를 축소했다가 원래 스케일로 되돌린 값이다.

```
공통 FP32 소스 → 정밀도 축소 round() → 정수 행렬곱 → 스케일 복원 → FP32와 비교
```

**FP32를 비교 기준으로 삼는 근거**는 세 가지다.

1. 정확도는 항상 기준값에 대한 상대량이므로, 축소되지 않은 공통 참값이 필요하다.
2. FP32의 유효숫자는 약 24비트로 측정 대상(최대 INT16)보다 8비트 이상 정밀하여, 기준자 자체의 오차를 무시할 수 있다.
3. 신경망은 FP32로 학습되므로, 실제 응용에서 "정확도 손실"이란 곧 FP32 모델 대비 이탈량을 의미한다.

INT8을 기준으로 삼을 경우 INT16의 우위가 측정되지 않는다. 원본에 없는 정보를 확장으로 만들어낼 수 없기 때문이다.

### 3.3 두 검증의 연결

검증 ①에서 하드웨어 출력이 NumPy 정수 결과와 비트 단위로 일치함을 보였다. 따라서 동일한 정수에 동일한 스케일을 적용하는 SQNR 계산은 Python에서 수행하더라도 하드웨어의 정확도와 같다. **검증 ①이 없으면 SQNR 수치는 하드웨어와 무관한 소프트웨어 시뮬레이션에 불과하다.**

정수 곱셈은 비트 단위로 정확하므로 검증 ①은 전 조합에서 통과하는 것이 정상이다. 정밀도 손실은 곱셈이 아니라 그 이전 단계인 반올림에서 이미 발생한다.

---

## 4. 측정 방법

| 항목 | 조건 | 도구 |
|---|---|---|
| 자원 (LUT/CARRY4/FF/Slice) | 10 ns 제약, Implementation 완료 후 | `report_utilization` |
| 타이밍 | 10 ns 제약, WNS로부터 역산 | `report_timing_summary` |
| 동적 전력 | Post-Implementation Timing Simulation → SAIF | `read_saif` → `report_power` |

**전력 측정 절차.** Post-Implementation Timing Simulation에서 20 µs 구간의 토글 정보를 SAIF로 기록한 뒤, Implemented Design에서 이를 읽어 전력을 산출하였다. 전 조합에서 Confidence Level High, 넷 매칭률 64–70%를 확보하였다.

Post-Synthesis Functional Simulation은 배선 지연이 0이어서 글리치 전력이 누락되며, 실측 결과 동일 설계에서 Post-Impl 대비 약 2 mW 낮게 측정되었다. 따라서 전 조합을 Post-Implementation Timing으로 통일하였다.

---

## 5. 결과

### 5.1 전체 측정 결과

| DW | 곱셈기 | LUT | CARRY4 | FF | Slice | Fmax | Dynamic |
|---|---|---|---|---|---|---|---|
| 16 | Wallace | 829 | 180 | 427 | 276 | 102.5 MHz | 9 mW |
| 8 | Array | 781 | 132 | 426 | 285 | 105.0 MHz | 10 mW |
| 8 | Wallace | 779 | 52 | 426 | 261 | 103.3 MHz | 9 mW |
| 4 | Array | 479 | 68 | 373 | 171 | 119.0 MHz | 6 mW |
| 4 | Wallace | 518 | 68 | 373 | 204 | 107.2 MHz | 7 mW |

*Fmax는 10 ns 제약 하 WNS로부터 `1/(T − WNS)`로 환산한 값이다(전 조합 timing met). DSP는 전 조합 0으로, 곱셈기가 LUT로 구현되었음을 확인하였다.*

### 5.2 정밀도별 손실 (SQNR)

| 정밀도 | 표현 범위 | AW | SQNR | INT8 대비 |
|---|---|---|---|---|
| INT4 | −8 ~ +7 | 16 | 12.9 dB | −25.2 dB |
| INT8 | −128 ~ +127 | 32 | 38.1 dB | (기준) |
| INT16 | −32768 ~ +32767 | 64 | 86.4 dB | +48.3 dB |

*64×64 정규분포 행렬 20회 평균, 대칭 per-tensor 스케일링 기준.*

곱셈기 구조는 비트 단위로 등가이므로 SQNR은 정밀도당 하나만 존재한다.

---

## 6. 분석

### 6.1 Wallace tree의 이득은 속도가 아닌 면적에서 나타난다

INT8 기준으로 Wallace tree는 LUT(781→779, −0.3%)과 Fmax(105.0→103.3 MHz, −1.6%)에서 사실상 차이가 없었다. 교과서적 예측인 속도 이득이 관측되지 않은 것이다.

원인은 FPGA 아키텍처에 있다. 타이밍 리포트에서 추출한 실측 지연은 다음과 같다.

| 경로 | 단당 지연 |
|---|---|
| CARRY4 (전용 캐리 체인) | ≈ 0.11 ns |
| LUT 경로 | ≈ 0.31 ns |

Xilinx 7-series는 슬라이스마다 전용 캐리 체인(CARRY4)을 하드 매크로로 제공하며, 이는 LUT 경로보다 약 3배 빠르다. Wallace tree는 CSA 트리를 LUT으로 구현하므로, 캐리 전파 단수를 줄이더라도 그 자리를 더 느린 LUT이 채워 이득이 상쇄된다. ASIC이라면 순수 게이트 지연만 존재하므로 트리 깊이가 곧 속도로 이어지지만, FPGA에서는 벤더가 제공하는 전용 회로가 array 곱셈기를 유리하게 만든다.

다만 Wallace tree는 **CARRY4 사용량을 61% 감소**(132→52)시켰고, 이것이 **Slice 8.4% 감소**(285→261)로 이어졌다. 캐리 체인은 세로로 연속된 슬라이스에 배치되어야 하는 제약이 있어 배치 자유도를 떨어뜨리는데, 이를 덜 쓰면 LUT 패킹 밀도가 개선된다. 실제로 슬라이스당 LUT 수는 2.74에서 2.98로 증가하였다.

즉 **FPGA에서 Wallace tree의 실질 이득은 속도가 아니라 면적**이며, 그 메커니즘은 캐리 체인 사용량 감소를 통한 배치 효율 개선이다.

### 6.2 Wallace tree에는 최소 유효 비트 폭이 존재한다

INT4에서는 결과가 역전되었다.

| 지표 | INT4 Array → Wallace |
|---|---|
| LUT | 479 → 518 (**+8.1%**) |
| Slice | 171 → 204 (**+19.3%**) |
| Fmax | 119.0 → 107.2 MHz (**−9.9%**) |
| Dynamic | 6 → 7 mW (**+16.7%**) |

모든 지표에서 Wallace tree가 열세이며, CARRY4는 68로 동일하여 감소 효과조차 없었다.

원인은 부분곱 개수다. Wallace tree의 이득은 다수의 부분곱을 CSA로 압축하는 데서 나오는데, 4비트 곱셈은 부분곱이 4개뿐이라 압축할 대상이 부족하다. 결과적으로 CSA 구조의 중간 sum/carry 배선 오버헤드만 추가된다.

INT8에서 이득이 나타나고 INT4에서 손해가 발생한다는 것은, **Wallace tree 적용에 최소 비트 폭 임계값이 존재**함을 시사한다. 본 실험 조건에서 그 경계는 4비트와 8비트 사이에 있다.

### 6.3 데이터 폭 축소의 비용·정확도 교환비

| 전환 | SQNR 손실 | Slice 절감 | LUT 절감 |
|---|---|---|---|
| INT8 → INT4 (Array) | −25.2 dB | −40.0% | −38.7% |

INT8에서 INT4로 전환하면 정밀도 손실은 25 dB, 즉 잡음 전력이 약 330배 증가한다. 상대 오차로는 약 1.2%에서 23%로 악화된다. 그 대가로 얻는 것은 자원 40% 절감이다.

실측 SQNR은 이론값과 잘 일치한다. 균일 반올림에서 비트 하나당 SQNR은 6.02 dB 개선되므로 4비트 감소 시 24.1 dB 손실이 예상되는데, 실측은 25.2 dB였다. 이 일치는 정밀도 축소 구현이 타당함을 뒷받침하는 근거이기도 하다.

한편 자원 절감이 이론적 예측(곱셈기 면적 ∝ 비트폭², 즉 1/4)보다 완만한 것은, 누산기·제어 FSM·LFSR 등 비트폭에 선형이거나 고정인 요소가 포함되어 있기 때문이다. FF 수가 426→373으로 12%만 감소한 것이 이를 뒷받침한다.

### 6.4 두 축의 독립성

곱셈기 구조는 정확도에 영향을 주지 않는다. Array와 Wallace tree는 부분곱 합산 순서만 다르며, 정수 덧셈은 결합법칙이 성립하므로 결과가 비트 단위로 동일하다. 검증 ①에서 이를 실측으로 확인하였다.

따라서 두 축은 성격이 다르다.

| 축 | 트레이드오프 | 판단 기준 |
|---|---|---|
| 데이터 폭 | 정확도 ↔ 비용 | SQNR과 자원을 함께 고려 |
| 곱셈기 구조 | 없음 (정확도 동일) | 비용만 비교 |

곱셈기 선택은 정확도 손실 없이 비용만 줄이는 문제이므로, 조건이 맞으면 순이득이다. 다만 6.2에서 확인했듯 그 조건은 비트 폭에 의존한다.

---

## 7. 한계

**타이밍 측정.** Fmax는 10 ns 제약 하에서 timing met 상태의 WNS로부터 환산한 값이다. 도구는 제약을 만족하면 최적화를 중단하므로, 이 값은 설계의 물리적 한계가 아니라 "주어진 제약에 대한 여유"를 반영한다. 별도 실험에서 제약을 3 ns로 조인 결과 INT8 Array의 Fmax는 105.0 MHz에서 113.8 MHz로 상승하였다. 조합 간 상대 비교는 동일 조건이므로 유효하나, 절대값을 설계 한계로 해석해서는 안 된다.

**전력 측정 해상도.** 4×4 규모에서 동적 전력은 6–10 mW 범위이며, Vivado 리포트의 mW 단위 반올림으로 인해 조합 간 차이(1–2 mW)가 측정 오차와 구분되기 어렵다. 전력 수치는 경향 참고용으로만 사용하고, 결론은 자원(Slice, CARRY4)에 근거하였다.

**배치 의존성.** 칩 사용률이 1–2%에 불과하여 배치 도구가 로직을 조밀하게 모을 유인이 없다. INT8 Array의 critical path에서 배선 지연 비중은 51%였으며, 이는 구조 차이가 배치 편차에 일부 가려질 수 있음을 의미한다.

**SQNR의 적용 범위.** SQNR은 연산 단위의 정밀도 손실 지표로, 실제 신경망 태스크 정확도(분류율 등)와의 정량적 연결은 검증하지 않았다. 또한 per-tensor 대칭 스케일링만 측정하였으며, per-channel 스케일링 적용 시 INT4의 손실이 상당히 회복될 여지가 있다. 측정에 사용한 정규분포 랜덤 행렬은 실제 신경망 가중치 분포와 차이가 있다.

**미완 항목.** INT16 Array 조합은 자원 측정(LUT 917, CARRY4 180, FF 428)까지 완료하였으나 전력 측정이 유효하지 않아 본 보고서의 비교표에서 제외하였다. 이로 인해 INT16에서의 Array 대 Wallace 비교는 수행하지 못하였다.

---

## 8. 결론 및 향후 계획

### 결론

1. FPGA에서 Wallace tree의 이득은 속도가 아니라 **면적**에서 나타난다(INT8 기준 Slice −8.4%). 전용 캐리 체인이 LUT보다 3배 빠르다는 아키텍처 특성이 교과서적 속도 이득을 상쇄한다.
2. Wallace tree에는 **최소 유효 비트 폭**이 존재한다. INT4에서는 부분곱이 부족하여 오히려 모든 지표에서 열세였다.
3. 데이터 폭 축소는 명확한 트레이드오프다. INT8→INT4는 25 dB의 정밀도를 내주고 자원 40%를 얻는다.
4. 두 축은 독립적이다. 곱셈기 구조는 정확도에 영향이 없으므로 비용만으로 판단하면 된다.

### 향후 계획

| 항목 | 내용 | 방법 |
|---|---|---|
| ① | INT16 Array 전력 측정 완료 | SAIF 재생성 후 Post-Impl로 재측정 |
| ② | INT16에서 Array 대 Wallace 비교 | 부분곱 16개 조건에서 6.2의 임계값 가설 검증 |
| ③ | per-channel 스케일링 SQNR | INT4 정밀도 회복 폭 정량화 |
| ④ | Fmax 별도 측정 | 제약을 조여 timing fail 상태에서 물리 한계 산출 |

②는 특히 중요하다. INT4에서 손해, INT8에서 이득이 확인된 상태이므로, INT16에서 이득이 더 커진다면 "비트 폭이 클수록 Wallace tree가 유리하다"는 단조 경향이 세 점으로 확정된다.

---

## 9. 저장소 구조

```
systolic-matmul-fpga/
├── rtl/
│   ├── rtl_int4/        # INT4 RTL (array, wallace, wrapper, top)
│   ├── rtl_int8/        # INT8 RTL
│   └── rtl_int16/       # INT16 RTL
├── tb/
│   ├── tb_int4/         # INT4 테스트벤치
│   ├── tb_int8/         # INT8 테스트벤치
│   └── tb_int16/        # INT16 테스트벤치
├── constraints/         # XDC 제약 (클럭, 핀 배치)
├── mem/                 # 검증용 .mem (A / B / C_golden)
├── precision_py/        # precision_eval.py — .mem 생성 및 SQNR 측정
├── result/              # 측정 리포트 원본
└── docs/                # 주차별 보고서, 발표 자료
```

### 실행 방법

**정밀도 평가 및 검증 데이터 생성**

```bash
python precision_py/precision_eval.py
# → INT4/8/16 .mem 파일 생성 + SQNR 리포트 출력
```

**RTL 시뮬레이션 (Icarus Verilog)**

```bash
# 곱셈기 단위 검증
iverilog -o sim.out tb/tb_int8/tb_MatMult.v rtl/rtl_int8/arrayMatMult.v && vvp sim.out

# 시스템 레벨 골든 비교
iverilog -o sim.out tb/tb_int8/tb_golden_compare.v rtl/rtl_int8/arrayMatMult.v && vvp sim.out
```

**Vivado 측정**

1. 해당 정밀도의 `rtl/rtl_int*/` 소스와 `constraints/` XDC 추가
2. Top 설정 — 자원·전력 측정: `power_bench_wrapper`, 보드 검증: `fpga_top_bram`
3. Synthesis → Implementation (10 ns 제약)
4. 자원: `report_utilization`에서 LUT / CARRY4 / FF / Slice
5. 전력: Post-Implementation Timing Simulation → SAIF 생성 → `read_saif` → `report_power`

```tcl
# 시뮬레이터 콘솔
restart
open_saif <경로>/power_int8_array.saif
log_saif [get_objects -r /tb_power_bench/dut/*]
run 20us
close_saif

# Implemented Design 콘솔
read_saif <경로>/power_int8_array.saif
report_power
```

SAIF 파일명은 정밀도·구조별로 분리하며, 결과 리포트에서 Confidence Level High와 넷 매칭률 60% 이상을 확인한다. 테스트벤치의 wrapper 인스턴스 이름은 정밀도별로 다르므로(`power_bench_wrapper_INT4` 등) 프로젝트 전환 시 반드시 확인해야 한다.
