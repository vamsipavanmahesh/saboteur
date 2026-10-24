#!/usr/bin/env bash
# Dispatcher: mode doctor | map | replay. Inputs arrive through the environment from the workflow.
set -uo pipefail
: "${MODE:?}" "${RECIPE_DIR:?}" "${TOOL_DIR:?}" "${OUT:?}" "${JOB_MONO0:?}"
export RECIPE_DIR TOOL_DIR OUT JOB_MONO0
case "$MODE" in
  doctor) exec bash "$RECIPE_DIR/doctor.sh" ;;
  map) : "${ERA:?}"; [[ "$ERA" =~ ^S[1-4]$ ]] || { echo "bad era"; exit 1; }; exec bash "$RECIPE_DIR/map.sh" "$ERA" ;;
  replay) : "${PR:?}" "${MAP_ART_DIR:?}"; [[ "$PR" =~ ^[0-9]+$ ]] || { echo "bad pr"; exit 1; }; exec bash "$RECIPE_DIR/replay.sh" "$PR" ;;
  *) echo "unknown mode"; exit 1 ;;
esac
