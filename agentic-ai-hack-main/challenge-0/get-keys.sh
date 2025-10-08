#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"

USER_KEY=""
SHARED_RG="rg-aihack-shared"
USER_RG=""

print_usage() {
  echo "Usage: $0 [--user <user_key>] [--shared-rg <rg-name>] [--user-rg <rg-name>]" 1>&2
  echo "  --user: User key (e.g., user1). If not provided, will auto-discover from Owner role assignments" 1>&2
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      USER_KEY="$2"; shift 2 ;;
    --shared-rg)
      SHARED_RG="$2"; shift 2 ;;
    --user-rg)
      USER_RG="$2"; shift 2 ;;
    -h|--help)
      print_usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" 1>&2
      print_usage; exit 1 ;;
  esac
done

# Auto-discover user if not provided (similar to get-keys-bak.sh)
if [[ -z "${USER_KEY}" ]]; then
  echo "Auto-discovering user from Owner role assignments..."
  current_user=$(az account show --query user.name -o tsv 2>/dev/null || echo "")
  if [[ -n "$current_user" ]]; then
    # Try to find user key from Owner role assignments
    owner_scope=$(az role assignment list --assignee "$current_user" --role "Owner" --query "[?contains(scope, '/resourceGroups/rg-aihack-') && !contains(scope, 'shared')].scope | [0]" -o tsv 2>/dev/null || echo "")
    if [[ -n "$owner_scope" && "$owner_scope" != "null" ]]; then
      # Extract user key from RG name like "rg-aihack-user1" -> "user1"
      rg_name=$(echo "$owner_scope" | awk -F'/' '{print $NF}')
      if [[ "$rg_name" =~ ^rg-aihack-(.+)$ ]]; then
        USER_KEY="${BASH_REMATCH[1]}"
        echo "Auto-discovered user: $USER_KEY"
      fi
    fi
  fi
  
  # Fallback: try to find any rg-aihack-* resource group
  if [[ -z "$USER_KEY" ]]; then
    fallback_rg=$(az group list --query "[?starts_with(name, 'rg-aihack-') && name != '${SHARED_RG}'].name | [0]" -o tsv 2>/dev/null || echo "")
    if [[ -n "$fallback_rg" && "$fallback_rg" != "null" ]]; then
      if [[ "$fallback_rg" =~ ^rg-aihack-(.+)$ ]]; then
        USER_KEY="${BASH_REMATCH[1]}"
        echo "Auto-discovered user from fallback RG: $USER_KEY"
      fi
    fi
  fi
  
  if [[ -z "$USER_KEY" ]]; then
    echo "Could not auto-discover user. Please provide --user <user_key>" 1>&2
    exit 1
  fi
fi

if [[ -z "${USER_RG}" ]]; then
  USER_RG="rg-aihack-${USER_KEY}"
fi

echo "Checking Azure CLI login status..."
if ! az account show &>/dev/null; then
  echo "You are not logged in to Azure CLI. Initiating login..."
  az login --use-device-code 1>/dev/null
fi

subscription_id=$(az account show --query id -o tsv 2>/dev/null || echo "")
tenant_id=$(az account show --query tenantId -o tsv 2>/dev/null || echo "")
current_user=$(az account show --query user.name -o tsv 2>/dev/null || echo "")

# Auto-discover resource groups similar to get-keys-bak.sh
echo "Discovering shared and user resource groups..."
# Shared RG: prefer exact, fallback to contains 'shared'
if ! az group show --name "$SHARED_RG" &>/dev/null; then
  det_shared=$(az group list --query "[?name == 'rg-aihack-shared'].name | [0]" -o tsv 2>/dev/null || echo "")
  if [[ -z "$det_shared" || "$det_shared" == "null" ]]; then
    det_shared=$(az group list --query "[?contains(name, 'shared')].name | [0]" -o tsv 2>/dev/null || echo "")
  fi
  if [[ -n "$det_shared" && "$det_shared" != "null" ]]; then
    SHARED_RG="$det_shared"
  fi
fi

