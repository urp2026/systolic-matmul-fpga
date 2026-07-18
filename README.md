# Systolic Array 기반 행렬곱 가속기 설계 및 비교 분석

> 2026 하계 URP (Undergraduate Research Program)
> Nexys A7-100T FPGA를 타깃으로 한 시스톨릭 어레이 기반 행렬곱 가속기의 설계, 구현 및 버전별 성능 비교 분석

## 👥 Team

- **지도교수**: 김율화 교수님 (성균관대학교)
- **팀원**: 배윤재, 이예준, 주형능, 이재현

## 📌 프로젝트 개요

본 프로젝트는 정수 행렬곱 연산을 수행하는 하드웨어 가속기를 설계하고, 두 개의 독립적인 축을 정량적으로 비교 분석하는 것을 목표로 합니다.

1. **곱셈기 구조 축** — Array vs. Wallace tree (자원/전력/타이밍 비교)
2. **정수 정밀도 축** — INT4 / INT8 / INT16 (정확도 vs. 비용 트레이드오프)

- **Target Board**: Digilent Nexys A7-100T (Xilinx Artix-7 XC7A100T)
- **HDL**: Verilog
- **Tools**: Vivado (합성/구현/SAIF 전력 측정), Icarus Verilog (시뮬레이션), Python/NumPy (골든 생성, SQNR)

## 🏗️ 주요 설계 사항

| 항목 | 설계 선택 | 비고 |
|---|---|---|
| Signed 곱셈 | Baugh-Wooley multiplier | `arrayMatMult.v` |
| 곱셈기 최적화 | Wallace tree 구조 | 부분곱 압축을 통한 캐리 체인 감소 |
| 누산기 폭 | `AW = 4*DW` | INT4/8/16 오버플로우 안전 (필요 10/18/34bit) |
| BRAM 초기화 | `INIT_FILE` 파라미터 방식 | 계층적 `$readmemh` 대체 |
| Top 모듈 분리 | `fpga_top_bram` / `power_bench_wrapper` | 기능 검증용 / 전력 측정용 |
| 전력 측정 입력 | LFSR 기반 동적 입력 | SAIF 토글 기반, 실제 스위칭 활동 유도 |

## 📊 비교 결과

### 1. 곱셈기 구조 비교 (INT8 기준)

| 구조 | LUT | CARRY4 | FF | Slice | Fmax | Dynamic Power |
|---|---|---|---|---|---|---|
| **Array (V1)** | 781 | 132 | 426 | 285 | 113.8 MHz | 10 mW |
| **Wallace (V2)** | 779 | 52 | 426 | 261 | 113.4 MHz | 9 mW |

> - **LUT/Fmax는 사실상 동등** (0.3% / 0.4% 차이 → 측정 노이즈 수준)
> - **CARRY4 61% 감소** (132→52): Wallace CSA 트리가 캐리 체인을 대폭 단축
> - **Slice 8.4% 감소** (285→261): CARRY4 감소로 슬라이스 패킹 밀도 개선이 실질 면적 이득으로 이어짐
> - FPGA에서는 전용 캐리 체인(CARRY4, ≈0.11 ns/단)이 LUT 경로(≈0.31 ns/단)보다 빨라, Wallace의 트리 깊이 이점이 속도로 나타나지 않음. 이득은 속도가 아닌 **면적(Slice)** 에서 발생.

*측정 조건: 면적/전력 = 10 ns 제약 (timing met), Fmax = 3 ns 제약 별도 런 (WNS 음수에서 역산). power_bench_wrapper + LFSR, SAIF Confidence High.*

### 2. 정수 정밀도 비교 (SQNR, Wallace 기준)

| 정밀도 | 표현 범위 | AW | SQNR | INT8 대비 |
|---|---|---|---|---|
| **INT4** | −8 ~ +7 | 16 | 12.9 dB | −25.2 dB |
| **INT8** | −128 ~ +127 | 32 | 38.1 dB | (기준) |
| **INT16** | −32768 ~ +32767 | 64 | 86.4 dB | +48.3 dB |

