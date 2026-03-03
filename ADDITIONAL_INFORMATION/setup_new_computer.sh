#!/bin/bash
# ============================================================================
# POST-CLONE SETUP SCRIPT FOR NEW COMPUTER
# Run this after cloning taxonomy_bundle to a new system
# ============================================================================

set -e
set -u

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_step() {
    echo -e "${YELLOW}➜${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# ============================================================================
# WELCOME MESSAGE
# ============================================================================

print_header "TAXONOMY BUNDLE - NEW COMPUTER SETUP"

echo ""
echo "This script will set up taxonomy_bundle on your new computer."
echo "It will guide you through:"
echo "  1. Verifying prerequisites"
echo "  2. Installing Pixi environments"
echo "  3. Setting up the external vault"
echo "  4. Testing the installation"
echo ""
read -p "Press Enter to continue..."

# ============================================================================
# STEP 1: VERIFY PREREQUISITES
# ============================================================================

print_header "STEP 1: VERIFYING PREREQUISITES"

# Check if pixi is installed
print_step "Checking for Pixi..."
if command -v pixi &> /dev/null; then
    PIXI_VERSION=$(pixi --version)
    print_success "Pixi found: $PIXI_VERSION"
else
    print_error "Pixi not found"
    echo ""
    echo "Installing Pixi..."
    curl -fsSL https://pixi.sh/install.sh | bash
    echo ""
    print_warning "Please restart your terminal and run this script again"
    exit 1
fi

# Check system resources
print_step "Checking system resources..."

# Check RAM
TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
if [ "$TOTAL_RAM" -ge 32 ]; then
    print_success "RAM: ${TOTAL_RAM}GB (sufficient)"
elif [ "$TOTAL_RAM" -ge 16 ]; then
    print_warning "RAM: ${TOTAL_RAM}GB (minimum met, but 32GB+ recommended)"
else
    print_error "RAM: ${TOTAL_RAM}GB (insufficient - 16GB minimum required)"
fi

# Check available disk space in home directory
HOME_SPACE=$(df -h ~ | awk 'NR==2 {print $4}')
print_info "Available space in home: $HOME_SPACE"

# Check for tmux
print_step "Checking for tmux (needed for large downloads)..."
if command -v tmux &> /dev/null; then
    print_success "tmux is installed"
else
    print_warning "tmux not found - install with: sudo apt-get install tmux"
fi

# ============================================================================
# STEP 2: VERIFY PROJECT STRUCTURE
# ============================================================================

print_header "STEP 2: VERIFYING PROJECT STRUCTURE"

print_step "Checking for required files..."

REQUIRED_FILES=(
    "pixi.toml"
    "Snakefile_autocycler.smk"
    "Snakefile_hybracter.smk"
    "Snakefile_hybrid_taxonomy.smk"
    "Snakefile_SRAsearch.smk"
    "config/config_auto.yaml"
    "config/config_hybracter.yaml"
    "config/config_taxonomy_merged.yaml"
    ".env.template"
)

MISSING_FILES=0
for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        print_success "Found: $file"
    else
        print_error "Missing: $file"
        MISSING_FILES=$((MISSING_FILES + 1))
    fi
done

if [ $MISSING_FILES -gt 0 ]; then
    print_error "$MISSING_FILES required file(s) missing"
    echo "Did you clone the complete repository?"
    exit 1
fi

# ============================================================================
# STEP 3: CONFIGURE EXTERNAL VAULT
# ============================================================================

print_header "STEP 3: CONFIGURING EXTERNAL VAULT"

echo ""
echo "The external vault stores large databases (500+ GB total)."
echo "Choose a location with plenty of space (external drive recommended)."
echo ""

if [ -n "${EXTERNAL_VAULT:-}" ]; then
    print_info "EXTERNAL_VAULT is already set to: $EXTERNAL_VAULT"
    read -p "Use this location? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        USE_EXISTING_VAULT=true
    else
        USE_EXISTING_VAULT=false
    fi
else
    USE_EXISTING_VAULT=false
fi

if [ "$USE_EXISTING_VAULT" = false ]; then
    echo ""
    echo "Common vault locations:"
    echo "  1. External drive:    /media/$USER/external_drive/taxonomy_databases"
    echo "  2. Secondary drive:   /mnt/data/taxonomy_databases"
    echo "  3. Network storage:   /nfs/shared/databases/taxonomy"
    echo ""
    read -p "Enter vault location: " vault_location
    
    # Expand ~ if present
    vault_location="${vault_location/#\~/$HOME}"
    
    export EXTERNAL_VAULT="$vault_location"
    
    # Add to .bashrc
    print_step "Adding EXTERNAL_VAULT to ~/.bashrc..."
    if ! grep -q "EXTERNAL_VAULT" ~/.bashrc; then
        echo "" >> ~/.bashrc
        echo "# Taxonomy Bundle External Vault" >> ~/.bashrc
        echo "export EXTERNAL_VAULT=\"$vault_location\"" >> ~/.bashrc
        print_success "Added to ~/.bashrc"
    else
        print_warning "EXTERNAL_VAULT already in ~/.bashrc (not modified)"
    fi
fi

# Verify vault location is writable
print_step "Verifying vault location is writable..."
if [ ! -d "$EXTERNAL_VAULT" ]; then
    print_info "Creating vault directory: $EXTERNAL_VAULT"
    mkdir -p "$EXTERNAL_VAULT" 2>/dev/null || {
        print_error "Cannot create directory. Check permissions."
        echo "You may need to run: sudo mkdir -p $EXTERNAL_VAULT && sudo chown $USER:$USER $EXTERNAL_VAULT"
        exit 1
    }
fi

if [ -w "$EXTERNAL_VAULT" ]; then
    print_success "Vault location is writable"
else
    print_error "Vault location is not writable"
    echo "Run: sudo chown $USER:$USER $EXTERNAL_VAULT"
    exit 1
fi

# ============================================================================
# STEP 4: INSTALL PIXI ENVIRONMENTS
# ============================================================================

print_header "STEP 4: INSTALLING PIXI ENVIRONMENTS"

print_warning "This step will download and install all software environments."
print_warning "It may take 10-30 minutes depending on your internet connection."
echo ""
read -p "Continue with installation? (Y/n): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    print_step "Installing environments..."
    
    # Run pixi install with output
    if pixi install; then
        print_success "All environments installed successfully"
    else
        print_error "Environment installation failed"
        echo "Try running: pixi install --verbose"
        exit 1
    fi
    
    # Verify key environments
    print_step "Verifying environments..."
    
    ENVS_TO_CHECK=("env-a" "env-b" "env-busco" "env-checkm2")
    for env in "${ENVS_TO_CHECK[@]}"; do
        if pixi list -e "$env" &> /dev/null; then
            print_success "Environment $env installed"
        else
            print_warning "Environment $env may have issues"
        fi
    done
else
    print_warning "Skipping environment installation"
fi

# ============================================================================
# STEP 5: SETUP VAULT STRUCTURE
# ============================================================================

print_header "STEP 5: SETTING UP VAULT STRUCTURE"

print_step "Creating vault directories and symlinks..."

if pixi run setup-vault; then
    print_success "Vault structure created"
else
    print_error "Vault setup failed"
    exit 1
fi

# Verify symlinks
print_step "Verifying symlinks..."
if [ -d "db_link" ] && [ -L "db_link/bakta" ]; then
    print_success "Symlinks created in db_link/"
else
    print_warning "Symlinks may not be properly created"
fi

# Show vault status
print_step "Current vault status:"
pixi run vault-audit

# ============================================================================
# STEP 6: SETUP CONFIGURATION FILES
# ============================================================================

print_header "STEP 6: SETTING UP CONFIGURATION FILES"

print_step "Creating configuration files from templates..."

# Copy template configs if they don't exist
if [ -f "config/config_auto.yaml" ]; then
    for config_name in "config_taxonomy" "config_auto" "config_hybracter"; do
        target="config/${config_name}.yaml"
        if [ ! -f "$target" ]; then
            cp "config/config_auto.yaml" "$target"
            print_success "Created: $target"
            print_info "  → Edit this file to configure your workflows"
        else
            print_info "$target already exists (not overwritten)"
        fi
    done
fi

print_info "Configuration files are in: config/"

# ============================================================================
# STEP 7: DATABASE INSTALLATION GUIDANCE
# ============================================================================

print_header "STEP 7: DATABASE INSTALLATION"

echo ""
echo "Databases are optional but required for specific workflows."
echo "They are large and should be downloaded in tmux sessions."
echo ""
echo "Available databases:"
echo "  1. Plassembler  (363 MB)   - Plasmid detection"
echo "  2. Bakta        (~62 GB)   - Genome annotation"
echo "  3. GTDB-Tk      (~141 GB)  - Taxonomic classification"
echo "  4. CheckM2      (~3.5 GB)  - Quality assessment"
echo "  5. Prokka       (~2 GB)    - Alternative annotation"
echo ""
echo "Recommendation: Start with Plassembler to test the system."
echo ""

read -p "Install Plassembler database now? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_step "Downloading Plassembler database..."
    if pixi run download-plassembler; then
        print_success "Plassembler database installed"
    else
        print_error "Plassembler download failed"
    fi
else
    print_info "Skipping Plassembler installation"
fi

echo ""
print_info "To install other databases later:"
echo "  Bakta:    tmux new -s bakta && pixi run download-bakta"
echo "  GTDB-Tk:  tmux new -s gtdbtk && pixi run download-gtdbtk"
echo "  CheckM2:  pixi run -e env-checkm2 download-checkm2"
echo "  Prokka:   pixi run setup-prokka-db"

# ============================================================================
# STEP 8: RUN INSTALLATION TESTS
# ============================================================================

print_header "STEP 8: RUNNING INSTALLATION TESTS"

echo ""
read -p "Run installation tests? (Y/n): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    print_step "Running comprehensive tests..."
    
    chmod +x test_taxonomy_bundle_setup.sh
    
    if ./test_taxonomy_bundle_setup.sh --skip-databases; then
        print_success "All tests passed!"
    else
        print_warning "Some tests failed - review output above"
    fi
else
    print_info "Skipping tests (you can run manually: ./test_taxonomy_bundle_setup.sh)"
fi

# ============================================================================
# FINAL SUMMARY
# ============================================================================

print_header "SETUP COMPLETE"

echo ""
echo -e "${GREEN}✓ Taxonomy Bundle is ready to use!${NC}"
echo ""
echo "Quick reference:"
echo "  • View environments:     pixi info"
echo "  • Check vault status:    pixi run vault-audit"
echo "  • Run workflows:         pixi run run-autocycler  OR  pixi run run-hybrid-taxonomy"
echo "  • Download databases:    pixi run download-<database>"
echo ""
echo "Documentation:"
echo "  • Installation guide:    INSTALLATION_GUIDE.md"
echo "  • Configuration:         config/*.yaml"
echo "  • Test suite:            ./test_taxonomy_bundle_setup.sh"
echo ""

echo "Environment variables set (in ~/.bashrc):"
echo "  EXTERNAL_VAULT=$EXTERNAL_VAULT"
echo ""

if [ -n "${PIXI_PROJECT_ROOT:-}" ]; then
    echo "Current session:"
    echo "  PIXI_PROJECT_ROOT=$PIXI_PROJECT_ROOT"
fi

echo ""
print_warning "IMPORTANT: Restart your terminal to load environment variables!"
echo ""

echo "Next steps:"
echo "  1. Restart terminal: source ~/.bashrc"
echo "  2. Download databases as needed (see above)"
echo "  3. Configure workflows in config/ directory"
echo "  4. Read INSTALLATION_GUIDE.md for detailed usage"
echo ""

print_success "Setup script complete!"
