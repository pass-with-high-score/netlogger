Đây là danh sách gợi ý theo mức độ ưu tiên, chia thành **Quick Win** (dễ làm) và **Advanced** (nâng cao):

### 🎯 Quick Win (có thể làm ngay)

| # | Tính năng | Mô tả |
|---|-----------|-------|
| 1 | **Bộ lọc theo Status** | Thêm Scope Bar dưới Search: `All` / `2xx` / `3xx` / `4xx+` / `Error` để lọc nhanh |
| 2 | **Share/Export** | Nút Share trên Detail View → xuất request dưới dạng **cURL command** hoặc text file |
| 3 | **Badge đếm log mới** | Hiện badge số trên nút "View Logs" ở trang Settings chính |
| 4 | **Swipe-to-delete** | Vuốt trái từng dòng log để xóa riêng lẻ thay vì phải xóa tất cả |
| 5 | **Auto-refresh Timer** | Tự động refresh list mỗi 3-5 giây khi đang mở (toggle bật/tắt) |
| 6 | **Response Time** | Tính thời gian phản hồi (ms) từ lúc gửi request → nhận response, hiện trên cell |

### 🚀 Advanced (nâng cấp lớn)

| # | Tính năng | Mô tả |
|---|-----------|-------|
| 7 | **Floating Window** | Cửa sổ nổi nhỏ trong app (như Flex/MTXX) hiện real-time log mà không cần vào Settings |
| 8 | **Domain Blacklist** | Cho phép ẩn các domain rác (analytics, tracking, ads) để tập trung vào API thật |
| 9 | **Replay Request** | Gửi lại 1 request đã capture (giống Postman) |
| 10 | **HAR Export** | Xuất toàn bộ log thành file `.har` để import vào Chrome DevTools hoặc Proxyman |
| 11 | **Diff View** | So sánh 2 request cạnh nhau để tìm khác biệt |
| 12 | **SSL Pinning Bypass** | Tích hợp sẵn bypass SSL pinning cho các app cứng đầu |

### 🎨 UI/UX Polish

| # | Cải thiện | Mô tả |
|---|-----------|-------|
| A | **Dark mode tối ưu** | Màu method badge tối hơn trong dark mode để không chói mắt |
| B | **Thống kê tổng quan** | Header ở đầu list hiện: Tổng requests / Thành công / Lỗi / Tổng dung lượng |
| C | **Group by App** | Cho phép nhóm log theo tên ứng dụng thay vì xếp theo thời gian |
| D | **Haptic feedback** | Rung nhẹ khi copy thành công |

---

Bạn thích cái nào? Chọn 1-2 cái tôi sẽ làm luôn! Cá nhân tôi recommend **#1 (Bộ lọc Status)** + **#2 (Export cURL)** + **#B (Thống kê)** vì chúng nâng UX lên rất nhiều mà không quá phức tạp.