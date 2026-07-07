# Systolic Array 기반 행렬곱 가속기 설계 및 비교 분석

> 2026 하계 URP (Undergraduate Research Program)
> Nexys A7-100T FPGA를 타깃으로 한 시스톨릭 어레이 기반 행렬곱 가속기의 설계, 구현 및 버전별 성능 비교 분석

## 👥 Team

- **지도교수**: 김율화 교수님 (성균관대학교)
- **팀원**: 배윤재, 이예준, 주형능, 이재현

## 📌 프로젝트 개요

본 프로젝트는 INT8 행렬곱 연산을 수행하는 하드웨어 가속기를 여러 버전으로 설계하고, 각 버전의 **타이밍(Fmax), 자원 사용량(LUT/FF/DSP), 전력 소모**를 정량적으로 비교 분석하는 것을 목표로 합니다.

- **Target Board**: Digilent Nexys A7-100T (Xilinx Artix-7 XC7A100T)
- **HDL**: Verilog
- **Tools**: Vivado (합성/구현/전력 측정), Icarus Verilog (시뮬레이션)

## 🏗️ 주요 설계 사항

| 항목 | 설계 선택 | 비고 |
|---|---|---|
| Signed 곱셈 | Baugh-Wooley multiplier | `arrayMatMult.v` |
| 곱셈기 최적화 | Wallace tree 구조 | 부분곱 압축을 통한 지연 감소 |
| BRAM 초기화 | `INIT_FILE` 파라미터 방식 | 계층적 `$readmemh` 대체 |
| Top 모듈 분리 | `fpga_top_bram` / `power_bench_wrapper` | 기능 검증용 / 전력 측정용 |
| 전력 측정 입력 | LFSR 기반 동적 입력 | 실제 동작에 가까운 스위칭 활동 유도 |

## 📊 버전별 비교 결과

| Version | 구조 | WNS | Fmax | LUT | FF | DSP | Power |
|---|---|---|---|---|---|---|---|
| **V1** | Array INT8 (baseline) | +0.409 ns | ~104.3 MHz | 784 | 426 | 0 | 0.084 W |
| **V2** | Wallac Tree INT8 | +0.154 ns | ~101.6 MHz | 780 | 426 | 0 | 0.084 W |
| **V3** | *(TBD)* | – | – | – | – | – | – |

> 측정 조건: Vivado 합성/구현 후 post-implementation 리포트 기준. 전력은 `power_bench_wrapper` + LFSR 동적 입력 환경에서 측정.

## 📁 디렉토리 구조

```
systolic-array/
├── rtl/            # Verilog RTL 소스 (arrayMatMult.v, PE, controller 등)
├── tb/             # 테스트벤치
├── constraints/    # XDC 제약 파일 (클럭, 핀 배치)
├── mem/            # BRAM 초기화용 .mem / .hex 파일
├── scripts/        # 시뮬레이션 / 빌드 스크립트
├── docs/           # 블록 다이어그램, 보고서, 발표 자료
└── results/        # 버전별 utilization / timing / power 리포트
```

## 🚀 빌드 및 실행 방법

### 1. 시뮬레이션 (Icarus Verilog)

```bash
# 예시: 행렬곱 모듈 시뮬레이션
iverilog -o sim.out tb/tb_arrayMatMult.v rtl/arrayMatMult.v
vvp sim.out
```

테스트벤치는 golden reference 값과 출력 결과를 비교하여 PASS/FAIL을 판정합니다.

### 2. Vivado 합성 및 구현

1. Vivado에서 프로젝트 생성 후 `rtl/` 소스와 `constraints/` XDC 추가
2. Top 모듈 선택:
   - 보드 동작 검증: `fpga_top_bram`
   - 전력 측정: `power_bench_wrapper`
3. Synthesis → Implementation → Generate Bitstream
4. Hardware Manager로 Nexys A7-100T에 비트스트림 프로그래밍

### 3. 결과 측정

- **Timing / Utilization**: Implementation 완료 후 리포트 확인 → `results/`에 저장
- **Power**: post-implementation 상태에서 Report Power 실행 (LFSR 동적 입력 적용)

## ✅ 검증 방법

- 각 모듈 단위 테스트벤치(`tb/`)로 기능 검증
- 행렬곱 결과는 소프트웨어로 계산한 기대값(golden reference)과 자동 비교
- 보드 레벨 검증은 `fpga_top_bram`을 통해 BRAM에 저장된 입력/출력 확인

## 🗂️ 버전 관리

- 각 버전(V1, V2, ...) 완료 시점에 git tag를 생성합니다 (`v1.0`, `v2.0`, ...)
- 버전별 측정 리포트 원본은 `results/v1/`, `results/v2/` 형태로 보관합니다

## 📄 License

*(TBD — 지도교수님과 협의 후 결정)*
