#!/bin/bash
# setup_miga_config.sh
# Generates MiGA config files (.miga_rc and .miga_modules) in the Vault.
# Called by: pixi run miga-setup-vault-config
# Bypasses miga init - no hardcoded paths, fully portable.
#
# What this script does:
#   1. Writes .miga_rc to MIGA_HOME (EXTERNAL_VAULT/miga_db/)
#   2. Writes .miga_modules to MIGA_HOME
#   3. Copies .miga_daemon.json to MIGA_HOME (required for MiGA initialized? check)
#   4. Creates ~/.miga_rc symlink pointing to MIGA_HOME/.miga_rc
#   5. Auto-detects RDP classifier path from pixi envs
set -e

# ── Resolve paths ──────────────────────────────────────────────────────────
MIGA_DB_DIR="$EXTERNAL_VAULT/miga_db"
MIGA_LINK_DIR="$PIXI_PROJECT_ROOT/db_link"
mkdir -p "$MIGA_DB_DIR"

# ── Find RDP classifier.jar dynamically inside pixi envs ───────────────────
RDP_JAR=$(find "$PIXI_PROJECT_ROOT/.pixi/envs" -name "classifier.jar" 2>/dev/null \
          | grep "rdp_classifier" | head -1)

if [ -z "$RDP_JAR" ]; then
  echo "WARNING: RDP classifier.jar not found in pixi envs."
  echo "         Run 'pixi install -e env-a' first, then re-run this task."
  RDP_DATA=""
else
  RDP_DATA="$(dirname "$RDP_JAR")/rdp_classifier"
  echo "RDP path resolved to: $RDP_DATA"
fi

# ── Write .miga_rc ─────────────────────────────────────────────────────────
cat > "$MIGA_DB_DIR/.miga_rc" << MIGAEOF
export MIGA_HOME="$PIXI_PROJECT_ROOT/db_link/miga_db"
export MYTAXA_DB="$PIXI_PROJECT_ROOT/db_link/mytaxa"
export MIGA_MYTAXA="no"
export RDP_CLASSIFIER_DATA="$RDP_DATA"
miga_type="workstation"
miga_shell="bash"
MIGAEOF

# ── Write .miga_modules ────────────────────────────────────────────────────
cat > "$MIGA_DB_DIR/.miga_modules" << MIGAEOF
export PATH="$PIXI_PROJECT_ROOT/.pixi/envs/default/bin:$PIXI_PROJECT_ROOT/.pixi/envs/default/share/rubygems/bin:\$PATH"
MIGAEOF

# ── Copy .miga_daemon.json to MIGA_HOME ────────────────────────────────────
# Required by MiGA::MiGA.initialized? check in common.rb
# Without this file in MIGA_HOME, all wf commands fail with "not been initialized"
DAEMON_SRC="$MIGA_LINK_DIR/.miga_daemon.json"
DAEMON_DST="$MIGA_DB_DIR/.miga_daemon.json"

if [ -f "$DAEMON_SRC" ]; then
  cp "$DAEMON_SRC" "$DAEMON_DST"
  echo "Daemon config copied to: $DAEMON_DST"
elif [ -f "$DAEMON_DST" ]; then
  echo "Daemon config already exists at: $DAEMON_DST"
else
  echo "WARNING: .miga_daemon.json not found at $DAEMON_SRC"
  echo "         Creating minimal default daemon config..."
  cat > "$DAEMON_DST" << DAEMONEOF
{
  "type": "bash",
  "cmd": "%1\$s",
  "var": "%1\$s",
  "varsep": " ",
  "alive": "ps -p %1\$d -o pid=",
  "kill": "kill %1\$d"
}
DAEMONEOF
  echo "Default daemon config written to: $DAEMON_DST"
fi

# ── Create ~/.miga_rc symlink ───────────────────────────────────────────────
# MiGA checks rc_path (typically ~/.miga_rc) as part of initialized? check
if [ -L "$HOME/.miga_rc" ]; then
  echo "~/.miga_rc symlink already exists: $(readlink $HOME/.miga_rc)"
elif [ -f "$HOME/.miga_rc" ]; then
  echo "WARNING: ~/.miga_rc exists as a regular file, not symlinking"
  echo "         Manually replace if needed:"
  echo "         ln -sf $MIGA_DB_DIR/.miga_rc ~/.miga_rc"
else
  ln -sf "$MIGA_DB_DIR/.miga_rc" "$HOME/.miga_rc"
  echo "~/.miga_rc symlink created -> $MIGA_DB_DIR/.miga_rc"
fi

# ── Summary ────────────────────────────────────────────────────────────────
echo ""
echo "SUCCESS: MiGA config written to $MIGA_DB_DIR"
echo "─────────────────────────────────────────────"
echo ".miga_rc contents:"
cat "$MIGA_DB_DIR/.miga_rc"
