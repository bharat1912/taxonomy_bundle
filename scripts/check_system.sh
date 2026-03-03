#!/bin/bash
# ---------------------------------------------------------------------------
# Purpose: Validates kernel user namespaces for Apptainer/DRAM2
# ---------------------------------------------------------------------------

USER_NS=$(cat /proc/sys/user/max_user_namespaces 2>/dev/null || echo 0)

if [ "$USER_NS" -lt 1000 ]; then
    echo "❌ SYSTEM CONFLICT: Kernel user namespaces are restricted (Current: $USER_NS)."
    echo "Please run: sudo ./scripts/fix_system.sh"
    exit 1
else
    echo "✅ System readiness: PASSED (Namespaces: $USER_NS)"
    exit 0
fi
