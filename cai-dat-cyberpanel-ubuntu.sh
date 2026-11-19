#!/usr/bin/env bash
# =============================================================================
#  Cài CyberPanel (bản stable mới nhất) + OpenLiteSpeed trên Ubuntu — v2
#  Khuyên dùng: Ubuntu 22.04 / 24.04 LTS, máy MỚI CÀI (chưa có web server)
#  Hỗ trợ thêm: 20.04 (đã hết hỗ trợ chuẩn), 26.04 (CyberPanel mới hỗ trợ)
#
#  Cài nhanh 1 lệnh (root):
#    curl -fsSL https://raw.githubusercontent.com/lequanth08-cyber/cyberpanel-ubuntu-installer/main/cai-dat-cyberpanel-ubuntu.sh -o cai-dat-cyberpanel-ubuntu.sh && bash cai-dat-cyberpanel-ubuntu.sh -a <IP-quản-trị>
#  (tải file về rồi chạy, KHÔNG chạy kiểu  bash <(curl ...)  vì cần chạy lại trong tmux)
#
#  Ví dụ khác:
#    bash cai-dat-cyberpanel-ubuntu.sh -a 203.0.113.10        # cài + chỉ IP này vào được panel
#    CP_ADMIN_PASS='MatKhau@123' bash cai-dat-cyberpanel-ubuntu.sh -a 203.0.113.10
#    bash cai-dat-cyberpanel-ubuntu.sh -m -y                  # tối giản, không hỏi gì
#
#  Tuỳ chọn:
#    -a <IP,IP/CIDR>  Chỉ các IP này được vào cổng 8090 (panel) và 7080 (OLS WebAdmin)
#                     Bỏ trống = mở cho mọi IP (KHÔNG khuyên dùng)
#    -p <mật khẩu>    Mật khẩu admin (>= 8 ký tự). Nên dùng biến CP_ADMIN_PASS thay
#                     cho -p để mật khẩu không lộ trong lịch sử lệnh / danh sách tiến trình.
#                     Không đặt = sinh ngẫu nhiên 20 ký tự
#    -m               Minimal: bỏ Postfix, PowerDNS, Pure-FTPd
#    -n               Không cài Memcached + Redis (mặc định CÓ)
#    -H <hostname>    Đặt hostname (FQDN) trước khi cài
#    -z <múi giờ>     Đặt múi giờ, vd: Asia/Ho_Chi_Minh (mặc định giữ nguyên)
#    -s               Bỏ qua apt upgrade
#    -y               Tự trả lời "có", không hỏi (dùng cho cloud-init / chạy hàng loạt)
#    -i               Interactive: để trình cài gốc tự hỏi từng bước
#    -T               Không tự chạy trong tmux
#    -h               Trợ giúp
#
#  Rớt SSH giữa chừng? Đăng nhập lại và gõ:  tmux attach -t cyberpanel
# =============================================================================
set -Eeuo pipefail

# ---------- Màu & log ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[i]${NC} $*"; }
ok()    { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
die()   { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }
trap 'die "Lỗi ở dòng $LINENO. Xem log: ${LOG_FILE:-không có}"' ERR

SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"
TMUX_SESSION="cyberpanel"
STATE_FILE="/root/.cyberpanel-setup.state"

# Hỏi có/không. Có -y thì tự "có"; không có TTY và không -y thì dừng.
confirm() {
  local q="$1" ans
  (( ASSUME_YES )) && return 0
  [[ -t 0 ]] || die "Cần xác nhận \"$q\" nhưng không có bàn phím. Chạy lại với -y."
  read -r -p "$q (y/N): " ans
  [[ "${ans,,}" == "y" ]]
}

# ---------- Tham số ----------
ADMIN_PASS="${CP_ADMIN_PASS:-}"; ALLOW_IPS=""; MINIMAL=0; ADDONS=1; NEW_HOSTNAME=""
TIMEZONE=""; SKIP_UPGRADE=0; ASSUME_YES=0; INTERACTIVE=0; NO_TMUX=0; RESUME_FILE=""
usage() { sed -n '2,31p' "$SELF" | sed 's/^# \{0,1\}//'; exit 0; }
while getopts ":a:p:mnH:z:syiTR:h" opt; do
  case "$opt" in
    a) ALLOW_IPS="$OPTARG" ;;
    p) ADMIN_PASS="$OPTARG" ;;
    m) MINIMAL=1 ;;
    n) ADDONS=0 ;;
    H) NEW_HOSTNAME="$OPTARG" ;;
    z) TIMEZONE="$OPTARG" ;;
    s) SKIP_UPGRADE=1 ;;
    y) ASSUME_YES=1 ;;
    i) INTERACTIVE=1 ;;
    T) NO_TMUX=1 ;;
    R) RESUME_FILE="$OPTARG" ;;   # nội bộ: chạy tiếp bên trong tmux
    h) usage ;;
    :) die "Tuỳ chọn -$OPTARG cần giá trị." ;;
    *) die "Tuỳ chọn không hợp lệ: -$OPTARG (xem -h)" ;;
  esac
