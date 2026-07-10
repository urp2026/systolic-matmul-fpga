import numpy as np

# 1. 파일 이름 설정
file_a = 'all_A.mem'
file_b = 'all_B.mem'
file_c_golden = 'all_C_golden.mem' # 생성될 정답 파일 이름

# 2. 16진수 문자열 리스트를 4x4 행렬로 변환하는 함수
def hex_list_to_matrix(hex_list):
    # 8-bit 부호 있는 정수(2의 보수) 변환
    dec_list = [int(x, 16) - 256 if int(x, 16) > 127 else int(x, 16) for x in hex_list]
    # 16개 데이터를 4x4 형태로 재배열
    return np.array(dec_list).reshape(4, 4)

# 3. 파일 읽기 및 처리
with open(file_a, 'r', encoding='utf-8') as fa, \
     open(file_b, 'r', encoding='utf-8') as fb, \
     open(file_c_golden, 'w', encoding='utf-8') as fc:
     
    for case_idx, (line_a, line_b) in enumerate(zip(fa, fb), start=1):
        
        line_a = line_a.strip()
        line_b = line_b.strip()
        if not line_a or not line_b:
            continue
            
        A = hex_list_to_matrix(line_a.split())
        B = hex_list_to_matrix(line_b.split())
        
        C = np.matmul(A, B)
        
        print(f"=== Test Case {case_idx} ===")
        print(C)
        print()
        
        c_hex_str = " ".join([hex(val & 0xFFFFFFFF)[2:].zfill(8).upper() for val in C.flatten()])
        fc.write(c_hex_str + "\n")
