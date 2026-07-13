## 1. 100MHz 시스템 클럭
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports CLK100MHZ]
create_clock -add -name sys_clk -period 10.000 -waveform {0 5} [get_ports CLK100MHZ]

## 2. 버튼 (Verilog 포트 이름에 맞게 btnC, btnU로 수정)
set_property -dict { PACKAGE_PIN N17   IOSTANDARD LVCMOS33 } [get_ports btnC] ;# 연산 시작 (start)
set_property -dict { PACKAGE_PIN M18   IOSTANDARD LVCMOS33 } [get_ports btnU] ;# 시스템 리셋 (rst)

## 3. 비동기 버튼 입력은 타이밍 분석(Fmax)에서 제외 (btnC, btnU 모두 적용)
set_false_path -from [get_ports btnC]
set_false_path -from [get_ports btnU]

## 4. 슬라이드 스위치 (SW[15]: 메모리 선택, SW[3:0]: 16개 원소 인덱스 선택)
set_property -dict { PACKAGE_PIN J15   IOSTANDARD LVCMOS33 } [get_ports {SW[0]}]
set_property -dict { PACKAGE_PIN L16   IOSTANDARD LVCMOS33 } [get_ports {SW[1]}]
set_property -dict { PACKAGE_PIN M13   IOSTANDARD LVCMOS33 } [get_ports {SW[2]}]
set_property -dict { PACKAGE_PIN R15   IOSTANDARD LVCMOS33 } [get_ports {SW[3]}]
set_property -dict { PACKAGE_PIN V10   IOSTANDARD LVCMOS33 } [get_ports {SW[15]}]
# 사용하지 않는 스위치 핀들도 에러 방지를 위해 접지(또는 선언) 필요 시 아래 주석 해제
# for {set i 4} {$i < 15} {incr i} { set_property -dict "PACKAGE_PIN T8 IOSTANDARD LVCMOS33" [get_ports "SW[$i]"] }

## 5. 7-세그먼트 디스플레이 세그먼트 (seg[6:0] 및 dp)
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports {seg[6]}] ;# CA
set_property -dict { PACKAGE_PIN R10   IOSTANDARD LVCMOS33 } [get_ports {seg[5]}] ;# CB
set_property -dict { PACKAGE_PIN K16   IOSTANDARD LVCMOS33 } [get_ports {seg[4]}] ;# CC
set_property -dict { PACKAGE_PIN K13   IOSTANDARD LVCMOS33 } [get_ports {seg[3]}] ;# CD
set_property -dict { PACKAGE_PIN P15   IOSTANDARD LVCMOS33 } [get_ports {seg[2]}] ;# CE
set_property -dict { PACKAGE_PIN T11   IOSTANDARD LVCMOS33 } [get_ports {seg[1]}] ;# CF
set_property -dict { PACKAGE_PIN L18   IOSTANDARD LVCMOS33 } [get_ports {seg[0]}] ;# CG
set_property -dict { PACKAGE_PIN H15   IOSTANDARD LVCMOS33 } [get_ports dp]

## 6. 7-세그먼트 자릿수 선택 애노드 (an[7:0])
set_property -dict { PACKAGE_PIN J17   IOSTANDARD LVCMOS33 } [get_ports {an[0]}]
set_property -dict { PACKAGE_PIN J18   IOSTANDARD LVCMOS33 } [get_ports {an[1]}]
set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports {an[2]}]
set_property -dict { PACKAGE_PIN J14   IOSTANDARD LVCMOS33 } [get_ports {an[3]}]
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports {an[4]}]
set_property -dict { PACKAGE_PIN T14   IOSTANDARD LVCMOS33 } [get_ports {an[5]}]
set_property -dict { PACKAGE_PIN K2    IOSTANDARD LVCMOS33 } [get_ports {an[6]}]
set_property -dict { PACKAGE_PIN U13   IOSTANDARD LVCMOS33 } [get_ports {an[7]}]
