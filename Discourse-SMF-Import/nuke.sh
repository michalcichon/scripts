#!/usr/bin/env bash
set -euo pipefail

# ======= KONFIG DO EDYCJI =======
DISCOURSE_DIR="/var/discourse"

# Co kasujemy
NUKE_POSTGRES=1
NUKE_UPLOADS=1
NUKE_REDIS=0          # ustaw 1 jeśli chcesz też zresetować redis

# Czy uruchomić import po rebuild
RUN_IMPORT=1

# Kontener z MariaDB SMF:
SMF_DB_CONTAINER="smf-maria"

# Połączenie do bazy SMF (domyślnie z Twojego setupu)
DB_HOST="${DB_HOST:-172.17.0.1}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-root}"
DB_PASS="${DB_PASS:-pass}"          # UWAGA: będzie użyte jako -pHASLO (bez spacji)
DB_NAME="${DB_NAME:-smfdb}"
DB_PREFIX="${DB_PREFIX:-smf2_}"     # np. smf_ / smf2_ lub puste
TZ="${TZ:-Europe/Warsaw}"

# Ścieżki do źródeł SMF
SMF_ROOT_HOST="${SMF_ROOT_HOST:-/var/discourse/shared/standalone/import/smf}"
SMF_ROOT_IN_IMPORT="/shared/import/smf"

# Wymuś bez potwierdzenia: ustaw YES=1
YES="${YES:-0}"
# ======= KONIEC KONFIGU ========

die(){ echo "ERROR: $*" >&2; exit 1; }
info(){ echo -e "\033[1;36m$*\033[0m"; }

require_root(){
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    exec sudo -E bash "$0" "$@"
  fi
}

confirm(){
  if [[ "$YES" == "1" ]]; then return 0; fi
  echo "To skasuje dane Discourse:"
  [[ "$NUKE_POSTGRES" == "1" ]] && echo "  - shared/standalone/postgres_data"
  [[ "$NUKE_UPLOADS"  == "1" ]] && echo "  - shared/standalone/uploads"
  [[ "$NUKE_REDIS"    == "1" ]] && echo "  - shared/standalone/redis_data"
  echo "Źródła importu zostają: $SMF_ROOT_HOST"
  read -r -p "Kontynuować? (type YES): " ans
  [[ "$ans" == "YES" ]] || die "Przerwano."
}

launcher(){ (cd "$DISCOURSE_DIR" && ./launcher "$@"); }

tune_mariadb(){
  info "Podkręcanie parametrów MariaDB (timeouts/packet)…"
  docker exec -i "$SMF_DB_CONTAINER" mariadb -u"$DB_USER" -p"$DB_PASS" -e "
    SET GLOBAL max_allowed_packet=1073741824;
    SET GLOBAL net_read_timeout=1800;
    SET GLOBAL net_write_timeout=1800;
    SET GLOBAL wait_timeout=86400;
    SET GLOBAL interactive_timeout=86400;
    SET GLOBAL innodb_lock_wait_timeout=300;
    SHOW VARIABLES WHERE Variable_name IN
    ('max_allowed_packet','net_read_timeout','net_write_timeout','wait_timeout','interactive_timeout','innodb_lock_wait_timeout');
  " || echo "WARN: Nie udało się podkręcić MariiDB (pomijam)."
}

run_import(){
  [[ "$RUN_IMPORT" == "1" ]] || { info "RUN_IMPORT=0 → pomijam uruchomienie importu."; return 0; }
  info "Start importu SMF…"

  # sprawdź, czy w kontenerze widać pliki SMF
  if [[ ! -e "$SMF_ROOT_HOST" ]]; then
    die "Brak źródeł SMF pod $SMF_ROOT_HOST"
  fi

  local PFX_ARG=""
  [[ -n "$DB_PREFIX" ]] && PFX_ARG="-f $DB_PREFIX"

  # RACK_MINI_PROFILER=off + RAILS_ENV=production + hasło bez spacji: -pHASLO
  local IMPORT_CMD
  IMPORT_CMD="su - discourse -c 'cd /var/www/discourse && \
    RACK_MINI_PROFILER=off RAILS_ENV=production \
    bundle exec ruby script/import_scripts/smf2.rb \
      $SMF_ROOT_IN_IMPORT -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASS -d $DB_NAME $PFX_ARG -t $TZ'"

  # odpal komendę wewnątrz kontenera 'import'
  docker exec -i import bash -lc "$IMPORT_CMD"
}

main(){
  require_root "$@"
  command -v docker >/dev/null || die "Brak docker w PATH"
  [[ -d "$DISCOURSE_DIR" ]] || die "Nie znaleziono $DISCOURSE_DIR"

  confirm

  info "Zatrzymuję kontenery…"
  launcher stop import || true
  launcher stop app || true

  info "Kasuję dane…"
  pushd "$DISCOURSE_DIR/shared/standalone" >/dev/null
    [[ "$NUKE_POSTGRES" == "1" ]] && rm -rf postgres_data
    [[ "$NUKE_UPLOADS"  == "1" ]] && rm -rf uploads
    [[ "$NUKE_REDIS"    == "1" ]] && rm -rf redis_data
  popd >/dev/null

  info "Rebuild app (to zastosuje hooki z app.yml)…"
  launcher rebuild app

  info "Rebuild import…"
  launcher rebuild import

  tune_mariadb
  run_import

  info "DONE. Jeśli trzeba, możesz teraz zrebake’ować posty:"
  echo "  cd /var/discourse && ./launcher enter app"
  echo "  su - discourse && cd /var/www/discourse && RAILS_ENV=production bundle exec rake posts:rebake"
}

main "$@"
