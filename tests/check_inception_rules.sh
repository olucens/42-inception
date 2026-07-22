#!/usr/bin/env bash
# Checks the mandatory forbidden-pattern rules from materials-inception/inception-subject.pdf.
# Exit 0 = no FAILs. Exit 1 = at least one FAIL. WARN never fails the build.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$ROOT_DIR/Inception"
COMPOSE="$PROJECT_DIR/srcs/docker-compose.yml"
MANDATORY_SERVICES="mariadb wordpress nginx"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BOLD='\033[1m'; NC='\033[0m'
PASS_COUNT=0; FAIL_COUNT=0; WARN_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT+1)); printf "${GREEN}PASS${NC}  %s\n" "$1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT+1)); printf "${RED}FAIL${NC}  %s\n" "$1"; }
warn() { WARN_COUNT=$((WARN_COUNT+1)); printf "${YELLOW}WARN${NC}  %s\n" "$1"; }
section() { printf "\n${BOLD}== %s ==${NC}\n" "$1"; }

# ---------------------------------------------------------------------------
section "Project structure"

if [ -f "$PROJECT_DIR/Makefile" ]; then
  pass "Makefile exists at Inception/Makefile"
else
  fail "Makefile missing at Inception/Makefile"
fi

if [ -f "$COMPOSE" ]; then
  pass "docker-compose.yml exists"
else
  fail "docker-compose.yml missing — compose checks below will be skipped"
fi

for svc in $MANDATORY_SERVICES; do
  df="$PROJECT_DIR/srcs/requirements/$svc/Dockerfile"
  if [ -f "$df" ]; then
    pass "Dockerfile exists for $svc"
  else
    fail "Dockerfile missing for $svc"
  fi
done

# ---------------------------------------------------------------------------
section "Dockerfile content"

for svc in $MANDATORY_SERVICES; do
  df="$PROJECT_DIR/srcs/requirements/$svc/Dockerfile"
  [ -f "$df" ] || continue

  if [ ! -s "$df" ]; then
    warn "$svc/Dockerfile is empty — content checks skipped (not written yet)"
    continue
  fi

  from_line=$(grep -im1 '^FROM' "$df" | sed -E 's/^FROM[[:space:]]+//I')
  case "$from_line" in
    [aA][lL][pP][iI][nN][eE]:*|[dD][eE][bB][iI][aA][nN]:*)
      tag="${from_line#*:}"
      if [ -z "$tag" ] || [ "$tag" = "latest" ]; then
        fail "$svc: FROM uses the 'latest' tag ($from_line)"
      else
        pass "$svc: FROM pinned to $from_line"
      fi
      ;;
    *)
      fail "$svc: FROM is not alpine/debian ($from_line) — forbidden base image"
      ;;
  esac

  if grep -qiE 'tail[[:space:]]+-f|sleep[[:space:]]+infinity|while[[:space:]]+(true|:)([[:space:]]|$)|(CMD|ENTRYPOINT)[[:space:]]*\[?"?(/bin/)?(bash|sh)"?\]?[[:space:]]*$' "$df"; then
    fail "$svc: forbidden hacky entrypoint pattern in Dockerfile (tail -f / sleep infinity / while true / bare bash-sh)"
  else
    pass "$svc: no forbidden entrypoint pattern in Dockerfile"
  fi

  if grep -inE '(PASSWORD|PASSWD)[[:space:]]*=[[:space:]]*[^$[:space:]]' "$df" >/dev/null; then
    fail "$svc: possible hardcoded password literal in Dockerfile — verify manually"
  else
    pass "$svc: no hardcoded password pattern in Dockerfile"
  fi

  scripts_dir="$PROJECT_DIR/srcs/requirements/$svc/tools"
  if [ -d "$scripts_dir" ]; then
    while IFS= read -r -d '' sh; do
      [ -s "$sh" ] || continue
      if grep -qiE 'tail[[:space:]]+-f|sleep[[:space:]]+infinity|while[[:space:]]+(true|:)([[:space:]]|$)' "$sh"; then
        fail "$svc: forbidden hacky pattern in $(basename "$sh")"
      else
        pass "$svc: no forbidden pattern in $(basename "$sh")"
      fi
    done < <(find "$scripts_dir" -maxdepth 1 -name '*.sh' -print0)
  fi
