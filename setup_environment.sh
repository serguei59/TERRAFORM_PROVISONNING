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
exec > >(tee -i $"$LOG_FILE") 2> >(grep -v 'password' >&2)

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
        --enable-rbac-authorization true; then
        echo "Key Vault $KEYVAULT_NAME created successfully."
    else
        echo "Failed to create Key Vault $KEYVAULT_NAME."
        exit 1
    fi
fi
#------------------------------------------
# Clean Up old Service Principals
#-------------------------------------------
OLD_SP_LIST=$(az ad sp list --query "[?contains(displayName, 'sp-kv-access-sbuasa')].{AppId:appId}" -o tsv
)
if [[ -n "$OLD_SP_LIST" ]]; then
    echo "Found old Service Principals. Deleting..."
    for SP_ID in $OLD_SP_LIST; do
        echo "Deleting Service principal with AppId: $SP_ID"
        if az ad sp delete --id "$SP_ID"; then
            echo "Service Principal with appId: $SP_ID deleted successfully."
        else
            echo "Failed to delete Service Principal with appId: $SP_ID. Skipping..."
        fi
    done
    echo "Old Service Principals deleted successfully."
else
    echo "No old Service Principals found."
fi 

#------------------------------------------
# Clean Up old App Registrations
#-------------------------------------------
OLD_APP_LIST=$(az ad app list --query "[?contains(displayName, 'sp-kv-access-sbuasa')].{AppId:appId}" -o tsv
)
if [[ -n "$OLD_APP_LIST" ]]; then
    echo "Found old App Registrations. Deleting..."
    for APP_ID in $OLD_APP_LIST; do
        echo "Deleting App Registration with AppId: $APP_ID"
        if az ad app delete --id "$APP_ID"; then
            echo "App Registrations with AppId: $APP_ID deleted successfully."
        else
            echo "Failed to delete App Registration with AppId: $APP_ID. Skipping..."
        fi
    done
    echo "Old App Registrations deleted successfully."
else	
    echo "No old App Registrations found."
fi 

#----------------------------------------------------------------------------
# Create Service Principal SP_KV_NAME for Key Vault Secrets access
#----------------------------------------------------------------------------
# Generate dynamic Service Principal name
SP_KV_NAME="${SP_KV_NAME_PREFIX}-$(date +%Y%m%d%H%M%S)"
echo "🔑 Using Service Principal Name: $SP_KV_NAME"


# Creating new Service Principal
APP_ID=$(az ad sp list --display-name "$SP_KV_NAME" --query "[0].appId" -o tsv)

if [ -n "$APP_ID" ]; then
    echo "Service Principal $SP_KV_NAME already exists."
    echo "Checking if it has the correct roles and permissions..."

    # Check if Service Principal has Key Vault Secrets User role
    ROLES=$(az role assignment list --assignee "$APP_ID" --query "[].roleDefinitionName" -o tsv)

    if [[ "$ROLES" == *"Key Vault Secrets User"* ]]; then
        echo "Service Principal $SP_KV_NAME has Key Vault Secrets User role. Skipping recreation."
    else
        echo "Service Principal $SP_KV_NAME does not have correct role. Deleting and recreating ..."
        if az ad sp delete --id "$APP_ID"; then
            echo "Service Principal $SP_KV_NAME deleted successfully."
            echo "Waiting 30 seconds to ensure Azure propagates the deletion..."
            sleep 30
        else
            echo "Failed to delete Service Principal $SP_KV_NAME."
            exit 1
        fi
    fi
fi

# Create Service Principal
echo "Creating Service Principal: $SP_KV_NAME..."
SP_OUTPUT=$(az ad sp create-for-rbac \
    --name "$SP_KV_NAME" \
    --query "{appId: appId, password: password}" -o json)
    
# Validate SP_OUTPUT
if [[ -z "$SP_OUTPUT" ]]; then
    echo "Failed to create Service Principal."
    exit 1
fi
# Extract  ClientId and ClientSecret using jq
SP_CLIENT_ID=$(echo "$SP_OUTPUT" | jq -r '.appId')
SP_CLIENT_SECRET=$(echo "$SP_OUTPUT" | jq -r '.password')

if [[ -z "$SP_CLIENT_ID" || -z "$SP_CLIENT_SECRET" ]]; then
    echo "Failed to extract ClientId and ClientSecret from Service Principal creation output"
    echo "SP_OUTPUT content: $SP_OUTPUT"
    exit 1
fi
echo "Service Principal created: $SP_KV_NAME"
echo "SP_OUTPUT content: $SP_OUTPUT"
echo "SP_CLIENT_ID: $SP_CLIENT_ID"
echo "SP_CLIENT_SECRET: $SP_CLIENT_SECRET"
#-------------
#Configuration
#-------------

