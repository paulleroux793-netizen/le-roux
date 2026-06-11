#!/usr/bin/env bash
# Refresh Ivory's READ-ONLY mirror of the live Elixir diary, end to end.
#
# Prereq: a fresh MDLDATA.FDB has been copied into the OneDrive Elixir folder
# (copy it on the Reception PC with Elixir CLOSED so the file is unlocked).
#
# Run from Paul's PC (Git Bash):  bash le-roux-repo/script/refresh_elixir_mirror.sh
#
# Pipeline: pick freshest MDLDATA.FDB -> copy to scratch -> isql extract ->
# python parse -> ship JSON to the rig -> import into ElixirDiarySnapshot.
set -euo pipefail

EL="/d/Paul le Roux/OneDrive/1. Dr Chalita le Roux/Elixir"
SCRATCH="/c/Users/paul-/AppData/Local/Temp/elixir_live"
ISQL="/c/Program Files (x86)/Firebird/Firebird_2_5/bin/isql.exe"
WIN_FDB='C:\Users\paul-\AppData\Local\Temp\elixir_live\live.fdb'
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RIG_REPO="/opt/ivory/le-roux-repo"
mkdir -p "$SCRATCH"

FRESH=$(ls -t "$EL/MDLDATA.FDB" "$EL/SQL/MDLDATA.FDB" 2>/dev/null | head -1)
[ -n "$FRESH" ] || { echo "No MDLDATA.FDB found in OneDrive Elixir folder."; exit 1; }
echo "1/5 source: $FRESH ($(stat -c%y "$FRESH" | cut -d. -f1))"
cp "$FRESH" "$SCRATCH/live.fdb"

echo "2/5 extracting diary via isql..."
rm -f "$SCRATCH/diary_raw.txt" "$SCRATCH/diary_live.json"   # isql -o appends, so start clean
"$ISQL" "$WIN_FDB" -user SYSDBA -password masterkey -i "$DIR/extract_elixir_diary.sql" -o "$SCRATCH/diary_raw.txt"

echo "3/5 parsing..."
python "$DIR/parse_elixir_diary.py" "$SCRATCH/diary_raw.txt" "$SCRATCH/diary_live.json"

echo "4/5 shipping to the rig..."
cat "$SCRATCH/diary_live.json" | ssh rig "cat > $RIG_REPO/tmp/diary_live.json"

echo "5/5 importing into Ivory..."
ssh rig "cd $RIG_REPO && docker compose -f docker-compose.rig.yml cp tmp/diary_live.json web:/rails/tmp/diary_live.json >/dev/null && docker compose -f docker-compose.rig.yml exec -T web bin/rails runner script/import_elixir_live.rb 2>&1 | grep -i elixir_live"

echo "Done — Ivory diary now mirrors the latest Elixir copy."
