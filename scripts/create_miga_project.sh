#!/bin/bash
# MiGA Project Creation Script - FULLY FIXED VERSION

PROJECT_NAME="${PROJECT_NAME:-my_miga_project}"
PROJECT_TYPE="${PROJECT_TYPE:-genomes}"

if [ -d "$PROJECT_NAME" ]; then
  echo "ERROR: Project already exists: $PROJECT_NAME"
  exit 1
fi

echo "Creating MiGA project: $PROJECT_NAME (type: $PROJECT_TYPE)"

mkdir -p "$PROJECT_NAME/data" "$PROJECT_NAME/metadata" "$PROJECT_NAME/daemon"
mkdir -p "$PROJECT_NAME/data/05.assembly"

cat > "$PROJECT_NAME/miga.project.json" << JSONEOF
{
  "name": "$PROJECT_NAME",
  "type": "$PROJECT_TYPE",
  "created": "$(date +%Y-%m-%d)",
  "updated": "$(date +%Y-%m-%d)",
  "datasets": [],
  "datasets_count": 0
}
JSONEOF

cat > "$PROJECT_NAME/daemon/daemon.json" << DAEMONJSON
{
  "created": "$(date +%Y-%m-%d)",
  "updated": "$(date +%Y-%m-%d)",
  "active": false,
  "latency": 30,
  "maxjobs": 4,
  "ppn": 1,
  "shutdown_when_done": false
}
DAEMONJSON

ln -sfn "$EXTERNAL_VAULT/miga_db/.miga_rc" "$PROJECT_NAME/.miga_rc"
ln -sfn "$EXTERNAL_VAULT/miga_db/.miga_modules" "$PROJECT_NAME/.miga_modules"

echo "✓ SUCCESS: Project created at: $PROJECT_NAME"
echo ""
echo "Next steps:"
echo "  pixi run miga-cli add -P $PROJECT_NAME -t genome -i assembly genome.fasta"
echo "  pixi run miga-cli daemon start -P $PROJECT_NAME --shutdown-when-done"
