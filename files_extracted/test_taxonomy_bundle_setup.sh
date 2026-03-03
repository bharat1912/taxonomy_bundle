#!/bin/bash
# ============================================================================
# TAXONOMY_BUNDLE INSTALLATION & VERIFICATION TEST SCRIPT
# Author: Bharat K.C. Patel
# Version: 1.0
# ============================================================================
# Purpose: Comprehensive testing script to verify taxonomy_bundle setup
#          before GitHub upload and after cloning to a new computer
#
# Usage: 
#   bash test_taxonomy_bundle_setup.sh [--skip-databases]
#
# Options:
#   --skip-databases    Skip database download tests (for quick testing)
# ============================================================================

set -e  # Exit on error
set -u  # Exit on undefined variable

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Flags
SKIP_DATABASES=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --skip-databases)
            SKIP_DATABASES=true
            shift
            ;;
    esac
done

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_test() {
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    echo -e "${YELLOW}[TEST $TESTS_TOTAL]${NC} $1"
}

print_success() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓ PASS:${NC} $1"
}

print_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗ FAIL:${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ INFO:${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠ WARNING:${NC} $1"
}

# ============================================================================
# SECTION 1: ENVIRONMENT SETUP VERIFICATION
# ============================================================================

print_header "SECTION 1: ENVIRONMENT SETUP VERIFICATION"

# Test 1: Check if pixi is installed
print_test "Checking if pixi is installed"
if command -v pixi &> /dev/null; then
    PIXI_VERSION=$(pixi --version 2>&1 || echo "unknown")
    print_success "Pixi is installed: $PIXI_VERSION"
else
    print_fail "Pixi is not installed. Install from: https://pixi.sh"
    exit 1
fi

# Test 2: Check if we're in the project directory
print_test "Checking project structure"
if [ ! -f "pixi.toml" ]; then
    print_fail "pixi.toml not found. Are you in the taxonomy_bundle directory?"
    exit 1
else
    print_success "Found pixi.toml in current directory"
fi

# Test 3: Verify required config files exist
print_test "Checking for configuration files"
REQUIRED_CONFIGS=(
    "config/config_taxonomy.yaml"
    "config/config_taxonomy_merged.yaml"
    "config/config_SRAsearch.yaml"
    "config/config_hybracter.yaml"
    "config/config_busco.yaml"
    "config/config_busco.ini"
    "config/config_auto.yaml"
)

CONFIG_MISSING=0
for config_file in "${REQUIRED_CONFIGS[@]}"; do
    if [ -f "$config_file" ]; then
        print_success "Found: $config_file"
    else
        print_fail "Missing: $config_file"
        CONFIG_MISSING=$((CONFIG_MISSING + 1))
    fi
done

if [ $CONFIG_MISSING -gt 0 ]; then
    print_warning "$CONFIG_MISSING configuration file(s) missing"
fi

# Test 4: Verify Snakefile presence
print_test "Checking for Snakefiles"
REQUIRED_SNAKEFILES=(
    "Snakefile_SRAsearch.smk"
    "Snakefile_hybrid_taxonomy.smk"
    "Snakefile_autocycler.smk"
)

SNAKEFILE_MISSING=0
for snakefile in "${REQUIRED_SNAKEFILES[@]}"; do
    if [ -f "$snakefile" ]; then
        print_success "Found: $snakefile"
    else
        print_fail "Missing: $snakefile"
        SNAKEFILE_MISSING=$((SNAKEFILE_MISSING + 1))
    fi
done

if [ $SNAKEFILE_MISSING -gt 0 ]; then
    print_warning "$SNAKEFILE_MISSING Snakefile(s) missing"
fi

# ============================================================================
# SECTION 2: PIXI ENVIRONMENT INSTALLATION
# ============================================================================

print_header "SECTION 2: PIXI ENVIRONMENT INSTALLATION"

# Test 5: Install/update default environment
print_test "Installing default environment"
if pixi install; then
    print_success "Default environment installed successfully"
else
    print_fail "Failed to install default environment"
fi

# Test 6: List all available environments
print_test "Listing available environments"
print_info "Available Pixi environments:"
pixi info
print_success "Environment list retrieved"

# Test 7: Verify specific environments
print_test "Verifying key environments exist"
REQUIRED_ENVS=(
    "env-a"
    "env-b"
    "env-busco"
    "env-checkm2"
    "env-ezaai"
    "env-a"
    "env-hybracter"
)

for env in "${REQUIRED_ENVS[@]}"; do
    if pixi list -e "$env" &> /dev/null; then
        print_success "Environment $env is available"
    else
        print_warning "Environment $env may not be configured"
    fi
done

# ============================================================================
# SECTION 3: EXTERNAL VAULT SETUP
# ============================================================================

print_header "SECTION 3: EXTERNAL VAULT SETUP"

# Test 8: Check EXTERNAL_VAULT environment variable
print_test "Checking EXTERNAL_VAULT configuration"
if [ -n "${EXTERNAL_VAULT:-}" ]; then
    print_success "EXTERNAL_VAULT is set to: $EXTERNAL_VAULT"
    
    # Test 9: Verify vault directory exists or can be created
    print_test "Verifying vault directory"
    if [ -d "$EXTERNAL_VAULT" ]; then
        print_success "Vault directory exists: $EXTERNAL_VAULT"
    else
        print_warning "Vault directory does not exist. Will be created by setup-vault"
    fi
else
    print_fail "EXTERNAL_VAULT environment variable not set"
    print_info "Set it with: export EXTERNAL_VAULT=/path/to/your/external/storage"
    print_info "Add to your ~/.bashrc: echo 'export EXTERNAL_VAULT=/path/to/storage' >> ~/.bashrc"
fi

# Test 10: Run vault setup
if [ -n "${EXTERNAL_VAULT:-}" ]; then
    print_test "Running vault setup (pixi run setup-vault)"
    if pixi run setup-vault; then
        print_success "Vault setup completed successfully"
    else
        print_fail "Vault setup failed"
    fi
    
    # Test 11: Verify db_link directory structure
    print_test "Verifying db_link symlinks"
    if [ -d "db_link" ]; then
        print_success "db_link directory exists"
        
        EXPECTED_LINKS=(
            "db_link/gtdbtk"
            "db_link/bakta"
            "db_link/plassembler"
            "db_link/checkm2"
            "db_link/taxonkit"
            "db_link/busco"
            "db_link/dfast_qc_ref"
        )
        
        for link in "${EXPECTED_LINKS[@]}"; do
            if [ -L "$link" ]; then
                print_success "Symlink exists: $link -> $(readlink $link)"
            else
                print_warning "Symlink missing: $link"
            fi
        done
    else
        print_fail "db_link directory not created"
    fi
    
    # Test 12: Run vault audit
    print_test "Running vault audit"
    print_info "Current vault status:"
    pixi run vault-audit || print_warning "Vault audit failed (may be empty)"
fi

# ============================================================================
# SECTION 4: DATABASE INSTALLATION (OPTIONAL)
# ============================================================================

if [ "$SKIP_DATABASES" = false ]; then
    print_header "SECTION 4: DATABASE INSTALLATION TESTS"
    
    print_warning "Database installation tests are OPTIONAL and SLOW"
    print_warning "These tests will download large databases (100s of GB total)"
    print_info "Skipped databases can be downloaded later with individual commands"
    
    # Test 13: Check if databases already exist
    print_test "Checking for existing databases"
    
    check_database() {
        local db_name=$1
        local check_file=$2
        
        if [ -f "$EXTERNAL_VAULT/$db_name/$check_file" ]; then
            print_success "$db_name database already installed"
            return 0
        else
            print_info "$db_name database not found"
            return 1
        fi
    }
    
    # Check Plassembler (smallest, good first test)
    if ! check_database "plassembler" "plsdb_2023_11_03_v2.msh"; then
        print_test "Installing Plassembler database (~363 MB)"
        print_info "This is a small database and good for testing"
        read -p "Install Plassembler database? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if pixi run download-plassembler; then
                print_success "Plassembler database installed"
            else
                print_fail "Plassembler database installation failed"
            fi
        else
            print_info "Skipping Plassembler installation"
        fi
    fi
    
    # Check Bakta (medium size)
    if ! check_database "bakta" "manifest.json"; then
        print_test "Bakta database check (~62 GB)"
        print_warning "This is a large download. Consider running in tmux session"
        print_info "Command: tmux new -s bakta && pixi run download-bakta"
        print_info "Skipping automatic installation. Run manually when ready."
    fi
    
    # Check GTDB-Tk (very large)
    if ! check_database "gtdb_226" "metadata/metadata.txt"; then
        print_test "GTDB-Tk database check (~141 GB download, ~250 GB extracted)"
        print_warning "This is a VERY large download. MUST run in tmux session"
        print_info "Command: tmux new -s gtdbtk && pixi run download-gtdbtk"
        print_info "Skipping automatic installation. Run manually when ready."
    fi
    
else
    print_header "SECTION 4: DATABASE INSTALLATION (SKIPPED)"
    print_info "Database installation tests skipped (--skip-databases flag)"
    print_info "To download databases manually:"
    print_info "  Plassembler:  pixi run download-plassembler"
    print_info "  Bakta:        tmux new -s bakta && pixi run download-bakta"
    print_info "  GTDB-Tk:      tmux new -s gtdbtk && pixi run download-gtdbtk"
    print_info "  CheckM2:      pixi run -e env-checkm2 download-checkm2"
fi

# ============================================================================
# SECTION 5: ENVIRONMENT-SPECIFIC TOOL TESTS
# ============================================================================

print_header "SECTION 5: ENVIRONMENT-SPECIFIC TOOL TESTS"

# Test 14: Test env-a tools
print_test "Testing env-a (Python 3.9 stack)"
if pixi run -e env-a python --version 2>&1 | grep -q "3.9"; then
    print_success "env-a Python 3.9 verified"
else
    print_fail "env-a Python version mismatch"
fi

# Test BIT availability in env-a
if pixi run -e env-a bit --help &> /dev/null; then
    print_success "BIT tool available in env-a"
else
    print_warning "BIT tool not found in env-a"
fi

# Test 15: Test env-b tools
print_test "Testing env-b (Python 3.12 + Snakemake)"
if pixi run -e env-b python --version 2>&1 | grep -q "3.12"; then
    print_success "env-b Python 3.12 verified"
else
    print_fail "env-b Python version mismatch"
fi

# Test Snakemake in env-b
if pixi run -e env-b snakemake --version &> /dev/null; then
    SNAKEMAKE_VER=$(pixi run -e env-b snakemake --version 2>&1)
    print_success "Snakemake available in env-b: $SNAKEMAKE_VER"
else
    print_fail "Snakemake not found in env-b"
fi

# Test 16: Test env-busco
print_test "Testing env-busco (BUSCO 6.x)"
if pixi run -e env-busco busco --version &> /dev/null; then
    BUSCO_VER=$(pixi run -e env-busco busco --version 2>&1)
    print_success "BUSCO available: $BUSCO_VER"
else
    print_fail "BUSCO not found in env-busco"
fi

# Test 17: Test env-ezaai (Legacy Java)
print_test "Testing env-ezaai (Legacy OpenJDK 8)"
if pixi run -e env-ezaai java -version 2>&1 | grep -q "1.8"; then
    print_success "env-ezaai Java 8 verified"
else
    print_warning "env-ezaai Java version may not be 1.8"
fi

# Test 18: Test env-checkm2
print_test "Testing env-checkm2"
if pixi run -e env-checkm2 checkm2 --version &> /dev/null; then
    CHECKM2_VER=$(pixi run -e env-checkm2 checkm2 --version 2>&1)
    print_success "CheckM2 available: $CHECKM2_VER"
else
    print_warning "CheckM2 not found in env-checkm2"
fi

# ============================================================================
# SECTION 6: WORKFLOW TESTS (DRY RUN)
# ============================================================================

print_header "SECTION 6: WORKFLOW TESTS (DRY RUN)"

# Test 19: SRA search workflow dry run
print_test "Testing SRA search workflow (dry run)"
if pixi run -e env-a snakemake -s Snakefile_SRAsearch.smk --dry-run &> /dev/null; then
    print_success "SRA search workflow syntax OK"
else
    print_warning "SRA search workflow dry run had issues (may need config adjustment)"
fi

# Test 20: Taxonomy workflow dry run
print_test "Testing taxonomy workflow (dry run)"
if [ -f "Snakefile_hybrid_taxonomy.smk" ]; then
    if pixi run -e env-a snakemake -s Snakefile_hybrid_taxonomy.smk --dry-run &> /dev/null; then
        print_success "Taxonomy workflow syntax OK"
    else
        print_warning "Taxonomy workflow dry run had issues (may need config adjustment)"
    fi
else
    print_warning "Taxonomy Snakefile not found"
fi

# Test 21: Autocycler workflow dry run
print_test "Testing autocycler workflow (dry run)"
if [ -f "Snakefile_autocycler.smk" ]; then
    if pixi run -e env-a snakemake -s Snakefile_autocycler.smk --dry-run &> /dev/null; then
        print_success "Autocycler workflow syntax OK"
    else
        print_warning "Autocycler workflow dry run had issues (may need config adjustment)"
    fi
else
    print_warning "Autocycler Snakefile not found"
fi

# ============================================================================
# SECTION 7: ADDITIONAL UTILITIES
# ============================================================================

print_header "SECTION 7: ADDITIONAL UTILITIES"

# Test 22: Check for helper scripts
print_test "Checking for helper scripts directory"
if [ -d "scripts" ]; then
    print_success "Scripts directory exists"
    SCRIPT_COUNT=$(find scripts -type f -name "*.py" -o -name "*.sh" | wc -l)
    print_info "Found $SCRIPT_COUNT script files"
else
    print_warning "Scripts directory not found"
fi

# Test 23: Check for local_data directory structure
print_test "Checking for local_data directory structure"
if [ -d "local_data" ]; then
    print_success "local_data directory exists"
else
    print_info "local_data directory will be created when needed"
fi

# Test 24: Test MiGA setup
print_test "Testing MiGA installation"
if pixi run miga-cli about &> /dev/null; then
    print_success "MiGA CLI is functional"
else
    print_warning "MiGA CLI may need additional setup"
fi

# ============================================================================
# SECTION 8: GITHUB READINESS CHECK
# ============================================================================

print_header "SECTION 8: GITHUB READINESS CHECK"

# Test 25: Check .gitignore exists
print_test "Checking .gitignore configuration"
if [ -f ".gitignore" ]; then
    print_success ".gitignore exists"
    
    # Check for important exclusions
    if grep -q "db_link" .gitignore && grep -q ".pixi" .gitignore; then
        print_success ".gitignore contains important exclusions"
    else
        print_warning ".gitignore may need updates for db_link and .pixi"
    fi
else
    print_warning ".gitignore not found - should create one"
fi

# Test 26: Check for large files that shouldn't be committed
print_test "Checking for large files in repository"
LARGE_FILES=$(find . -type f -size +100M 2>/dev/null | grep -v ".pixi" | grep -v "db_link" || true)
if [ -z "$LARGE_FILES" ]; then
    print_success "No large files found in repository"
else
    print_warning "Large files found (should be in .gitignore):"
    echo "$LARGE_FILES"
fi

# Test 27: Verify no absolute paths in config files
print_test "Checking for absolute paths in config files"
ABSOLUTE_PATHS=$(grep -r "/home/bharat" config/ 2>/dev/null || true)
if [ -z "$ABSOLUTE_PATHS" ]; then
    print_success "No absolute paths found in config files"
else
    print_warning "Absolute paths found in config files (should be relative):"
    echo "$ABSOLUTE_PATHS" | head -n 5
fi

# ============================================================================
# SECTION 9: FINAL SUMMARY
# ============================================================================

print_header "FINAL SUMMARY"

echo ""
echo "Test Results:"
echo "  Total Tests:  $TESTS_TOTAL"
echo -e "  ${GREEN}Passed:       $TESTS_PASSED${NC}"
echo -e "  ${RED}Failed:       $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ ALL TESTS PASSED!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Your taxonomy_bundle setup is ready for:"
    echo "  1. GitHub upload"
    echo "  2. Cloning to another computer"
    echo ""
    echo "Next steps:"
    echo "  1. Review any warnings above"
    echo "  2. Update .gitignore if needed"
    echo "  3. Replace absolute paths with relative paths in configs"
    echo "  4. Create a README.md with setup instructions"
    echo "  5. Commit and push to GitHub"
else
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}⚠ SOME TESTS FAILED${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    echo "Please review the failures above and:"
    echo "  1. Fix any critical issues (marked in RED)"
    echo "  2. Review warnings (marked in YELLOW)"
    echo "  3. Re-run this script to verify fixes"
fi

echo ""
echo "For database installation on new computer:"
echo "  1. Set EXTERNAL_VAULT: export EXTERNAL_VAULT=/path/to/storage"
echo "  2. Run vault setup: pixi run setup-vault"
echo "  3. Download databases as needed (see Section 4)"
echo ""

exit $TESTS_FAILED