done

# Nạp lại tham số khi chạy tiếp trong tmux (mật khẩu đi qua file chmod 600, không qua dòng lệnh)
if [[ -n "$RESUME_FILE" ]]; then
  [[ -f "$RESUME_FILE" ]] || die "Không thấy file trạng thái $RESUME_FILE"
  # shellcheck disable=SC1090
  source "$RESUME_FILE"; rm -f "$RESUME_FILE"
fi

# ---------- 1. Quyền root ----------
[[ $EUID -eq 0 ]] || die "Hãy chạy bằng root:  sudo -i  rồi chạy lại script."

# ---------- 2. Kiểm tra hệ điều hành ----------
[[ -r /etc/os-release ]] || die "Không đọc được /etc/os-release."
# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || die "Script chỉ dành cho Ubuntu (máy đang chạy: ${PRETTY_NAME:-không rõ})."
case "${VERSION_ID:-}" in
  22.04|24.04) ok "Hệ điều hành: $PRETTY_NAME" ;;
  20.04) warn "Ubuntu 20.04 đã hết hỗ trợ chuẩn — nên dùng 22.04 / 24.04." ;;
  26.04) warn "Ubuntu 26.04: CyberPanel mới hỗ trợ (Python 3.12 từ PPA ngoài) — cài cho khách nên dùng 22.04 / 24.04." ;;
  *) die "Ubuntu $VERSION_ID chưa được CyberPanel hỗ trợ. Dùng 22.04 / 24.04 LTS." ;;
esac
[[ "$(uname -m)" == "x86_64" ]] || warn "Kiến trúc $(uname -m): CyberPanel chủ yếu hỗ trợ x86_64, có thể lỗi."
[[ -d /usr/local/CyberCP ]] && die "CyberPanel đã được cài (/usr/local/CyberCP). Nâng cấp:  sh <(curl -s https://raw.githubusercontent.com/usmannasir/cyberpanel/stable/preUpgrade.sh)"

