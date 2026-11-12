#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

usage() {
    echo "usage: $0 STEP... (descending, like 15m 10m 5m 1m or 1m 30s)" >&2
    exit 2
}

[ $# -gt 0 ] || usage
seconds=()
texts=()
for step in "$@"; do
    [[ "$step" =~ ^([1-9][0-9]*)([ms])$ ]] || usage
    count=${BASH_REMATCH[1]}
    if [ "${BASH_REMATCH[2]}" = m ]; then
        total=$(( count * 60 ))
        unit=minute
    else
        total=$count
        unit=second
    fi
    [ "$count" = 1 ] || unit+=s
    [ ${#seconds[@]} = 0 ] || [ "$total" -lt "${seconds[-1]}" ] || usage
    seconds+=("$total")
    texts+=("Server restarting in $count $unit.")
done

announce=false
grep -qx game00 <<<"$(docker compose config --services 2>/dev/null)" && announce=true

for i in "${!seconds[@]}"; do
    text=${texts[i]}
    if $announce; then
        docker compose exec -T game00 sh -c 'printf %s "$1" > /tmp/restart-notice.new && mv /tmp/restart-notice.new /tmp/restart-notice' _ "$text" </dev/null \
            || echo "could not write restart notice: $text" >&2
    fi
    sleep $(( seconds[i] - ${seconds[i+1]:-0} ))
done
