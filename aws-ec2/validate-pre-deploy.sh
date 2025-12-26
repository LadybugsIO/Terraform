#!/bin/bash
# =============================================================================
# Pre-Deploy Environment Validation
# =============================================================================
# Run this script before 'terraform apply' to validate environment variables
# locally, catching configuration errors before deployment.
#
# Usage:
#   ./validate-pre-deploy.sh
#   ./validate-pre-deploy.sh --debug           # Show debug output
#   ./validate-pre-deploy.sh --skip-cleanup    # Keep temp files for inspection
#
# Requirements:
#   - Node.js, jq, Terraform
#   - AWS CLI (only if using existing Secrets Manager ARN)
# =============================================================================

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR_URL="https://static.ladybugs.io/validate-env.js"
TEMP_ENV_FILE="/tmp/.env.ladybugs-validation"
TEMP_VALIDATOR="/tmp/validate-env.js"
SKIP_CLEANUP=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Parse arguments
DEBUG=false
for arg in "$@"; do
    case $arg in
        --skip-cleanup)
            SKIP_CLEANUP=true
            ;;
        --debug)
            DEBUG=true
            ;;
    esac
done

cleanup() {
    if [ "$SKIP_CLEANUP" = false ]; then
        rm -f "$TEMP_ENV_FILE" "$TEMP_VALIDATOR" 2>/dev/null || true
    else
        echo -e "${YELLOW}Skipping cleanup. Temp files:${NC}"
        echo "  - $TEMP_ENV_FILE"
        echo "  - $TEMP_VALIDATOR"
    fi
}

trap cleanup EXIT

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          Pre-Deploy Environment Validation                 ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check for required dependencies
check_dependency() {
    local cmd="$1"
    local name="$2"
    local install_hint="$3"

    if ! command -v "$cmd" &> /dev/null; then
        echo -e "${RED}ERROR: $name is required but not installed.${NC}"
        echo ""
        echo "Installation options:"
        echo "$install_hint"
        echo ""
        exit 1
    fi
}

check_dependency "node" "Node.js" "  - Windows: https://nodejs.org/ or 'winget install OpenJS.NodeJS'
  - macOS: 'brew install node'
  - Linux: 'sudo apt install nodejs' or 'sudo dnf install nodejs'"

check_dependency "jq" "jq (JSON processor)" "  - Windows (Git Bash): Download from https://jqlang.github.io/jq/download/
                        or 'winget install jqlang.jq'
  - macOS: 'brew install jq'
  - Linux: 'sudo apt install jq' or 'sudo dnf install jq'"

# Find terraform command (handle Windows Git Bash where terraform might not be in PATH)
TERRAFORM_CMD="terraform"
if ! command -v terraform &> /dev/null; then
    # Try to find terraform.exe on Windows
    if command -v terraform.exe &> /dev/null; then
        TERRAFORM_CMD="terraform.exe"
    elif [ -f "/c/Program Files/Terraform/terraform.exe" ]; then
        TERRAFORM_CMD="/c/Program Files/Terraform/terraform.exe"
    elif [ -f "$LOCALAPPDATA/Programs/Terraform/terraform.exe" ]; then
        TERRAFORM_CMD="$LOCALAPPDATA/Programs/Terraform/terraform.exe"
    else
        echo -e "${RED}ERROR: Terraform is required but not found in PATH.${NC}"
        echo ""
        echo "Installation options:"
        echo "  - Windows: https://developer.hashicorp.com/terraform/downloads"
        echo "             or 'winget install Hashicorp.Terraform'"
        echo "  - macOS: 'brew install terraform'"
        echo "  - Linux: https://developer.hashicorp.com/terraform/downloads"
        echo ""
        echo "If terraform is installed, add it to your PATH in ~/.bashrc:"
        echo "  export PATH=\"\$PATH:/c/path/to/terraform\""
        exit 1
    fi
fi

if [ "$DEBUG" = true ]; then
    echo -e "${YELLOW}[DEBUG] Using terraform command: $TERRAFORM_CMD${NC}"
fi

# Check we're in the right directory
if [ ! -f "$SCRIPT_DIR/main.tf" ]; then
    echo -e "${RED}ERROR: main.tf not found. Run this script from the aws-ec2 directory.${NC}"
    exit 1
fi

cd "$SCRIPT_DIR"

# Check for tfvars file
TFVARS_FILE=""
if [ -f "terraform.tfvars" ]; then
    TFVARS_FILE="terraform.tfvars"
elif [ -f "terraform.tfvars.json" ]; then
    TFVARS_FILE="terraform.tfvars.json"
else
    echo -e "${RED}ERROR: No terraform.tfvars or terraform.tfvars.json found.${NC}"
    echo "Create one from terraform.tfvars.example first."
    exit 1
fi

echo -e "${CYAN}Using variables from:${NC} $TFVARS_FILE"
echo ""

# Determine the mode: Secrets Manager ARN, Create Secrets Manager, or Direct
# We use terraform console to extract variable values
get_tf_var() {
    local var_name="$1"
    local temp_expr="/tmp/.tf_expr_$$"
    echo "var.$var_name" > "$temp_expr"
    local result=$("$TERRAFORM_CMD" console -var-file="$TFVARS_FILE" < "$temp_expr" 2>/dev/null | tr -d '"')
    if [ "$DEBUG" = true ]; then
        echo -e "${YELLOW}[DEBUG] get_tf_var($var_name):${NC}" >&2
        echo -e "${YELLOW}  expr: $(cat $temp_expr)${NC}" >&2
        echo -e "${YELLOW}  result: '$result'${NC}" >&2
    fi
    rm -f "$temp_expr"
    echo "$result"
}

