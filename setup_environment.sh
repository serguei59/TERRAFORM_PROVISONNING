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
    if az group show --name "$rg" &>/dev/null; then
        echo "✅ Resource Group $rg already exists. Skipping creation."
    else
        echo "🛠️ Creating Resource Group: $key ($rg)"
        if az group create --name "$rg" --location "$LOCATION"; then
            echo "✅ Resource Group $rg created successfully."
        else
            echo "❌ Failed to create Resource Group $rg."
            exit 1
        fi
    fi    
done

#------------------------------------------
# Create Key Vault
#------------------------------------------
# Check and handle Deleted Key Vault
echo "Checking for existing deleted Key Vault..."
DELETED_KEYVAULT=$(az keyvault list-deleted --query "[?name=='$KEYVAULT_NAME']" -o tsv)

if [ -n "$DELETED_KEYVAULT" ]; then
    echo "Key Vault $KEYVAULT_NAME exists in deleted state. Attempting to purge..."
    if az keyvault purge --name "$KEYVAULT_NAME"; then
        echo "Key Vault $KEYVAULT_NAME purged successfully."
    else
        echo "Failed to purge Key Vault $KEYVAULT_NAME."
        exit 1
    fi
fi
# Create Key Vault (if not exists)
if az keyvault show --name "$KEYVAULT_NAME" --resource-group "$RESOURCE_GROUP_SECURITY" &>/dev/null; then
    echo "✅ Key Vault $KEYVAULT_NAME already exists. Skipping creation."
else
    echo "Creating Key Vault : $KEYVAULT_NAME"
    if az keyvault create --name "$KEYVAULT_NAME" --resource-group "$RESOURCE_GROUP_SECURITY" --location "$LOCATION" \
        --enable-rbac-authorization false; then
        echo "Key Vault $KEYVAULT_NAME created successfully."
    else
        echo "Failed to create Key Vault $KEYVAULT_NAME."
        exit 1
    fi
fi