> - SQNR은 FP32 원본 대비 양자화 정확도. 이론값 6.02 dB/bit와 실측이 일치 (8→4bit: 이론 24 dB, 실측 25.2 dB).
> - 곱셈기 구조(Array/Wallace)는 bit-exact 등가이므로 정확도 축에는 SQNR이 정밀도당 하나만 존재.
> - 측정 방법: 공통 FP32 소스 → 각 정밀도 양자화 → 정수 연산 → 역양자화 → FP32와 비교 (64×64, 20회 평균).

## ✅ 검증

- **곱셈기 정확성**: `tb_golden_compare` 기준 INT4/8/16 전 케이스 bit-exact PASS (15 케이스 × 16 원소 = 240/240).
- **RTL ↔ SQNR 연결**: HW 정수 결과가 NumPy 골든과 bit-exact 일치하므로, Python에서 계산한 SQNR이 곧 하드웨어 정확도.
- **정수 곱셈은 비트 단위로 정확** → RTL 전 케이스 PASS는 정상이며, 정확도 손실은 곱셈이 아닌 양자화(round)에서 발생.
- 골든 레퍼런스는 외부(Python/NumPy)에서 생성하여 DUT과 독립 (동일 버그 전파 방지).

## 📁 디렉토리 구조

```
systolic-matmul-fpga/
├── rtl/            # INT8 Verilog RTL (Array, Wallace, wrapper, top)
├── rtl_int4/       # INT4 RTL
├── rtl_int16/      # INT16 RTL
├── tb/             # INT8 테스트벤치
├── tb_int4/        # INT4 테스트벤치
├── tb_int16/       # INT16 테스트벤치
├── constraints/    # XDC 제약 파일 (클럭, 핀 배치)
├── mem/            # BRAM 초기화용 .mem 파일 (INT4/INT8/INT16)
├── precision_py/   # SQNR 측정 및 골든 생성 (make_golden.py)
├── docs/           # 주차별 보고서, 발표 자료
└── result/         # 버전별 utilization / timing / power 리포트
```

## 🚀 빌드 및 실행 방법

### 1. 골든 생성 및 SQNR 측정 (Python)

```bash
python precision_py/make_golden.py
# → INT4/8/16 .mem 파일 생성 + SQNR 리포트 출력
```

### 2. 시뮬레이션 (Icarus Verilog)

```bash
# 곱셈기 단독 검증
iverilog -o sim.out tb/tb_MatMult.v rtl/arrayMatMult.v
vvp sim.out

# 시스템 레벨 골든 비교
iverilog -o sim.out tb/tb_golden_compare.v rtl/arrayMatMult.v
vvp sim.out
```

테스트벤치는 golden reference 값과 출력을 비교하여 PASS/FAIL을 판정합니다.

### 3. Vivado 합성 및 구현

1. Vivado에서 프로젝트 생성 후 해당 정밀도의 `rtl*/` 소스와 `constraints/` XDC 추가
2. Top 모듈 선택:
   - 보드 동작 검증: `fpga_top_bram`
   - 전력 측정: `power_bench_wrapper`
3. Synthesis → Implementation → Generate Bitstream
4. Hardware Manager로 Nexys A7-100T에 비트스트림 프로그래밍

### 4. 결과 측정

- **Utilization / Timing**: Implementation 완료 후 리포트 확인 (10 ns 제약)
- **Fmax**: 클럭 제약을 3 ns로 조여 WNS 음수 상태에서 `Fmax = 1 / (T − WNS)` 역산 (별도 런)
- **Power**: Post-Implementation Timing Simulation으로 SAIF 생성 후 `read_saif` → `report_power` (Confidence High)

## 🗂️ 버전 관리

- 각 버전(V1, V2, ...) 완료 시점에 git tag를 생성합니다 (`v1.0`, `v2.0`, ...)
- 버전별 측정 리포트 원본은 `result/`에 정밀도·구조별로 보관합니다
