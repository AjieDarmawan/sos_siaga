#!/usr/bin/env bash
# Build rilis Polmas Digital (penerima SOS) yang PASTI tersambung ke produksi.
#
#   scripts/build_release.sh aab   # untuk Play Store (wajib android/key.properties)
#   scripts/build_release.sh apk   # untuk dipasang manual
#
# Sebelum build, dicek: server produksi bisa mengirim push SOS ke project Firebase yang sama dengan
# android/app/google-services.json, paket Android cocok, dan kunci unggah ada (untuk aab).
set -euo pipefail

API_URL="https://sos.tip2.co"
PACKAGE="id.polmas.polmas_keamanan"
TARGET="${1:-aab}"
cd "$(dirname "$0")/.."

fail() { echo "✘ $*" >&2; exit 1; }
ok() { echo "✔ $*"; }

[[ "$TARGET" == "aab" || "$TARGET" == "apk" ]] || fail "Pakai: $0 aab|apk"

# 1. Firebase app (google-services.json) — project & paket.
GS=android/app/google-services.json
[[ -f "$GS" ]] || fail "$GS tidak ada (unduh dari Firebase console project siagasos-a61e9)."
APP_PROJECT=$(python3 -c "import json;print(json.load(open('$GS'))['project_info']['project_id'])")
python3 -c "import json,sys;d=json.load(open('$GS'));sys.exit(0 if any(c['client_info']['android_client_info']['package_name']=='$PACKAGE' for c in d['client']) else 1)" \
  || fail "$GS tidak memuat paket $PACKAGE."
ok "google-services.json: project $APP_PROJECT, paket $PACKAGE"

# 2. Server produksi: push SOS aktif & project Firebase sama.
STATUS=$(curl -fsS -m 20 "$API_URL/v1/pk/status") || fail "Tidak bisa menghubungi $API_URL/v1/pk/status (server lama atau mati?)."
SERVER_PUSH=$(python3 -c "import json,sys;print(json.loads(sys.argv[1]).get('server_push'))" "$STATUS")
SERVER_PROJECT=$(python3 -c "import json,sys;print(json.loads(sys.argv[1]).get('fcm_project'))" "$STATUS")
SERVER_CHANNEL=$(python3 -c "import json,sys;print(json.loads(sys.argv[1]).get('fcm_channel'))" "$STATUS")
[[ "$SERVER_PUSH" == "True" ]] || fail "Server produksi belum bisa mengirim push SOS: isi PK_FCM_SERVICE_ACCOUNT di env server lalu restart API."
[[ "$SERVER_PROJECT" == "$APP_PROJECT" ]] || fail "Project Firebase server ($SERVER_PROJECT) ≠ app ($APP_PROJECT): push tidak akan sampai."
grep -q "\"$SERVER_CHANNEL\"" android/app/src/main/kotlin/id/polmas/polmas_keamanan/MainActivity.kt \
  || fail "Kanal push server ($SERVER_CHANNEL) tidak dibuat oleh app (MainActivity.kt)."
ok "Server $API_URL: push aktif, project $SERVER_PROJECT, kanal $SERVER_CHANNEL"

# 3. Kunci unggah Play Store.
if [[ -f android/key.properties ]]; then
  ok "android/key.properties ada (ditandatangani kunci unggah)"
elif [[ "$TARGET" == "aab" ]]; then
  fail "android/key.properties belum ada: AAB bertanda tangan debug ditolak Play Store."
else
  echo "! android/key.properties belum ada: APK ditandatangani kunci debug (hanya untuk pasang manual)."
fi

# 4. Build. API_URL juga sudah default produksi untuk rilis (lib/core/api.dart); ditulis eksplisit agar jelas.
flutter pub get >/dev/null
if [[ "$TARGET" == "aab" ]]; then
  flutter build appbundle --release --dart-define=API_URL="$API_URL"
  OUT=build/app/outputs/bundle/release/app-release.aab
else
  flutter build apk --release --dart-define=API_URL="$API_URL"
  OUT=build/app/outputs/flutter-apk/app-release.apk
fi
# 5. Sirene kanal SOS harus ikut (resource shrinker membuangnya bila res/raw/keep.xml hilang → push tanpa suara).
unzip -l "$OUT" | grep -q "res/raw/sos_siren" || fail "res/raw/sos_siren tidak ada di $OUT: push SOS akan tanpa sirene (cek res/raw/keep.xml)."
ok "Sirene res/raw/sos_siren ada di paket"
VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}')
ok "Selesai: $OUT (versi $VERSION, server $API_URL)"
