#!/bin/bash

echo "📦 1. Xóa các bản build cũ..."
make clean
rm -f packages/*.deb

echo "🛠 2. Biên dịch bản Tweak mới nhất..."
make package

echo "📂 3. Copy .deb vào thư mục repo (docs/debs)..."
cp packages/*.deb docs/debs/

echo "🔍 4. Đang quét và tạo Packages file (yêu cầu dpkg)..."
cd docs || exit

# Quét tất cả file .deb trong thư mục /debs/ và ghi vào Packages
dpkg-scanpackages -m ./debs > Packages

echo "🗜 5. Đang nén Packages file (Bzip2, XZ, Zstd, Gzip)..."
# Tạo các phiên bản nén để tương thích với Cydia, Sileo, Zebra
bzip2 -fks Packages
gzip -fk Packages
xz -fk Packages 2>/dev/null || echo "Bỏ qua nén xz (chưa cài xz)"
zstd -q -c19 Packages > Packages.zst 2>/dev/null || echo "Bỏ qua nén zstd (chưa cài zstd)"

cd ..

echo "✅ HOÀN TẤT!
Xin hãy chạy các lệnh sau để đẩy lên Github:
  git add docs/
  git commit -m \"Update repo\"
  git push
"
