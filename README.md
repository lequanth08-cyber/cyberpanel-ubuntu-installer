# Cài CyberPanel trên Ubuntu bằng 1 lệnh

Script cài CyberPanel (bản stable mới nhất) + OpenLiteSpeed, kèm kiểm tra trước khi cài, chống rớt SSH (tmux) và khoá cổng panel theo IP.

Khuyên dùng **Ubuntu 22.04 / 24.04 LTS**, máy **mới cài**, RAM ≥ 1 GB, ổ trống ≥ 10 GB.

## Cài nhanh

Đăng nhập VPS bằng **root** rồi chạy (thay `203.0.113.10` bằng IP của anh/chị — chỉ IP này vào được panel):

```bash
curl -fsSL https://raw.githubusercontent.com/lequanth08-cyber/cyberpanel-ubuntu-installer/main/cai-dat-cyberpanel-ubuntu.sh -o cai-dat-cyberpanel-ubuntu.sh && bash cai-dat-cyberpanel-ubuntu.sh -a 203.0.113.10
```

Tự đặt mật khẩu admin (không lộ trong lịch sử lệnh nếu gõ dấu cách ở đầu):

```bash
 curl -fsSL https://raw.githubusercontent.com/lequanth08-cyber/cyberpanel-ubuntu-installer/main/cai-dat-cyberpanel-ubuntu.sh -o cai-dat-cyberpanel-ubuntu.sh && CP_ADMIN_PASS='MatKhau@Manh123' bash cai-dat-cyberpanel-ubuntu.sh -a 203.0.113.10
```

Cài xong: mở `https://IP-VPS:8090`, tài khoản `admin`, mật khẩu nằm trong `/root/cyberpanel-admin.txt`.

Rớt SSH giữa chừng: đăng nhập lại và gõ `tmux attach -t cyberpanel`.

## Tuỳ chọn

| Tuỳ chọn | Ý nghĩa |
|---|---|
| `-a <IP,IP/CIDR>` | Chỉ các IP này vào được cổng 8090 / 7080 |
| `-p <mật khẩu>` | Mật khẩu admin (nên dùng biến `CP_ADMIN_PASS`) |
| `-m` | Tối giản: bỏ Mail, DNS, FTP |
| `-n` | Không cài Memcached + Redis |
| `-H <hostname>` | Đặt hostname trước khi cài |
| `-z <múi giờ>` | Đặt múi giờ, vd `Asia/Ho_Chi_Minh` |
| `-s` | Bỏ qua `apt upgrade` |
| `-y` | Không hỏi gì (cloud-init / chạy hàng loạt) |
| `-i` | Để trình cài gốc hỏi từng bước |
| `-T` | Không chạy trong tmux |

## Script làm gì

1. Kiểm tra root, phiên bản Ubuntu, RAM, ổ đĩa; tạo swap nếu RAM < 1 GB.
2. Cảnh báo nếu máy đã có Apache / Nginx / MySQL.
3. Cập nhật hệ thống, hỏi reboot nếu kernel mới.
4. Tải và chạy trình cài chính thức `https://cyberpanel.net/install.sh`.
5. Kiểm tra panel chạy thật (dịch vụ `lscpd` + cổng 8090).
6. Đặt mật khẩu admin, khoá cổng 8090/7080 theo IP bằng firewalld.
7. Đặt lịch kiểm tra hằng ngày, báo khi CyberPanel có bản mới (không tự nâng cấp).

Sau khi cài: bật xác thực 2 lớp (2FA) cho tài khoản admin trong panel.
