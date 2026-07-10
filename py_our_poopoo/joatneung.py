import numpy as np
import re

def read_mem_batch(filepath, num_cases, rows, cols, is_signed=True):
    # 파일 읽기
    with open(filepath, 'r') as f:
        data = f.read()

    # 정규식을 이용해 16진수 바이트 값만 추출
    hex_values = re.findall(r'\b[0-9A-Fa-f]{2}\b', data)
    int_values = [int(h, 16) for h in hex_values]

    # 부호 없는 8비트로 numpy 배열 생성 후, 필요시 부호 있는 8비트로 뷰 변환
    arr = np.array(int_values, dtype=np.uint8)
    if is_signed:
        arr = arr.view(np.int8)

    # 3차원 배열로 변환 (예: 15 x 4 x 4)
    return arr.reshape((num_cases, rows, cols))

def write_mem_batch(filepath, matrix_batch):
    with open(filepath, 'w') as f:
        for matrix in matrix_batch:
            # 4x4 행렬 하나를 1차원으로 평탄화 (16개 요소)
            flat_array = matrix.flatten()
            for val in flat_array:
                # 32비트 2의 보수 형태로 마스킹하여 8자리 16진수로 출력
                # 한 줄에 하나씩 바로 줄바꿈 처리
                hex_str = f"{(int(val) & 0xFFFFFFFF):08X}"
                f.write(hex_str + "\n")

# --- 실행 부분 ---
if __name__ == "__main__":
    num_cases = 15
    rows = 4
    cols = 4

    # 1. 파일 읽기 (15개의 4x4 행렬 로드)
    matrix_A = read_mem_batch('all_A.mem', num_cases, rows, cols, is_signed=True)
    matrix_B = read_mem_batch('all_B.mem', num_cases, rows, cols, is_signed=True)

    # 2. 배치 행렬 곱 연산
    # 8비트 정수를 곱해서 더하면 범위를 넘어가므로 int32로 캐스팅하여 계산
    matrix_C = np.matmul(matrix_A.astype(np.int32), matrix_B.astype(np.int32))

    # 3. 결과를 다시 .mem 파일로 출력 (골든 데이터 포맷)
    write_mem_batch('result_C.mem', matrix_C)
    
    print("연산 완료! result_C.mem 파일이 골든 데이터 포맷으로 생성되었습니다.")