# ---------- 3. Kiểm tra tham số ----------
if [[ -n "$ADMIN_PASS" ]] && (( ${#ADMIN_PASS} < 8 )); then
  die "Mật khẩu admin phải từ 8 ký tự trở lên."
fi
IFS=',' read -r -a ALLOW_LIST <<< "${ALLOW_IPS// /}"
for ip in "${ALLOW_LIST[@]}"; do
  [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?$ || "$ip" =~ ^[0-9A-Fa-f]*:[0-9A-Fa-f:]*(/[0-9]{1,3})?$ ]] \
    || die "IP không hợp lệ ở -a: $ip"
done
[[ -z "$TIMEZONE" || -e "/usr/share/zoneinfo/$TIMEZONE" ]] || die "Múi giờ không tồn tại: $TIMEZONE"

# ---------- 4. Tự chạy trong tmux để rớt SSH không hỏng cài đặt ----------
# Chỉ áp dụng khi có màn hình (TTY); cloud-init / chạy nền thì không cần.
if [[ -z "$RESUME_FILE" && -z "${TMUX:-}" && -z "${STY:-}" && $NO_TMUX -eq 0 && -t 0 ]]; then
  [[ -f "$SELF" ]] || die "Hãy tải script về file rồi chạy (không dùng bash <(curl ...)), hoặc thêm -T."
  if ! command -v tmux >/dev/null; then
    info "Cài tmux để giữ phiên cài khi rớt SSH..."
    DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y tmux >/dev/null 2>&1 \
      || die "Không cài được tmux. Chạy lại với -T để bỏ qua tmux."
  fi
  tmux has-session -t "$TMUX_SESSION" 2>/dev/null \
    && die "Đang có phiên cài khác. Xem tiếp:  tmux attach -t $TMUX_SESSION"
  ( umask 077
    declare -p ADMIN_PASS ALLOW_IPS MINIMAL ADDONS NEW_HOSTNAME TIMEZONE SKIP_UPGRADE \
               ASSUME_YES INTERACTIVE > "$STATE_FILE" )
  tmux new-session -d -s "$TMUX_SESSION" \
    "bash '$SELF' -R '$STATE_FILE'; echo; read -r -p 'Đã chạy xong. Nhấn Enter để đóng phiên tmux...'"
  echo -e "${GREEN}Đang chạy trong tmux phiên '$TMUX_SESSION'.${NC} Rớt SSH thì đăng nhập lại và gõ: tmux attach -t $TMUX_SESSION"
  sleep 1
  exec tmux attach -t "$TMUX_SESSION"
fi

LOG_FILE="/root/cyberpanel-install-$(date +%Y%m%d-%H%M%S).log"
touch "$LOG_FILE"; chmod 600 "$LOG_FILE"

# ---------- 5. Tài nguyên ----------
RAM_MB=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
DISK_GB=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
info "RAM: ${RAM_MB} MB | Ổ trống (/): ${DISK_GB} GB"
(( DISK_GB >= 10 )) || die "Cần tối thiểu 10 GB trống ở phân vùng /."
if (( RAM_MB < 1024 )) && ! swapon --show | grep -q .; then
  warn "RAM < 1 GB và chưa có swap → tạo swap 2 GB."
  fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
  chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  ok "Đã bật swap 2 GB."
fi

# ---------- 6. Máy đã có web server / database ----------
for svc in apache2 nginx mysql mariadb; do
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    warn "Dịch vụ '$svc' đang chạy — CyberPanel nên cài trên máy MỚI để tránh xung đột."
    confirm "Vẫn tiếp tục?" || die "Đã huỷ."
  fi
done

# ---------- 7. Hostname & múi giờ ----------
if [[ -n "$NEW_HOSTNAME" ]]; then
  hostnamectl set-hostname "$NEW_HOSTNAME"
  grep -qw "$NEW_HOSTNAME" /etc/hosts || echo "127.0.1.1 $NEW_HOSTNAME" >> /etc/hosts
  ok "Hostname: $NEW_HOSTNAME"
fi
if [[ -n "$TIMEZONE" ]]; then
  timedatectl set-timezone "$TIMEZONE" && ok "Múi giờ: $TIMEZONE"
fi

# ---------- 8. Cập nhật hệ thống ----------
export DEBIAN_FRONTEND=noninteractive
info "Cập nhật danh sách gói..."
apt-get update -y >>"$LOG_FILE" 2>&1
if (( SKIP_UPGRADE == 0 )); then
  info "Nâng cấp hệ thống (vài phút)..."
  apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
    upgrade -y >>"$LOG_FILE" 2>&1
fi
apt-get install -y curl wget ca-certificates >>"$LOG_FILE" 2>&1
ok "Hệ thống sẵn sàng."

if [[ -f /var/run/reboot-required ]]; then
  warn "Có bản cập nhật kernel/thư viện cần khởi động lại."
  if (( ! ASSUME_YES )) && [[ -t 0 ]] && confirm "Khởi động lại NGAY rồi chạy lại script (khuyên dùng)?"; then
    echo "Sau khi máy lên lại, chạy lại đúng lệnh cũ (thêm -s để bỏ qua bước nâng cấp)."
    sleep 3; reboot; exit 0
  fi
  warn "Tiếp tục cài trên kernel hiện tại — nhớ reboot sau khi cài xong."
fi

# ---------- 9. Tải trình cài chính thức ----------
WORKDIR=$(mktemp -d /root/cyberpanel-setup.XXXX)
cd "$WORKDIR"
info "Tải trình cài CyberPanel chính thức..."
curl -fsSL https://cyberpanel.net/install.sh -o install.sh \
  || wget -qO install.sh https://cyberpanel.net/install.sh \
  || die "Không tải được https://cyberpanel.net/install.sh"
[[ -s install.sh ]] || die "File install.sh rỗng."

# ---------- 10. Cài đặt ----------
# Trình cài gốc đôi khi trả mã lỗi dù đã cài xong → tắt bẫy lỗi, kiểm tra thật ở bước 11
trap - ERR
set +e
echo
info "Bắt đầu cài CyberPanel — thường 15–40 phút. Log: $LOG_FILE"
echo
# Mật khẩu TẠM (lộ trong danh sách tiến trình lúc cài cũng vô hại) → đổi sang mật khẩu thật ở bước 12
TEMP_PASS="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)"
if (( INTERACTIVE == 1 )); then
  bash install.sh 2>&1 | tee -a "$LOG_FILE"
else
  ARGS=(-v ols -p "$TEMP_PASS")    # OpenLiteSpeed (miễn phí)
  (( ADDONS == 1 )) && ARGS+=(-a)   # Memcached + Redis
  (( MINIMAL == 1 )) && ARGS+=(-m)  # Bỏ Mail/DNS/FTP
  bash install.sh "${ARGS[@]}" 2>&1 | tee -a "$LOG_FILE"
fi

# ---------- 11. Kiểm tra panel chạy thật ----------
echo
info "Kiểm tra CyberPanel sau cài..."
PANEL_OK=0
for _ in $(seq 1 24); do   # chờ tối đa ~2 phút
  code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 https://127.0.0.1:8090/ || true)
  if systemctl is-active --quiet lscpd && [[ "$code" =~ ^(200|301|302)$ ]]; then PANEL_OK=1; break; fi
  sleep 5
done
(( PANEL_OK )) || die "CyberPanel chưa chạy (lscpd / cổng 8090 không trả lời). Xem $LOG_FILE và /var/log/installLogs.txt"
ok "Panel đang chạy ở cổng 8090."

# ---------- 12. Đặt mật khẩu admin thật ----------
# Không tự đặt mật khẩu → dùng luôn mật khẩu ngẫu nhiên lúc cài (chỉ nằm trong file chmod 600).
FINAL_PASS="$TEMP_PASS"
if (( INTERACTIVE == 0 )) && [[ -n "$ADMIN_PASS" ]]; then
  if command -v adminPass >/dev/null && adminPass "$ADMIN_PASS" >>"$LOG_FILE" 2>&1; then
    FINAL_PASS="$ADMIN_PASS"; ok "Đã đặt mật khẩu admin theo yêu cầu."
  else
    FINAL_PASS="$TEMP_PASS  (KHÔNG đổi được sang mật khẩu anh/chị đặt — đổi tay:  adminPass 'MatKhauMoi')"
    warn "adminPass lỗi → vẫn dùng mật khẩu sinh lúc cài (đã lưu trong file)."
  fi
fi

# ---------- 13. Khoá cổng 8090 / 7080 theo IP quản trị ----------
# Trình cài gốc dùng firewalld và mở 8090/7080 cho MỌI IP bằng rich rule.
if (( ${#ALLOW_LIST[@]} > 0 )); then
  if systemctl is-active --quiet firewalld; then
    for port in 8090 7080; do
      # Gỡ luật mở-cho-tất-cả (rich rule + port thường nếu có)
      while IFS= read -r rule; do
        [[ -n "$rule" ]] && firewall-cmd --permanent --zone=public --remove-rich-rule="$rule" >/dev/null
      done < <(firewall-cmd --permanent --zone=public --list-rich-rules | grep "port=\"$port\"" | grep -v 'source address="[^0]' || true)
      firewall-cmd --permanent --zone=public --remove-port="$port/tcp" >/dev/null 2>&1 || true
      for ip in "${ALLOW_LIST[@]}"; do
        fam=ipv4; [[ "$ip" == *:* ]] && fam=ipv6
        firewall-cmd --permanent --zone=public --add-rich-rule="rule family=\"$fam\" source address=\"$ip\" port port=\"$port\" protocol=\"tcp\" accept" >/dev/null
      done
    done
    firewall-cmd --reload >/dev/null
    ok "Cổng 8090/7080 chỉ mở cho: ${ALLOW_LIST[*]}"
  else
    warn "firewalld không chạy — chưa khoá được cổng 8090/7080 theo IP."
  fi
else
  warn "Chưa giới hạn IP: cổng 8090 đang mở cho cả Internet. Nên chạy lại phần này với -a <IP của anh/chị>."
fi

# ---------- 14. Báo khi CyberPanel có bản mới (không tự nâng cấp) ----------
cat > /usr/local/sbin/cyberpanel-update-check <<'EOS'
#!/usr/bin/env bash
# So sánh bản CyberPanel đang cài với bản mới nhất; có bản mới thì báo khi đăng nhập SSH.
NOTICE=/etc/cyberpanel-update-notice
latest=$(curl -fsS --max-time 15 https://cyberpanel.net/version.txt) || exit 0
lv=$(grep -o '"version":"[^"]*"' <<<"$latest" | cut -d'"' -f4)
lb=$(grep -o '"build":[0-9]*' <<<"$latest" | cut -d: -f2)
Q="SELECT CONCAT(currentVersion,'.',build) FROM cyberpanel.baseTemplate_version LIMIT 1"
cur=$(mysql -N -e "$Q" 2>/dev/null || mysql -uroot -p"$(cat /etc/cyberpanel/mysqlPassword 2>/dev/null)" -N -e "$Q" 2>/dev/null)
[[ -n "$lv" && -n "$cur" ]] || exit 0
if [[ "$cur" != "$lv.$lb" ]]; then
  echo "[CyberPanel] Có bản mới $lv (build $lb), máy đang chạy $cur. Đọc ghi chú phát hành rồi nâng cấp:" > "$NOTICE"
  echo "  sh <(curl -s https://raw.githubusercontent.com/usmannasir/cyberpanel/stable/preUpgrade.sh)" >> "$NOTICE"
else
  rm -f "$NOTICE"
fi
EOS
chmod 700 /usr/local/sbin/cyberpanel-update-check
echo "17 4 * * * root /usr/local/sbin/cyberpanel-update-check" > /etc/cron.d/cyberpanel-update-check
cat > /etc/profile.d/zz-cyberpanel-update-notice.sh <<'EOS'
[ -r /etc/cyberpanel-update-notice ] && printf '\033[1;33m%s\033[0m\n' "$(cat /etc/cyberpanel-update-notice)"
EOS
/usr/local/sbin/cyberpanel-update-check || true
ok "Đã đặt lịch kiểm tra bản mới hằng ngày (chỉ báo, không tự nâng cấp)."

# ---------- 15. Lưu thông tin & tổng kết ----------
SERVER_IP=$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
CRED_FILE="/root/cyberpanel-admin.txt"
( umask 077
  {
    echo "CyberPanel URL : https://${SERVER_IP}:8090"
    echo "Tài khoản      : admin"
    if (( INTERACTIVE == 0 )); then echo "Mật khẩu       : ${FINAL_PASS}"; else echo "Mật khẩu       : (đã nhập lúc cài)"; fi
    echo "OLS WebAdmin   : https://${SERVER_IP}:7080 (mật khẩu: cat /etc/cyberpanel/webadmin_passwd)"
    echo "IP được vào    : ${ALLOW_IPS:-tất cả (chưa giới hạn)}"
    echo "Cài ngày       : $(date '+%d/%m/%Y %H:%M')"
  } > "$CRED_FILE" )
rm -rf "$WORKDIR"

echo
echo -e "${GREEN}==================================================================${NC}"
echo -e "${GREEN}  CÀI ĐẶT CYBERPANEL HOÀN TẤT${NC}"
echo -e "  Đăng nhập : ${YELLOW}https://${SERVER_IP}:8090${NC}   (tài khoản: admin)"
echo -e "  Mật khẩu  : trong ${YELLOW}${CRED_FILE}${NC} (chỉ root đọc được)"
echo -e "  Log       : $LOG_FILE"
echo -e "${GREEN}==================================================================${NC}"
echo "Việc nên làm tiếp:"
echo "  1. Đăng nhập → Users → Modify User → bật Two-Factor Authentication (2FA) cho admin."
echo "  2. Mở cổng 8090 (theo IP), 80, 443 ở firewall của nhà cung cấp VPS nếu có."
[[ -f /var/run/reboot-required ]] && echo "  3. Khởi động lại máy để dùng kernel mới:  reboot"
exit 0