# Store SubscriptionId & TenantId in Key Vault
echo "Storing secrets in Key Vault..."
SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)
TENANT_ID=$(az account show --query "tenantId" -o tsv)

echo "Storing SubscriptionId in Key Vault..."
if az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "SubscriptionId" --value "$SUBSCRIPTION_ID"; then
    echo "Secret 'SubscriptionID' stored successfully."
else
    echo "Failed to store 'SubscriptionId."
    exit 1
fi

echo "Storing TenantId in Key Vault..."
if az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "TenantId" --value "$TENANT_ID"; then
    echo "Secret 'TenantId' stored successfully."
else
    echo "Failed to store 'TenantId'."
    exit 1
fi

# Store SP ClientSecret in Key Vault
echo "Storing Service Principal ClientSecret in Key Vault..."
if az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "SP-ClientSecret" --value "$SP_CLIENT_SECRET"; then
    echo "Secret 'SP-ClientSecret' stored successfully."
else
    echo "Failed to store 'SP-ClientSecret'."
    exit 1
fi

# Add Service Principal ID to GitHub Secrets
echo "Adding Service Principal ClientId to GitHub Secrets..."
if /usr/bin/gh secret set ARM_CLIENT_ID --repo "$GITHUB_REPO" -b "$SP_CLIENT_ID"; then
    echo " Added 'SP-ClientId successfully to GitHub Secrets."
else
    echo "Failed to add 'SP-ClientId'."
    exit 1
fi

# Add Tenant ID to GitHub Secrets
echo "Adding Service Principal TenantId to GitHub Secrets..."
if /usr/bin/gh secret set ARM_TENANT_ID --repo "$GITHUB_REPO" -b "$TENANT_ID"; then
    echo " Added 'TenantId successfully to GitHub Secrets."
else
    echo "Failed to add 'TenantId'."
    exit 1
fi

echo "Service Principal created: $SP_KV_NAME"
echo "SP_OUTPUT content: $SP_OUTPUT"
echo "SP_CLIENT_ID: $SP_CLIENT_ID"
echo "SP_CLIENT_SECRET: $SP_CLIENT_SECRET"
# --------------------------------------------------------------------------------
# Customize Service Principal: Add Contributor role and Reduce Key Vault's scope
# ---------------------------------------------------------------------------------
echo "Adding Key Vault Secrets User role and Reducing Service Principal's scope to the specific Key Vault."
if az role assignment create \
    --assignee "$SP_CLIENT_ID" \
    --role "Key Vault Secrets User" \
    --scope "$(az keyvault show --name "$KEYVAULT_NAME" --query id -o tsv)"; then
    echo " Key Vault Secrets User role added and Scope reduced to Key Vault successfully for service principal $SP_CLIENT_ID."
else
    echo "Failed to assign Key Vault Secrets User role and reduce scope."
    exit 1
fi

# ------------------------------------------
# 🕒 Wait for RBAC Role Propagation (30 min max)
# ------------------------------------------

echo "🕒 Waiting for RBAC role assignment to propagate (max 30 minutes)..."
MAX_RETRIES=60  # 60 tentatives (30 minutes avec des intervalles de 30 secondes)
WAIT_TIME=30    # Temps d'attente en secondes entre les vérifications

for i in $(seq 1 $MAX_RETRIES); do
    echo "🔄 Checking RBAC propagation... Attempt $i/$MAX_RETRIES"

    # Test si le Service Principal peut accéder au Key Vault
    if az keyvault secret list --vault-name "$KEYVAULT_NAME" --query "[].id" --output table &>/dev/null; then
        echo "✅ RBAC propagation completed successfully."
        break
    else
        echo "❌ RBAC propagation not yet complete. Waiting for $WAIT_TIME seconds..."
        sleep $WAIT_TIME
    fi

    if [ "$i" -eq $MAX_RETRIES ]; then
        echo "❌ RBAC propagation failed after $((MAX_RETRIES * WAIT_TIME / 60)) minutes."
        exit 1
    fi
done




#------------------------------------------
# 🧹 Clean Sensitive Variables from Memory
#------------------------------------------

unset SP_CLIENT_ID
unset SP_CLIENT_SECRET
unset SUBSCRIPTION_ID
unset TENANT_ID
unset KEYVAULT_NAME
unset RESOURCE_GROUP_SECURITY
unset RESOURCE_GROUP_TERRAFORM
unset SP_OUTPUT
unset APP_ID
unset DELETED_KEYVAULT

echo "🧹 Sensitive variables have been cleared from memory."
