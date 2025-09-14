#!/usr/bin/env bash
# Resetuje instancję Discourse do „zera”, stawia kontener import, uruchamia import SMF,
# a potem podnosi docelowy 'app'. Idempotentne.
#
# ZALECENIA:
#  - Uruchamiaj jako root:  sudo YES=1 /var/discourse/shared/standalone/nuke.sh
#  - Domyślnie importer czyta DB z /shared/import/smf/Settings.php (wewnątrz kontenera).
#    Upewnij się, że ten mount istnieje w kontenerze 'import' (containers/import.yml).
#
# SZYBKIE PRZEŁĄCZNIKI (env):
#   YES=1                 # pomiń pytanie o potwierdzenie
#   RUN_IMPORT=0          # zrób tylko wipe + rebuild kontenerów (bez importu)
#   OVERRIDE_DB_HOST=IP   # jeśli Settings.php ma 'localhost' i trzeba nadpisać host (np. 172.17.0.1)
#   DB_PASS=pass          # (opcjonalne) pozwala podkręcić parametry MariaDB (tuning)
#
# PRZYKŁADY:
#   sudo YES=1 /var/discourse/shared/standalone/nuke.sh
#   sudo YES=1 RUN_IMPORT=0 /var/discourse/shared/standalone/nuke.sh
#   sudo YES=1 OVERRIDE_DB_HOST=172.17.0.1 /var/discourse/shared/standalone/nuke.sh

set -euo pipefail

############################################
# Napraw PATH pod sudo + wrapper na docker #
############################################
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"
DOCKER_BIN="${DOCKER_BIN:-$(command -v docker 2>/dev/null || true)}"
[[ -z "$DOCKER_BIN" && -x /usr/bin/docker ]] && DOCKER_BIN="/usr/bin/docker"
if [[ -z "$DOCKER_BIN" || ! -x "$DOCKER_BIN" ]]; then
  echo "ERROR: nie znalazłem binarki 'docker'. Zainstaluj docker albo ustaw DOCKER_BIN=/pełna/ścieżka." >&2
  exit 1
fi
docker() { "$DOCKER_BIN" "$@"; }

#################
# KONFIG DOMYŚLNY
#################
DISCOURSE_DIR="${DISCOURSE_DIR:-/var/discourse}"

# Co kasujemy
NUKE_POSTGRES="${NUKE_POSTGRES:-1}"
NUKE_UPLOADS="${NUKE_UPLOADS:-1}"
NUKE_REDIS="${NUKE_REDIS:-0}"

# Czy uruchomić import po rebuild
RUN_IMPORT="${RUN_IMPORT:-1}"

# Kontener z MariaDB SMF (nazwa w `docker ps`)
SMF_DB_CONTAINER="${SMF_DB_CONTAINER:-smf-maria}"

# (opcjonalnie) dane do tuningu MariaDB; nie są używane do importu!
DB_USER="${DB_USER:-root}"
DB_PASS="${DB_PASS:-}"       # jeśli puste → tuning pominięty

# Strefa czasu dla importera (żeby nie wymagał PHP CLI)
TZ="${TZ:-Europe/Warsaw}"

# Ścieżki do źródeł SMF:
#  - na hoście:
SMF_ROOT_HOST="${SMF_ROOT_HOST:-/var/discourse/shared/standalone/import/smf}"
#  - wewnątrz kontenera 'import' (musi się zgadzać z mountem w containers/import.yml):
SMF_ROOT_IN_IMPORT="${SMF_ROOT_IN_IMPORT:-/shared/import/smf}"

# (opcjonalnie) nadpisanie hosta DB (gdy w Settings.php jest 'localhost' niewłaściwy w dockerze)
OVERRIDE_DB_HOST="${OVERRIDE_DB_HOST:-}"

YES="${YES:-0}"

############
# HELPERY
############
die(){ echo -e "\033[1;31mERROR:\033[0m $*" >&2; exit 1; }
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

########################
# Tuning MariaDB (opc.)
########################
tune_mariadb(){
  info "Podkręcanie parametrów MariaDB (timeouts/packet)…"
  # Upewnij się, że kontener MariaDB działa
  if ! docker ps --format '{{.Names}}' | grep -qx "$SMF_DB_CONTAINER"; then
    info "Kontener $SMF_DB_CONTAINER nie działa – próbuję uruchomić…"
    docker start "$SMF_DB_CONTAINER" >/dev/null 2>&1 || {
      echo "WARN: Nie udało się uruchomić $SMF_DB_CONTAINER. Pomijam tuning." >&2
      return 0
    }
  fi
  # Bez hasła nie tuninguje (import i tak zadziała)
  if [[ -z "$DB_PASS" ]]; then
    echo "INFO: DB_PASS nieustawione → pomijam tuning MariiDB." >&2
    return 0
  fi

  docker exec -i "$SMF_DB_CONTAINER" mariadb -u"$DB_USER" -p"$DB_PASS" -e "
    SET GLOBAL max_allowed_packet=1073741824;  -- 1GB
    SET GLOBAL net_read_timeout=1800;
    SET GLOBAL net_write_timeout=1800;
    SET GLOBAL wait_timeout=86400;
    SET GLOBAL interactive_timeout=86400;
    SET GLOBAL innodb_lock_wait_timeout=300;
    SHOW VARIABLES WHERE Variable_name IN
    ('max_allowed_packet','net_read_timeout','net_write_timeout','wait_timeout','interactive_timeout','innodb_lock_wait_timeout');
  " || echo "WARN: Tuning MariiDB nie powiódł się (pomijam)."
}

