#!/usr/bin/env bash
# Run Playwright E2E tests grouped by game.
# Each game group starts its own Lisp server + Gateway, runs tests, then tears down.
set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

TOTAL_PASS=0
TOTAL_FAIL=0
RESULTS=""

cleanup() {
    [ -n "$GW_PID" ] && kill "$GW_PID" 2>/dev/null; wait "$GW_PID" 2>/dev/null
    [ -n "$LISP_PID" ] && kill "$LISP_PID" 2>/dev/null; wait "$LISP_PID" 2>/dev/null
    GW_PID=""
    LISP_PID=""
    # Force-kill anything on our ports and wait for release
    lsof -ti :4444 -ti :8080 2>/dev/null | xargs -r kill -9 2>/dev/null
    for i in $(seq 1 10); do
        if ! lsof -ti :4444 -ti :8080 >/dev/null 2>&1; then break; fi
        sleep 1
    done
}
trap cleanup EXIT

start_servers() {
    local game=$1
    local lisp_cmd=$2

    echo ""
    echo "=============================="
    echo "Starting servers for: $game"
    echo "=============================="

    # Start Lisp server
    sbcl --load foldback.asd \
         --eval "(ql:quickload :foldback)" \
         --eval "$lisp_cmd" &
    LISP_PID=$!
    sleep 4

    # Start Gateway
    cd gateway && go run main.go &
    GW_PID=$!
    cd "$PROJECT_DIR"
    sleep 2

    # Verify both are running
    if ! kill -0 "$LISP_PID" 2>/dev/null; then
        echo "ERROR: Lisp server failed to start for $game"
        return 1
    fi
    if ! kill -0 "$GW_PID" 2>/dev/null; then
        echo "ERROR: Gateway failed to start for $game"
        return 1
    fi
    echo "Servers ready for $game"
}

run_game_tests() {
    local game=$1
    shift
    local specs=("$@")

    echo ""
    echo "--- $game E2E Tests ---"
    npx playwright test "${specs[@]}" --reporter=list --workers=1 --grep-invert "WebRTC" 2>&1
    local rc=$?

    if [ $rc -eq 0 ]; then
        RESULTS="$RESULTS\n  ✓ $game"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        RESULTS="$RESULTS\n  ✗ $game (exit $rc)"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
    return $rc
}

# ── Bomberman ──
start_servers "bomberman" \
    "(let* ((level (foldback:make-bomberman-map)) (bots (foldback:spawn-bots level 3))) (foldback:start-server :game-id \"bomberman\" :simulation-fn #'foldback:bomberman-update :serialization-fn #'foldback:bomberman-serialize :join-fn #'foldback:bomberman-join :initial-custom-state (fset:map (:level level) (:bots bots) (:seed 123))))"

run_game_tests "Bomberman" \
    tests/bomberman-multiplayer.spec.ts \
    tests/bomberman-prediction.spec.ts \
    tests/bomberman-rollback.spec.ts || true

cleanup

# ── Air Hockey ──
start_servers "airhockey" \
    "(foldback:start-server :game-id \"airhockey\" :simulation-fn #'foldback:airhockey-update :serialization-fn #'foldback:airhockey-serialize :join-fn #'foldback:airhockey-join)"

run_game_tests "Air Hockey" \
    tests/airhockey-prediction.spec.ts \
    tests/airhockey-multiplayer.spec.ts || true

cleanup

# ── Pong ──
start_servers "pong" \
    "(foldback:start-server :game-id \"pong\" :simulation-fn #'foldback:pong-update :serialization-fn #'foldback:pong-serialize :join-fn #'foldback:pong-join)"

run_game_tests "Pong" \
    tests/pong-multiplayer.spec.ts || true

cleanup

# ── Jump and Bump ──
start_servers "jumpnbump" \
    "(foldback:start-server :game-id \"jumpnbump\" :simulation-fn #'foldback:jnb-update :serialization-fn #'foldback:jnb-serialize :join-fn #'foldback:jnb-join :initial-custom-state (fset:map (:seed 123)))"

run_game_tests "Jump and Bump" \
    tests/jumpnbump-multiplayer.spec.ts \
    tests/jumpnbump-singleplayer.spec.ts || true

cleanup

# ── Summary ──
echo ""
echo "=============================="
echo "E2E Test Summary"
echo "=============================="
echo -e "$RESULTS"
echo ""
if [ $TOTAL_FAIL -gt 0 ]; then
    echo "RESULT: $TOTAL_PASS passed, $TOTAL_FAIL failed"
    exit 1
else
    echo "RESULT: All $TOTAL_PASS game groups passed"
fi
