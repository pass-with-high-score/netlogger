#!/bin/bash

# A helper script to decode iOS NetLogger binary dumps (Protobuf/Hex)

FILE=$1

if [ -z "$FILE" ]; then
    echo "Sử dụng: ./decode_bin.sh <đường_dẫn_tới_file.bin>"
    exit 1
fi

if [ ! -f "$FILE" ]; then
    echo "Lỗi: Không tìm thấy file '$FILE'!"
    exit 1
fi

# Kiểm tra xem protoc đã được cài đặt chưa
if ! command -v protoc &> /dev/null; then
    echo "❌ 'protoc' (Protocol Buffers) chưa được cài đặt."
    echo "👉 Hãy cài đặt nó trên Mac bằng mã lệnh: brew install protobuf"
    exit 1
fi

echo "======================================"
echo "📦 Đang giải mã Protobuf: $(basename "$FILE")"
echo "======================================"

# Decode Protobuf
protoc --decode_raw < "$FILE"
RESULT=$?

if [ $RESULT -ne 0 ]; then
    echo "⚠️ Giải mã Protobuf thất bại! File này có vẻ cấu trúc không phải là Protocol Buffers hợp lệ."
    echo "--------------------------------------"
    echo "Cung cấp Hex Dump (Dữ liệu thô - 20 dòng đầu):"
    hexdump -C "$FILE" | head -n 20
fi