# User RG: try Owner assignment scope, then heuristics with user key
if ! az group show --name "$USER_RG" &>/dev/null; then
  if [[ -n "$current_user" ]]; then
    owner_scope=$(az role assignment list --assignee "$current_user" --role "Owner" --query "[?contains(scope, '/resourceGroups/rg-aihack-') && !contains(scope, 'shared')].scope | [0]" -o tsv 2>/dev/null || echo "")
    if [[ -n "$owner_scope" && "$owner_scope" != "null" ]]; then
      USER_RG=$(echo "$owner_scope" | awk -F'/' '{print $NF}')
    else
      cand=$(az group list --query "[?contains(name, '${USER_KEY}')].name | [0]" -o tsv 2>/dev/null || echo "")
      if [[ -z "$cand" || "$cand" == "null" ]]; then
        cand=$(az group list --query "[?starts_with(name, 'rg-aihack-') && name != '${SHARED_RG}'].name | [0]" -o tsv 2>/dev/null || echo "")
      fi
      if [[ -n "$cand" && "$cand" != "null" ]]; then
        USER_RG="$cand"
      fi
    fi
  fi
fi

echo "Using SHARED_RG='${SHARED_RG}', USER_RG='${USER_RG}'"

# Helper to safely run az and return empty string on error
az_safe() {
  local cmd="$1"
  bash -lc "$cmd" 2>/dev/null || true
}

echo "Discovering shared and user resources..."

# Shared resources (in parallel where possible)
shared_resources=$(az_safe "az resource list --resource-group ${SHARED_RG} --query '[].{name:name,type:type}' -o tsv")

get_res_name_by_type() {
  local list="$1"; local type="$2"
  echo "$list" | awk -v type="$type" '$2 == type {print $1; exit}'
}

storage_shared_name=$(get_res_name_by_type "$shared_resources" "Microsoft.Storage/storageAccounts")
ml_hub_name=$(get_res_name_by_type "$shared_resources" "Microsoft.MachineLearningServices/workspaces")
acr_shared_name=$(get_res_name_by_type "$shared_resources" "Microsoft.ContainerRegistry/registries")
appins_name=$(get_res_name_by_type "$shared_resources" "Microsoft.Insights/components")
kv_name=$(get_res_name_by_type "$shared_resources" "Microsoft.KeyVault/vaults")
apim_name=$(get_res_name_by_type "$shared_resources" "Microsoft.ApiManagement/service")

# Find AIServices account (AI Foundry)
foundry_names=$(echo "$shared_resources" | awk '$2 == "Microsoft.CognitiveServices/accounts" {print $1}')
foundry_name=""
for acc in $foundry_names; do
  kind=$(az_safe "az cognitiveservices account show --name ${acc} --resource-group ${SHARED_RG} --query kind -o tsv")
  if [[ "$kind" == "AIServices" ]]; then
    foundry_name="$acc"
    break
  fi
done

# User RG resources
user_resources=$(az_safe "az resource list --resource-group ${USER_RG} --query '[].{name:name,type:type}' -o tsv") || true
search_name=$(get_res_name_by_type "$user_resources" "Microsoft.Search/searchServices")
log_analytics_name=$(get_res_name_by_type "$user_resources" "Microsoft.OperationalInsights/workspaces")
cosmos_name=$(get_res_name_by_type "$user_resources" "Microsoft.DocumentDB/databaseAccounts")
acr_user_name=$(get_res_name_by_type "$user_resources" "Microsoft.ContainerRegistry/registries")

acr_name="$acr_user_name"
if [[ -z "$acr_name" || "$acr_name" == "null" ]]; then
  if [[ -n "$USER_KEY" ]]; then
    candidate="${USER_KEY}acr"
    candidate_exists=$(az_safe "az acr show --name ${candidate} --query name -o tsv")
    if [[ -n "$candidate_exists" && "$candidate_exists" != "null" ]]; then
      acr_name="$candidate_exists"
    fi
  fi
fi

if [[ -z "$acr_name" || "$acr_name" == "null" ]]; then
  acr_name="$acr_shared_name"
fi

