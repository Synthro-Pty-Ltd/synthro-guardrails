#!/usr/bin/env bash
# Proof harness for the Migration Rounds.
#
# For every case under cases/, on a throwaway Postgres container with no
# network at all:
#
#   1. apply broken.sql to a fresh copy of the fixture, run the matrix as a real
#      signed-in user, and REQUIRE it to report the defect;
#   2. apply fixed.sql to another fresh copy, run the same matrix, and REQUIRE
#      it to report clean;
#   3. for cases marked `blind`, run the matrix as the table owner against both
#      and REQUIRE the two verdicts to be identical — showing that a test run as
#      the owner cannot tell a broken database from a fixed one.
#
# A matrix that only ever passes cannot see the hole it was written for. This
# script fails if a defect goes undetected, if a fix does not clean it, or if a
# matrix produces no verdict at all.
#
# Usage:  bash packs/migration-rounds/proof/run.sh
# Needs:  Docker. Pulls postgres:17 if it is not already present.
# Env:    PROOF_IMAGE   override the image (e.g. a supabase/postgres tag)

set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash on Windows: do not rewrite /paths

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${PROOF_IMAGE:-postgres:17}"
CONTAINER="guardrails-proof-$$"

cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# --network none: the database is unreachable from anywhere, including the host.
docker run -d --name "$CONTAINER" --network none \
  -e POSTGRES_PASSWORD=throwaway-proof-only "$IMAGE" >/dev/null

# The image starts a temporary server for initialisation and then restarts.
# Waiting for pg_isready alone can catch the temporary one, so wait for the log
# line that marks the end of initialisation first.
for _ in $(seq 1 90); do
  if docker logs "$CONTAINER" 2>&1 | grep -q "PostgreSQL init process complete"; then break; fi
  sleep 1
done
for _ in $(seq 1 30); do
  docker exec "$CONTAINER" pg_isready -U postgres -q && break
  sleep 1
done

sql() { # sql <db> [psql args...]  — reads SQL from stdin
  local db="$1"; shift
  docker exec -i "$CONTAINER" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d "$db" "$@"
}

PGVERSION=$(docker exec "$CONTAINER" psql -X -qtA -U postgres -c "SHOW server_version")
echo "Throwaway container: $IMAGE (PostgreSQL $PGVERSION), no network"
echo

sql postgres >/dev/null <<'SQL'
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE DATABASE fixture;
SQL
sql fixture < "$HERE/fixture.sql" >/dev/null

# Every database a case uses is a fresh copy of the fixture.
fresh_db() {
  sql postgres -c "DROP DATABASE IF EXISTS $1" -c "CREATE DATABASE $1 TEMPLATE fixture" >/dev/null 2>&1
}

# Run a case's matrix and print its verdict line, e.g. "RESULT DEFECT 1/3".
# Both stdout and stderr are read: RAISE NOTICE travels on stderr, and a
# detector that reads only stdout never sees a single assertion.
verdict() { # verdict <case_dir> <db> <role> <logfile>
  local dir="$1" db="$2" role="$3" log="$4"
  if [ -f "$dir/matrix.sh" ]; then
    DB="$db" CONTAINER="$CONTAINER" bash "$dir/matrix.sh" >"$log" 2>&1 || true
  else
    sql "$db" -v as_role="$role" < "$dir/matrix.sql" >"$log" 2>&1 || true
  fi
  grep -oE 'RESULT (CLEAN|DEFECT) [0-9]+/[0-9]+' "$log" | tail -n 1 || true
}

show() { # print the case lines of a matrix log, indented
  grep -oE '(ok|FAIL|info) +.*' "$1" | sed 's/^/      /' || true
}

LOGS="$(mktemp -d)"
pass=0; fail=0
results=()

for dir in "$HERE"/cases/*/; do
  dir="${dir%/}"
  name="$(basename "$dir")"
  id="c$(echo "$name" | cut -c1-2)"
  echo "== $name"

  fresh_db "${id}_broken"
  if ! sql "${id}_broken" < "$dir/broken.sql" >"$LOGS/$id.apply-broken" 2>&1; then
    echo "   HARNESS ERROR: broken.sql did not apply"; sed 's/^/      /' "$LOGS/$id.apply-broken"
    fail=$((fail + 1)); results+=("$name|harness error|"); continue
  fi
  fresh_db "${id}_fixed"
  if ! sql "${id}_fixed" < "$dir/fixed.sql" >"$LOGS/$id.apply-fixed" 2>&1; then
    echo "   FIXED VERSION DID NOT APPLY"; sed 's/^/      /' "$LOGS/$id.apply-fixed"
    fail=$((fail + 1)); results+=("$name|fixed did not apply|"); continue
  fi

  before="$(verdict "$dir" "${id}_broken" authenticated "$LOGS/$id.broken")"
  after="$(verdict "$dir" "${id}_fixed" authenticated "$LOGS/$id.fixed")"

  echo "   broken, as a signed-in user:  ${before:-NO VERDICT}"
  show "$LOGS/$id.broken"
  echo "   fixed,  as a signed-in user:  ${after:-NO VERDICT}"
  show "$LOGS/$id.fixed"

  ok=1
  case "$before" in "RESULT DEFECT"*) ;; *) ok=0; echo "   ✗ the matrix did not detect the defect";; esac
  case "$after"  in "RESULT CLEAN"*)  ;; *) ok=0; echo "   ✗ the fix did not come back clean";; esac

  blind=""
  if [ -f "$dir/blind" ]; then
    ob="$(verdict "$dir" "${id}_broken" postgres "$LOGS/$id.owner-broken")"
    of="$(verdict "$dir" "${id}_fixed"  postgres "$LOGS/$id.owner-fixed")"
    echo "   same matrix as the table OWNER: broken → ${ob:-NO VERDICT}   fixed → ${of:-NO VERDICT}"
    if [ -n "$ob" ] && [ "$ob" = "$of" ]; then
      echo "   → identical: a test run as the owner cannot tell these databases apart"
      blind="owner-blind"
    else
      ok=0; echo "   ✗ expected the owner run to be blind (identical verdicts)"
    fi
  fi

  if [ "$ok" = 1 ]; then pass=$((pass + 1)); echo "   ✓ proven both directions"
  else fail=$((fail + 1)); fi
  results+=("$name|${before#RESULT } → ${after#RESULT }|$blind")
  echo
done

total=$((pass + fail))
echo "──────────────────────────────────────────────────────────────"
printf "%-28s %-30s %s\n" "case" "broken → fixed (as user)" ""
for r in "${results[@]}"; do
  IFS='|' read -r n v b <<<"$r"
  printf "%-28s %-30s %s\n" "$n" "$v" "$b"
done
echo "──────────────────────────────────────────────────────────────"

if [ "$total" = 0 ]; then
  echo "NOTHING CHECKED — no cases found. This is a failure, not a pass."
  exit 1
fi
if [ "$fail" = 0 ]; then
  echo "PROOF PASSED: $pass/$total cases — every defect detected, every fix clean."
  exit 0
fi
echo "PROOF FAILED: $fail/$total cases did not prove both directions."
exit 1