get_tf_var_raw() {
    local var_name="$1"
    local temp_expr="/tmp/.tf_expr_$$"
    # Use jsonencode + nonsensitive to get proper JSON output for sensitive variables
    echo "jsonencode(nonsensitive(var.$var_name))" > "$temp_expr"

    if [ "$DEBUG" = true ]; then
        echo -e "${YELLOW}[DEBUG] get_tf_var_raw($var_name):${NC}" >&2
        echo -e "${YELLOW}  expr: $(cat $temp_expr)${NC}" >&2
        echo -e "${YELLOW}  terraform output:${NC}" >&2
        "$TERRAFORM_CMD" console -var-file="$TFVARS_FILE" < "$temp_expr" 2>&1 | head -5 | while read line; do echo -e "${YELLOW}    $line${NC}" >&2; done
    fi

    local result=$("$TERRAFORM_CMD" console -var-file="$TFVARS_FILE" < "$temp_expr" 2>/dev/null | jq -r '.' 2>/dev/null)

    if [ "$DEBUG" = true ]; then
        echo -e "${YELLOW}  jq result: '$(echo "$result" | head -c 200)'${NC}" >&2
    fi

    rm -f "$temp_expr"
    echo "$result"
}

SECRETS_MANAGER_ARN=$(get_tf_var "secrets_manager_arn")
CREATE_SECRETS_MANAGER=$(get_tf_var "create_secrets_manager")

echo -e "${CYAN}Detecting configuration mode...${NC}"

if [ -n "$SECRETS_MANAGER_ARN" ] && [ "$SECRETS_MANAGER_ARN" != "" ]; then
    # Mode: Using existing Secrets Manager secret - fetch from AWS
    echo -e "Mode: ${GREEN}Existing Secrets Manager${NC}"
    echo "ARN: $SECRETS_MANAGER_ARN"
    echo ""

    # Check for AWS CLI
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}ERROR: AWS CLI is required to fetch secrets but not installed.${NC}"
        exit 1
    fi

    echo "Fetching secrets from AWS Secrets Manager..."

    # Extract region from ARN or use default
    AWS_REGION=$(get_tf_var "aws_region")
    if [ -z "$AWS_REGION" ]; then
        AWS_REGION="us-east-1"
    fi

    # Fetch and convert to .env format
    aws secretsmanager get-secret-value \
        --secret-id "$SECRETS_MANAGER_ARN" \
        --region "$AWS_REGION" \
        --query 'SecretString' \
        --output text | jq -r 'to_entries | .[] | "\(.key)=\(.value)"' > "$TEMP_ENV_FILE"

    if [ ! -s "$TEMP_ENV_FILE" ]; then
        echo -e "${RED}ERROR: Failed to fetch secrets or secret is empty.${NC}"
        exit 1
    fi

    echo -e "${GREEN}Secrets fetched successfully.${NC}"

else
    # Mode: Using ladybugs_env_vars from tfvars (either for Secrets Manager creation or direct .env)
    if [ "$CREATE_SECRETS_MANAGER" = "true" ]; then
        echo -e "Mode: ${GREEN}Create Secrets Manager (from ladybugs_env_vars)${NC}"
    else
        echo -e "Mode: ${GREEN}Direct .env (from ladybugs_env_vars)${NC}"
    fi
    echo ""

    echo "Extracting environment variables from tfvars..."

    get_tf_var_raw "ladybugs_env_vars" | jq -r 'to_entries | .[] | "\(.key)=\(.value)"' > "$TEMP_ENV_FILE"

    if [ ! -s "$TEMP_ENV_FILE" ]; then
        echo -e "${RED}ERROR: ladybugs_env_vars is empty or not defined in $TFVARS_FILE${NC}"
        echo ""
        echo "Make sure your terraform.tfvars contains:"
        echo '  ladybugs_env_vars = {'
        echo '    "AI_PROVIDER_API_KEY" = "your-key"'
        echo '    ...'
        echo '  }'
        exit 1
    fi

    echo -e "${GREEN}Variables extracted successfully.${NC}"
fi

echo ""
echo -e "${CYAN}Downloading validator...${NC}"

if ! curl -fsSL "$VALIDATOR_URL" -o "$TEMP_VALIDATOR"; then
    echo -e "${RED}ERROR: Could not download validator from $VALIDATOR_URL${NC}"
    exit 1
fi

echo -e "${GREEN}Validator downloaded.${NC}"

echo ""
echo -e "${CYAN}Running validation...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Run validation
if node "$TEMP_VALIDATOR" --env "$TEMP_ENV_FILE" --strict; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}✓ Pre-deploy validation passed!${NC}"
    echo ""
    echo "You can now run:"
    echo -e "  ${CYAN}terraform apply${NC}"
    exit 0
else
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${RED}✗ Pre-deploy validation failed!${NC}"
    echo ""
    echo "Fix the errors above before running terraform apply."
    exit 1
fi