########################
# Custom importer 
########################

use_custom_importer(){
  info "Sprawdzam własny smf2.rb…"
  # Ścieżki w KONTENERZE 'import' (mount /shared/…)
  CANDIDATES=(
    "$SMF_ROOT_IN_IMPORT/smf2.rb"  # domyślnie: /shared/import/smf/smf2.rb
    "/shared/smf/smf2.rb"          # alternatywa: /shared/smf/smf2.rb
  )
  docker exec import bash -lc 'set -e; mkdir -p /var/www/discourse/script/import_scripts'
  for p in "${CANDIDATES[@]}"; do
    if docker exec import bash -lc "[ -f \"$p\" ]"; then
      info "Znalazłem: $p — podmieniam importer."
      docker exec import bash -lc "
        set -e
        cd /var/www/discourse/script/import_scripts
        if [ -f smf2.rb ]; then cp smf2.rb smf2.rb.factory.\$(date +%F_%H%M%S); fi
        cp \"$p\" smf2.rb
        chmod 644 smf2.rb
        head -n 1 smf2.rb || true
      "
      return 0
    fi
  done
  info "Nie znaleziono własnego smf2.rb (pomijam podmianę)."
}

########################
# Custom site settings
########################

enforce_site_settings(){
  local CONTAINER="${1:?podaj nazwę kontenera (import|app)}"
  info "Wymuszam ustawienia witryny w kontenerze '$CONTAINER'…"
  docker exec -i "$CONTAINER" bash -lc 'set -e
cat > /tmp/enforce.rb <<'"'"'RUBY'"'"'
SiteSetting.title = "ForumIQ"
SiteSetting.enable_names = true
SiteSetting.display_name_on_posts = true
SiteSetting.prioritize_username_in_ux = false
SiteSetting.use_name_for_username_suggestions = true

base = (SiteSetting.authorized_extensions.presence || "jpg|jpeg|png|gif|heic|heif|webp|avif").split("|")
need = %w[pdf doc docx xls xlsx odt ods odp odg mp3 mp4 avi mkv]
SiteSetting.authorized_extensions = (base | need).join("|")

SiteSetting.max_attachment_size_kb = 524_288

puts "OK: title=#{SiteSetting.title}, authorized_extensions=#{SiteSetting.authorized_extensions}"
RUBY

su - discourse -c "cd /var/www/discourse && RAILS_ENV=production bundle exec rails r /tmp/enforce.rb"
rm -f /tmp/enforce.rb
'
}


########################
# Import SMF → Discourse
########################
run_import(){
  [[ "$RUN_IMPORT" == "1" ]] || { info "RUN_IMPORT=0 → pomijam uruchomienie importu."; return 0; }

  info "Start importu SMF…"

  if [[ ! -e "$SMF_ROOT_HOST" ]]; then
    die "Brak źródeł SMF pod $SMF_ROOT_HOST (na hoście). Upewnij się, że Settings.php i załączniki są na miejscu."
  fi

  local HOST_ARG=""
  [[ -n "$OVERRIDE_DB_HOST" ]] && HOST_ARG="-h $OVERRIDE_DB_HOST"

  # Uwaga: NIE podajemy -p/-u/-d/-f → importer czyta wszystko z Settings.php.
  # Podajemy tylko strefę czasu (żeby nie wymagał PHP CLI) i ewentualny override hosta DB.
  local IMPORT_CMD
  IMPORT_CMD="su - discourse -c 'cd /var/www/discourse && \
    RACK_MINI_PROFILER=off RAILS_ENV=production \
    bundle exec ruby script/import_scripts/smf2.rb \
      $SMF_ROOT_IN_IMPORT $HOST_ARG -t $TZ'"

  docker exec -i import bash -lc "$IMPORT_CMD"
}

########
# MAIN
########
main(){
  require_root "$@"
  command -v "$DOCKER_BIN" >/dev/null || die "Brak docker w PATH"
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
    rm -rf postgres_run   # usuń ewentualny stary socket PG (zapobiega kolizji przy 'import')
  popd >/dev/null

  # 1) Najpierw stawiamy 'import' (on startuje własnego Postgresa)
  info "Rebuild import…"
  launcher rebuild import
  enforce_site_settings import

  use_custom_importer
  tune_mariadb
  run_import

  # 2) Po imporcie: wygaszamy import i stawiamy docelowy app (z hookami z app.yml)
  info "Wyłączam import i stawiam app…"
  launcher stop import || true
  launcher rebuild app
  enforce_site_settings app

  info "DONE. Jeśli trzeba, możesz teraz zrebake’ować posty:"
  echo "  cd /var/discourse && ./launcher enter app"
  echo "  su - discourse && cd /var/www/discourse && RAILS_ENV=production bundle exec rake posts:rebake"
}

main "$@"
