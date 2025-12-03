
set -euo pipefail
IFS=$'\n\t'

bold() { tput bold; }
normal() { tput sgr0; }
fg() { tput setaf "$1"; }
clear_screen() { printf "\033c"; }

TYPE_SPEED=0.008

type_write() {
  local text="$1"
  if [[ -t 1 ]]; then
    local i
    for ((i=0;i<${#text};i++)); do
      printf "%s" "${text:i:1}"
      sleep "$TYPE_SPEED"
    done
    printf "\n"
  else
    printf "%s\n" "$text"
  fi
}

spinner() {
  local pid=$1; shift
  local msg="${*:-Working...}"
  local sp='|/-\'
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r[%c] %s" "${sp:i++%${#sp}:1}" "$msg"
    sleep 0.08
  done
  printf "\r[✓] %s\n" "$msg"
}

confirm() {
  local question="$1"
  read -r -p "$question [y/N]: " ans
  [[ "$ans" =~ ^([yY][eE]?[sS]?)$ ]]
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    printf "\n"
    fg 1; bold; type_write "This tool must be run as root (sudo). Exiting."; normal; fg 7
    exit 1
  fi
}

press_any_key() {
  printf "\n"
  read -n1 -r -s -p "Press any key to continue..."
  printf "\n"
}

print_header() {
  clear_screen
  fg 2; bold
  cat <<'EOF'
 ____         __        _____           _   _____                
/ ___|  __ _ / _| ___  |_   _|__   ___ | | | ____|_   _____ _ __ 
\___ \ / _` | |_ / _ \   | |/ _ \ / _ \| | |  _| \ \ / / _ \ '__|
 ___) | (_| |  _|  __/   | | (_) | (_) | | | |___ \ V /  __/ |   
|____/ \__,_|_|  \___|   |_|\___/ \___/|_| |_____| \_/ \___|_|   

EOF
  normal
  fg 7
  printf "%s\n" "  Simple Linux System Tool — run with sudo"
  printf "%s\n\n" "  Choose an option below:"
  normal
}

system_info() {
  clear_screen
  fg 4; bold; type_write "Generating system information report..."; normal

  echo "---- OS / Host ----"
  uname -a || true
  echo
  if command -v lsb_release >/dev/null 2>&1; then
    lsb_release -a 2>/dev/null || true
  else
    cat /etc/os-release 2>/dev/null || true
  fi
  echo

  echo "---- CPU ----"
  if command -v lscpu >/dev/null 2>&1; then
    lscpu | sed -n '1,8p'
  else
    cat /proc/cpuinfo | grep -m1 'model name' || true
  fi
  echo

  echo "---- Uptime & Load ----"
  uptime
  echo

  echo "---- Memory (RAM) ----"
  if command -v free >/dev/null 2>&1; then
    free -h
  else
    cat /proc/meminfo | sed -n '1,6p'
  fi
  echo

  echo "---- Storage (mounted filesystems) ----"
  df -hT --total 2>/dev/null || df -h --total 2>/dev/null || true
  echo

  echo "---- Top processes (by CPU) ----"
  ps aux --sort=-%cpu | awk 'NR<=10{printf "%-8s %-7s %-7s %-10s %s\n",$1,$3,$4,$2,$11}' || true
  echo
  echo "---- Top processes (by MEM) ----"
  ps aux --sort=-%mem | awk 'NR<=10{printf "%-8s %-7s %-7s %-10s %s\n",$1,$3,$4,$2,$11}' || true
  echo

  echo "---- systemd: Active services (top 20) ----"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl list-units --type=service --state=running --no-pager | sed -n '1,20p'
  else
    echo "systemctl not available on this system."
  fi
  echo

  echo "---- Listening ports / sockets ----"
  if command -v ss >/dev/null 2>&1; then
    ss -tuln | sed -n '1,40p'
  elif command -v netstat >/dev/null 2>&1; then
    netstat -tuln | sed -n '1,40p'
  else
    echo "Neither ss nor netstat available."
  fi
  echo

  type_write "Report complete."
  press_any_key
}

ensure_ufw() {
  if ! command -v ufw >/dev/null 2>&1; then
    fg 3; type_write "ufw is not installed."
    if confirm "Install ufw now?"; then
      if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y ufw
      elif command -v yum >/dev/null 2>&1; then
        yum install -y ufw || true
      else
        type_write "Package manager not recognized. Please install ufw manually."
        return 1
      fi
      type_write "ufw installed."
      return 0
    else
      type_write "Skipping ufw setup."
      return 1
    fi
  fi
  return 0
}

ufw_status() {
  if ! command -v ufw >/dev/null 2>&1; then
    echo "ufw not found."
    return 0
  fi
  printf "\n"
  ufw status verbose || true
}

ufw_enable() {
  ensure_ufw || return
  if ufw status | grep -q inactive; then
    type_write "Enabling ufw..."
    ufw --force enable
    type_write "ufw enabled."
  else
    type_write "ufw already enabled."
  fi
}

ufw_disable() {
  ensure_ufw || return
  if ufw status | grep -q active; then
    if confirm "Are you sure you want to disable ufw (this opens the system)?"; then
      ufw --force disable
      type_write "ufw disabled."
    else
      type_write "Aborted."
    fi
  else
    type_write "ufw already inactive."
  fi
}

ufw_allow_port() {
  ensure_ufw || return
  read -r -p "Port or port/proto (e.g. 22 or 22/tcp) to ALLOW: " port
  if [[ -z "$port" ]]; then
    type_write "No port provided; aborting."
    return
  fi
  ufw allow "$port"
  type_write "Allowed $port."
}

ufw_deny_port() {
  ensure_ufw || return
  read -r -p "Port or port/proto (e.g. 22 or 22/tcp) to DENY: " port
  if [[ -z "$port" ]]; then
    type_write "No port provided; aborting."
    return
  fi
  ufw deny "$port"
  type_write "Denied $port."
}

firewall_menu() {
  while true; do
    clear_screen
    fg 2; bold; type_write "Firewall (ufw) Control"
    normal
    ufw_status
    echo
    cat <<-EOF
    1) Enable ufw
    2) Disable ufw
    3) Allow a port (ask for port)
    4) Deny a port (ask for port)
    5) Show ufw status
    0) Back to main menu
EOF
    read -r -p "Choice: " choice
    case "$choice" in
      1) ufw_enable; press_any_key ;;
      2) ufw_disable; press_any_key ;;
      3) ufw_allow_port; press_any_key ;;
      4) ufw_deny_port; press_any_key ;;
      5) ufw_status; press_any_key ;;
      0) break ;;
      *) type_write "Invalid choice." ; press_any_key ;;
    esac
  done
}

ssh_remote() {
  clear_screen
  fg 6; bold; type_write "SSH Remote Helper"; normal
  read -r -p "Remote username (default: current user): " ruser
  ruser=${ruser:-$(logname 2>/dev/null || $USER)}
  read -r -p "Remote host (IP or hostname): " rhost
  if [[ -z "$rhost" ]]; then
    type_write "No host provided. Aborting."
    press_any_key
    return
  fi
  read -r -p "Port (default 22): " rport
  rport=${rport:-22}
  read -r -p "Extra ssh options? (leave blank for none): " extra

  type_write "Testing connectivity to $ruser@$rhost:$rport ..."
  if ! command -v nc >/dev/null 2>&1; then
    type_write "nc (netcat) not available; attempting ssh directly."
  else
    if nc -z -w3 "$rhost" "$rport"; then
      type_write "Port $rport is reachable."
    else
      type_write "Warning: Could not reach $rhost:$rport (port closed or filtered). You can still try to SSH."
      if ! confirm "Continue to attempt SSH?"; then
        type_write "Aborted."
        press_any_key
        return
      fi
    fi
  fi

  cmd="ssh -p $rport $extra $ruser@$rhost"
  printf "\nAbout to run: %s\n\n" "$cmd"
  if confirm "Proceed to connect?"; then
    ${cmd}
  else
    type_write "Cancelled."
    press_any_key
  fi
}

main_menu() {
  while true; do
    print_header
    cat <<-EOF
    1) System information report
    2) Firewall (ufw) control
    3) SSH remote helper
    0) Exit
EOF
    read -r -p "Select an option: " opt
    case "$opt" in
      1) system_info ;;
      2) firewall_menu ;;
      3) ssh_remote ;;
      0) type_write "Bye."; exit 0 ;;
      *) type_write "Invalid option." ; press_any_key ;;
    esac
  done
}

trap 'normal; tput cnorm; exit' INT TERM EXIT
tput civis 2>/dev/null || true

require_root
main_menu