# Prefer shared storage; fallback to user RG storage if shared not found
storage_name="$storage_shared_name"
storage_rg="$SHARED_RG"
if [[ -z "$storage_name" || "$storage_name" == "null" ]]; then
  storage_user_name=$(get_res_name_by_type "$user_resources" "Microsoft.Storage/storageAccounts")
  if [[ -n "$storage_user_name" && "$storage_user_name" != "null" ]]; then
    storage_name="$storage_user_name"
    storage_rg="$USER_RG"
  fi
fi

# Keys and endpoints (parallelizable via subshells)
tmpdir="$(mktemp -d)"
(
  if [[ -n "$storage_name" ]]; then
    az storage account keys list --account-name "$storage_name" --resource-group "$storage_rg" --query "[0].value" -o tsv 2>/dev/null >"$tmpdir/storage_key" || true
  fi
) &
(
  if [[ -n "$search_name" ]]; then
    az search admin-key show --service-name "$search_name" --resource-group "$USER_RG" --query primaryKey -o tsv 2>/dev/null >"$tmpdir/search_key" || true
  fi
) &
(
  if [[ -n "$cosmos_name" ]]; then
    az cosmosdb show --name "$cosmos_name" --resource-group "$USER_RG" --query documentEndpoint -o tsv 2>/dev/null >"$tmpdir/cosmos_ep" || true
    az cosmosdb keys list --name "$cosmos_name" --resource-group "$USER_RG" --query primaryMasterKey -o tsv 2>/dev/null >"$tmpdir/cosmos_key" || true
  fi
) &
(
  if [[ -n "$foundry_name" ]]; then
    az cognitiveservices account show --name "$foundry_name" --resource-group "$SHARED_RG" --query properties.endpoint -o tsv 2>/dev/null >"$tmpdir/foundry_ep" || true
    az cognitiveservices account keys list --name "$foundry_name" --resource-group "$SHARED_RG" --query key1 -o tsv 2>/dev/null >"$tmpdir/foundry_key" || true
    az cognitiveservices account deployment list --name "$foundry_name" --resource-group "$SHARED_RG" --query "[?contains(name, 'gpt')].name | [0]" -o tsv 2>/dev/null >"$tmpdir/gpt_dep" || true
    az cognitiveservices account deployment list --name "$foundry_name" --resource-group "$SHARED_RG" --query "[?contains(name, 'embedding')].name | [0]" -o tsv 2>/dev/null >"$tmpdir/emb_dep" || true
  fi
) &
(
  if [[ -n "$acr_name" ]]; then
    az acr credential show --name "$acr_name" --query username -o tsv 2>/dev/null >"$tmpdir/acr_user" || true
    az acr credential show --name "$acr_name" --query passwords[0].value -o tsv 2>/dev/null >"$tmpdir/acr_pass" || true
  fi
) &
wait

storage_key=$(cat "$tmpdir/storage_key" 2>/dev/null || echo "")
search_key=$(cat "$tmpdir/search_key" 2>/dev/null || echo "")
cosmos_ep=$(cat "$tmpdir/cosmos_ep" 2>/dev/null || echo "")
cosmos_key=$(cat "$tmpdir/cosmos_key" 2>/dev/null || echo "")
foundry_ep=$(cat "$tmpdir/foundry_ep" 2>/dev/null || echo "")
foundry_key=$(cat "$tmpdir/foundry_key" 2>/dev/null || echo "")
gpt_dep=$(cat "$tmpdir/gpt_dep" 2>/dev/null || echo "")
emb_dep=$(cat "$tmpdir/emb_dep" 2>/dev/null || echo "")
acr_user=$(cat "$tmpdir/acr_user" 2>/dev/null || echo "")
acr_pass=$(cat "$tmpdir/acr_pass" 2>/dev/null || echo "")

# Defaults
if [[ -z "$gpt_dep" || "$gpt_dep" == "null" ]]; then
  gpt_dep="gpt-4.1-mini"
fi

