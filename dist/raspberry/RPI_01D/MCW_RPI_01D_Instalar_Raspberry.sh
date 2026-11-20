#!/usr/bin/env bash
# ADN MyCarWash RPI-01D - Raspberry Pi OS Desktop / labwc
set -Eeuo pipefail
MODE="${1:-}"
[[ "$MODE" == '--preflight' || "$MODE" == '--apply' ]] || { echo 'Uso: bash MCW_RPI_01D_Instalar_Raspberry.sh --preflight|--apply'; exit 2; }
[[ "$(id -u)" -ne 0 ]] || { echo '[ERROR] Ejecutar como usuario normal; NO root.'; exit 2; }
[[ -e /etc/os-release ]] || { echo '[ERROR] Linux no identificado.'; exit 2; }
source /etc/os-release
[[ "${ID:-}" == 'raspbian' || "${ID:-}" == 'debian' ]] || { echo '[ERROR] Requiere Raspberry Pi OS Desktop.'; exit 2; }
BROWSER="$(command -v chromium || command -v chromium-browser || true)"
[[ -n "$BROWSER" ]] || { echo '[ERROR] Instalar Chromium primero.'; exit 2; }
command -v python3 >/dev/null || { echo '[ERROR] Falta python3.'; exit 2; }
[[ -d "$HOME/.config/labwc" ]] || { echo '[ERROR] Se requiere sesion labwc de Raspberry Pi OS Desktop.'; exit 2; }
BASE="$HOME/.local/share/adn-mycarwash-kiosk"
PROXY_SOURCE="$(dirname "$(readlink -f "$0")")/mcw_kiosk_proxy.py"
[[ -f "$PROXY_SOURCE" ]] || { echo '[ERROR] Copie este instalador y mcw_kiosk_proxy.py en la misma carpeta.'; exit 2; }
python3 -m py_compile "$PROXY_SOURCE"
echo '[OK] Raspberry Pi OS, Chromium, labwc y proxy verificados.'
[[ "$MODE" == '--apply' ]] || { echo '[PRECHECK] Sin cambios. Necesita clave de dispositivo RPI-01C emitida por owner tras despliegue.'; exit 0; }
if [[ ! -r /dev/tty ]]; then echo '[ERROR] Se necesita terminal para ingresar la clave.'; exit 2; fi
printf 'Clave de dispositivo RPI-01C (64 caracteres, NO contrasena del propietario): ' >&2
IFS= read -rs KEY </dev/tty
printf '\n' >&2
[[ "$KEY" =~ ^[a-f0-9]{64}$ ]] || { echo '[ERROR] Clave no valida.'; exit 2; }
mkdir -p "$BASE" "$HOME/.config/labwc" "$HOME/.config/systemd/user"
chmod 700 "$BASE"
STAMP="$(date +%Y%m%d_%H%M%S)"
for file in "$BASE/device.key" "$BASE/mcw_kiosk_proxy.py" "$BASE/start.sh" "$HOME/.config/labwc/autostart" "$HOME/.config/systemd/user/mcw-kiosk-proxy.service"; do
  [[ ! -f "$file" ]] || cp -p "$file" "$file.mcw_$STAMP.bak"
done
umask 077
printf '%s\n' "$KEY" > "$BASE/device.key"
chmod 600 "$BASE/device.key"
unset KEY
cp "$PROXY_SOURCE" "$BASE/mcw_kiosk_proxy.py"
chmod 600 "$BASE/mcw_kiosk_proxy.py"
cat > "$HOME/.config/systemd/user/mcw-kiosk-proxy.service" <<'UNIT'
[Unit]
Description=ADN MyCarWash Raspberry Kiosk Local Reverse Proxy
After=network-online.target
[Service]
Type=simple
ExecStart=/usr/bin/python3 %h/.local/share/adn-mycarwash-kiosk/mcw_kiosk_proxy.py
Restart=always
RestartSec=5
NoNewPrivileges=true
ProtectSystem=full
PrivateTmp=true
[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable --now mcw-kiosk-proxy.service
cat > "$BASE/start.sh" <<'START'
#!/usr/bin/env bash
set -u
BROWSER="$(command -v chromium || command -v chromium-browser)"
while :; do
  until curl -fsS --max-time 3 http://127.0.0.1:8787/ >/dev/null 2>&1; do sleep 5; done
  "$BROWSER" --kiosk --no-first-run --no-default-browser-check --disable-session-crashed-bubble \
    --disable-infobars --disable-translate --disable-pinch --overscroll-history-navigation=0 \
    --user-data-dir="$HOME/.local/share/adn-mycarwash-kiosk/chromium-profile" \
    'http://127.0.0.1:8787/?mcw_kiosk=local'
  sleep 3
done
START
chmod 700 "$BASE/start.sh"
AUTOSTART="$HOME/.config/labwc/autostart"
touch "$AUTOSTART"
# Remove only our own previous line; keep other applications' autostarts.
sed -i '/# MCW_RPI_KIOSK_AUTOSTART$/d' "$AUTOSTART"
printf '\n"%s" >/dev/null 2>&1 & # MCW_RPI_KIOSK_AUTOSTART\n' "$BASE/start.sh" >> "$AUTOSTART"
echo '[OK] Proxy autorizado y arranque Chromium kiosco configurados.'
echo '[SIGUIENTE] Configure Desktop Autologin en raspi-config y reinicie.'
echo '[SEGURIDAD] La clave esta solo en un archivo 0600, nunca en URL ni JavaScript.'