done

# ---------------------------------------------------------------------------
section "docker-compose.yml"

if [ -f "$COMPOSE" ]; then

  if grep -qE '^[[:space:]]*(network_mode:[[:space:]]*host|network:[[:space:]]*host)' "$COMPOSE"; then
    fail "network: host found in compose — forbidden"
  else
    pass "no network: host"
  fi

  if grep -qE '(^[[:space:]]*links:|--link)' "$COMPOSE"; then
    fail "links: / --link found in compose — forbidden"
  else
    pass "no links: / --link"
  fi

  if grep -qE '^networks:' "$COMPOSE"; then
    pass "top-level networks: key present"
  else
    fail "top-level networks: key missing (subject requires it)"
  fi

  if grep -qE '^secrets:' "$COMPOSE"; then
    pass "top-level secrets: key present"
  else
    warn "no top-level secrets: key (strongly recommended, not mandatory)"
  fi

  services=$(awk '
    /^services:/ {insvc=1; next}
    insvc && /^[A-Za-z_]/ && !/^  / {insvc=0}
    insvc && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ {
      line=$0; sub(/^  /,"",line); sub(/:.*/,"",line); print line
    }
  ' "$COMPOSE")

  for name in $MANDATORY_SERVICES; do
    if printf '%s\n' "$services" | grep -qx "$name"; then
      pass "service '$name' defined in compose"
    else
      fail "service '$name' not defined in compose (yet)"
    fi
  done

  service_block() {
    awk -v name="$1" '
      $0 ~ "^  "name":[[:space:]]*$" {insvc=1; next}
      insvc && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ {insvc=0}
      insvc && /^[A-Za-z_]/ && !/^  / {insvc=0}
      insvc
    ' "$COMPOSE"
  }

  for name in $services; do
    block=$(service_block "$name")

    image_line=$(printf '%s\n' "$block" | grep -m1 -E '^[[:space:]]*image:' | sed -E 's/^[[:space:]]*image:[[:space:]]*//')
    if [ -z "$image_line" ]; then
      warn "$name: no image: key set"
    elif [ "$image_line" = "$name" ]; then
      fail "$name: image: '$image_line' has no explicit tag -> defaults to :latest"
    elif [[ "$image_line" == *:latest ]]; then
      fail "$name: image: '$image_line' explicitly uses latest"
    elif [ "${image_line%%:*}" = "$name" ]; then
      pass "$name: image name matches service, tag pinned ($image_line)"
    else
      fail "$name: image: '$image_line' does not match service name '$name'"
    fi

    if printf '%s\n' "$block" | grep -qE '^[[:space:]]*restart:'; then
      pass "$name: restart policy set"
    else
      fail "$name: no restart: policy (containers must restart on crash)"
    fi

    if printf '%s\n' "$block" | grep -qE '^[[:space:]]*-[[:space:]]+(\.{0,2}/|~/)'; then
      fail "$name: bind-mount volume syntax found (named volumes only)"
    else
      pass "$name: no bind-mount volume syntax"
    fi
  done
fi

# ---------------------------------------------------------------------------
section "Secrets hygiene (git)"

cd "$ROOT_DIR" || exit 1
tracked_env=$(git ls-files | grep -E '(^|/)srcs/\.env$' || true)
tracked_secrets=$(git ls-files | grep -E '(^|/)secrets/[^/]+\.txt$' || true)

if [ -z "$tracked_env" ]; then
  pass "no .env file tracked by git"
else
  fail ".env file is tracked by git: $tracked_env"
fi

if [ -z "$tracked_secrets" ]; then
  pass "no secrets/*.txt tracked by git"
else
  fail "secret files tracked by git: $tracked_secrets"
fi

# ---------------------------------------------------------------------------
section "Summary"
printf "passed: %s  failed: %s  warnings: %s\n" "$PASS_COUNT" "$FAIL_COUNT" "$WARN_COUNT"

[ "$FAIL_COUNT" -eq 0 ]