# AI Foundry Hub endpoint (ML Studio) from ML workspace
ai_foundry_hub_endpoint=""
if [[ -n "$ml_hub_name" && -n "$subscription_id" ]]; then
  ai_foundry_hub_endpoint="https://ml.azure.com/home?wsid=/subscriptions/${subscription_id}/resourceGroups/${SHARED_RG}/providers/Microsoft.MachineLearningServices/workspaces/${ml_hub_name}"
fi

# AI Project discovery under Foundry account
ai_project_name=""
if [[ -n "$foundry_name" && -n "$subscription_id" ]]; then
  # Try to find a project matching the new nomenclature: <user_key>-ai-project
  full_project_name=$(az rest --method get \
    --url "https://management.azure.com/subscriptions/${subscription_id}/resourceGroups/${SHARED_RG}/providers/Microsoft.CognitiveServices/accounts/${foundry_name}/projects?api-version=2025-06-01" \
    --query "value[?ends_with(name, '${USER_KEY}-ai-project')].name | [0]" -o tsv 2>/dev/null || echo "")

  # Fallback to original discovery method if not found
  if [[ -z "$full_project_name" || "$full_project_name" == "null" ]]; then
    full_project_name=$(az rest --method get \
      --url "https://management.azure.com/subscriptions/${subscription_id}/resourceGroups/${SHARED_RG}/providers/Microsoft.CognitiveServices/accounts/${foundry_name}/projects?api-version=2025-06-01" \
      --query "value[0].name" -o tsv 2>/dev/null || echo "")
  fi

  # Extract short name from formats like "hub-name/my-ai-project" → "my-ai-project"
  if [[ -n "$full_project_name" && "$full_project_name" != "null" ]]; then
    if [[ "$full_project_name" == */* ]]; then
      ai_project_name="${full_project_name##*/}"
    else
      ai_project_name="$full_project_name"
    fi
  fi

  # Strip any accidental suffix like " AI Project"
  if [[ "$ai_project_name" == *" AI Project" ]]; then
    ai_project_name="${ai_project_name% AI Project}"
  fi

  # Final fallback with new nomenclature
  if [[ -z "$ai_project_name" || "$ai_project_name" == "null" ]]; then
    ai_project_name="${USER_KEY}-ai-project"
  fi
fi

# Azure AI Search connection ID: select the project-level CognitiveSearch connection created by Terraform
azure_ai_connection_id=""
if [[ -n "$foundry_name" && -n "$ai_project_name" && -n "$subscription_id" ]]; then
  # Prefer connection explicitly named "<user>-search-connection"
  project_sc_id=$(az rest --method get \
    --url "https://management.azure.com/subscriptions/${subscription_id}/resourceGroups/${SHARED_RG}/providers/Microsoft.CognitiveServices/accounts/${foundry_name}/projects/${ai_project_name}/connections?api-version=2025-06-01" \
    --query "value[?name == '${USER_KEY}-search-connection'].id | [0]" -o tsv 2>/dev/null || echo "")

  # Fallback: first connection with category == 'CognitiveSearch'
  if [[ -z "$project_sc_id" || "$project_sc_id" == "null" ]]; then
    project_sc_id=$(az rest --method get \
      --url "https://management.azure.com/subscriptions/${subscription_id}/resourceGroups/${SHARED_RG}/providers/Microsoft.CognitiveServices/accounts/${foundry_name}/projects/${ai_project_name}/connections?api-version=2025-06-01" \
      --query "value[?properties.category == 'CognitiveSearch'].id | [0]" -o tsv 2>/dev/null || echo "")
  fi

  if [[ -n "$project_sc_id" && "$project_sc_id" != "null" ]]; then
    azure_ai_connection_id="$project_sc_id"
  fi
fi

# Compose connection strings
storage_conn_str=""
if [[ -n "$storage_name" && -n "$storage_key" ]]; then
  storage_conn_str="DefaultEndpointsProtocol=https;AccountName=${storage_name};AccountKey=${storage_key};EndpointSuffix=core.windows.net"
fi

cosmos_conn_str=""
if [[ -n "$cosmos_ep" && -n "$cosmos_key" ]]; then
  cosmos_conn_str="AccountEndpoint=${cosmos_ep};AccountKey=${cosmos_key};"
fi

search_endpoint=""
if [[ -n "$search_name" ]]; then
  search_endpoint="https://${search_name}.search.windows.net"
fi

# AI Foundry Project API endpoint
ai_foundry_project_endpoint=""
if [[ -n "$foundry_name" && -n "$ai_project_name" ]]; then
  ai_foundry_project_endpoint="https://${foundry_name}.services.ai.azure.com/api/projects/${ai_project_name}"
fi

# Write .env
rm -f "$ENV_FILE"
{
  echo "AZURE_STORAGE_ACCOUNT_NAME=\"$storage_name\""
  echo "AZURE_STORAGE_ACCOUNT_KEY=\"$storage_key\""
  echo "AZURE_STORAGE_CONNECTION_STRING=\"$storage_conn_str\""

  echo "LOG_ANALYTICS_WORKSPACE_NAME=\"$log_analytics_name\""
  echo "SEARCH_SERVICE_NAME=\"$search_name\""
  echo "SEARCH_SERVICE_ENDPOINT=\"$search_endpoint\""
  echo "SEARCH_ADMIN_KEY=\"$search_key\""

  echo "AI_FOUNDRY_HUB_NAME=\"$foundry_name\""
  echo "AI_FOUNDRY_PROJECT_NAME=\"$ai_project_name\""
  echo "AI_FOUNDRY_ENDPOINT=\"$foundry_ep\""
  echo "AI_FOUNDRY_KEY=\"$foundry_key\""
  echo "AI_FOUNDRY_HUB_ENDPOINT=\"$ai_foundry_hub_endpoint\""
  echo "AI_FOUNDRY_PROJECT_ENDPOINT=\"$ai_foundry_project_endpoint\""
  echo "AZURE_AI_CONNECTION_ID=\"$azure_ai_connection_id\""

  echo "COSMOS_ENDPOINT=\"$cosmos_ep\""
  echo "COSMOS_KEY=\"$cosmos_key\""
  echo "COSMOS_CONNECTION_STRING=\"$cosmos_conn_str\""

  # Back-compat OpenAI-style variables pointing to AI Foundry
  echo "AZURE_OPENAI_SERVICE_NAME=\"$foundry_name\""
  echo "AZURE_OPENAI_ENDPOINT=\"$foundry_ep\""
  echo "AZURE_OPENAI_KEY=\"$foundry_key\""
  echo "AZURE_OPENAI_DEPLOYMENT_NAME=\"$gpt_dep\""
  echo "MODEL_DEPLOYMENT_NAME=\"$gpt_dep\""

  echo "ACR_NAME=\"$acr_name\""
  echo "ACR_USERNAME=\"$acr_user\""
  echo "ACR_PASSWORD=\"$acr_pass\""
} >> "$ENV_FILE"

echo "Keys and properties are stored in '.env' file successfully."

echo ""
echo "=== Configuration Summary ==="
echo "Shared RG: $SHARED_RG"
echo "User RG:   $USER_RG"
echo "Storage Account: $storage_name"
echo "Log Analytics Workspace: $log_analytics_name"
echo "Search Service: $search_name"
echo "API Management: $apim_name"
echo "AI Foundry (AIServices): $foundry_name"
echo "AI Foundry Project: $ai_project_name"
echo "Container Registry: $acr_name"
if [[ -n "$cosmos_name" ]]; then
  echo "Cosmos DB: $cosmos_name"
else
  echo "Cosmos DB: NOT FOUND"
fi
echo "Environment file created: $ENV_FILE"

missing_services=""
if [[ -z "$storage_shared_name" ]]; then missing_services+=" Storage"; fi
if [[ -z "$search_name" ]]; then missing_services+=" Search"; fi
if [[ -z "$foundry_name" ]]; then missing_services+=" AI-Foundry"; fi
if [[ -n "$missing_services" ]]; then
  echo ""
  echo "⚠️  Missing services:${missing_services}"
  echo "Verify your Terraform deployment or override RG names via flags."
fi

rm -rf "$tmpdir" 2>/dev/null || true


