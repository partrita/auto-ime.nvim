#!/usr/bin/env bash
# auto-ime-daemon.sh
# Lightweight local listener for controlling macOS / Linux local IME from remote SSH Neovim sessions.
#
# Usage:
#   1. Run this script on your local macOS/Linux machine:
#      ./scripts/auto-ime-daemon.sh
#
#   2. Connect to your remote server with reverse port forwarding:
#      ssh -R 8989:127.0.0.1:8989 user@remote-server
#
#   3. Use Neovim on the remote server! When leaving Insert/Cmdline mode,
#      remote Neovim will signal this daemon to switch your local IME to Latin.

PORT="${1:-8989}"
OS="$(uname -s)"
trap "echo -e '\nDaemon stopped.'; exit 0" SIGINT SIGTERM

# Determine the local IME switch command
IME_CMD=""
if [ "$OS" = "Darwin" ]; then
    if command -v macism >/dev/null 2>&1; then
        IME_CMD="macism com.apple.keylayout.ABC"
    else
        echo "[Error] 'macism' is not installed on this Mac."
        echo "Please install it via Homebrew: brew install macism"
        exit 1
    fi
elif [ "$OS" = "Linux" ]; then
    if command -v fcitx5-remote >/dev/null 2>&1; then
        IME_CMD="fcitx5-remote -c"
    elif command -v ibus >/dev/null 2>&1; then
        IME_CMD="ibus engine xkb:us::eng"
    else
        echo "[Error] Neither 'fcitx5-remote' nor 'ibus' found on this Linux machine."
        exit 1
    fi
else
    echo "[Error] Unsupported OS for this script: $OS. On Windows, use auto-ime-daemon.ps1."
    exit 1
fi

echo "=========================================================="
echo " [auto-ime] $OS SSH Bridge Daemon running on 127.0.0.1:$PORT"
echo " Connect with: ssh -R ${PORT}:127.0.0.1:${PORT} user@remote"
echo " Trigger command: $IME_CMD"
echo " Waiting for signals from remote Neovim... (Ctrl+C to stop)"
echo "=========================================================="

# Check if python3 is available (preferred for clean, high-performance socket handling)
if command -v python3 >/dev/null 2>&1; then
    python3 -c "
import socket, subprocess, sys, datetime, shlex

port = int(sys.argv[1])
ime_cmd = shlex.split(sys.argv[2])

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(('127.0.0.1', port))
server.listen(10)
server.settimeout(0.5)

try:
    while True:
        try:
            client, addr = server.accept()
        except socket.timeout:
            continue
        now = datetime.datetime.now().strftime('%H:%M:%S.%f')[:-3]
        subprocess.run(ime_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print(f'[{now}] Signal received! Switched local IME to Latin')
        try:
            client.sendall(b'HTTP/1.0 200 OK\r\nContent-Length: 2\r\n\r\nOK')
        except Exception:
            pass
        client.close()
except (KeyboardInterrupt, SystemExit):
    pass
finally:
    server.close()
" "$PORT" "$IME_CMD"
else
    # Fallback to nc (netcat) loop
    while true; do
        nc -l 127.0.0.1 "$PORT" >/dev/null 2>&1
        $IME_CMD >/dev/null 2>&1
        now=$(date +"%T")
        echo "[$now] Signal received! Switched local IME to Latin"
    done
fi
