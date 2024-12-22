#!/bin/bash

#------------------------------------------
# Variables and prerequisite
#------------------------------------------
#chemin vers .env
#$0 : représente le chemin du script actuellement exécuté
#dirname "$0" : permet d'obtenir le répertoire où se trouve le script.
ENV_FILE="$(cd "$(dirname "$0")" && pwd)/.env"

# Load existing environnment variables
if [ -f "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
else
    echo ".env not found, please create one filled with required variables"
    exit 1
fi

# enable logging
LOG_FILE="$(cd "$(dirname "$0")" && pwd)/setup_environment.log"
exec > >(tee -i $"$LOG_FILE")

# Verify Azure CLI Login
if ! az account show &>/dev/null; then
    echo "You're not logged into Azure Cli.Please run 'az login' and try again"
    exit 1
fi
echo "Azure CLI login verified"

# Check if GitHub CLI is installed
if ! command -v gh &>/dev/null; then
    echo "GitHub CLI is not installed or not in Path."
    echo "Please install it, GitHub CLI: https://cli.github.com/"
    exit 1
fi
echo "GitHub CLI is installed"

#------------------------------------------
# Create Resource Groups
#------------------------------------------
echo "🛠️ Creating Resource Groups..."

declare -A RESOURCE_GROUPS=(
    ["SECURITY"]="$RESOURCE_GROUP_SECURITY"
    ["TERRAFORM"]="$RESOURCE_GROUP_TERRAFORM"
)

for key in "${!RESOURCE_GROUPS[@]}"; do
    rg=${RESOURCE_GROUPS[$key]}
    echo "🛠️ Creating Resource Group: $key ($rg)"
    if az group create --name "$rg" --location "$LOCATION"; then
        echo "✅ Resource Group $rg created successfully."
    else
        echo "❌ Failed to create Resource Group $rg."
        exit 1
    fi
done