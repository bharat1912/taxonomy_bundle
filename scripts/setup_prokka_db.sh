#!/bin/bash
set -e # Exit on error

# Ensure the Vault link is active
pixi run setup-vault

# Check if the database folder has files in it
if [ "$(ls -A $EXTERNAL_VAULT/prokka_db 2>/dev/null)" ]; then
     echo "✅ Prokka DB already populated. Running re-index..."
else
     echo "📂 Vault empty. Pulling Prokka core assets..."
     git clone --depth 1 https://github.com/tseemann/prokka.git temp_prokka
     cp -rv temp_prokka/db/* "$EXTERNAL_VAULT/prokka_db/"
     rm -rf temp_prokka
fi

# Run the actual indexing
echo "🧬 Starting Prokka Database Setup..."
pixi run -e env-pan prokka --setupdb
