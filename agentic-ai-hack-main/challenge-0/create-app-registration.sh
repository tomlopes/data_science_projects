#!/bin/bash
set -e

APP_NAME="$1"
if [ -z "$APP_NAME" ]; then
  echo "Usage: $0 <app-name>"
  exit 1
fi

echo "Creating Azure AD app registration: $APP_NAME"
APP_REG=$(az ad app create --display-name "$APP_NAME")
CLIENT_ID=$(echo "$APP_REG" | jq -r '.appId')

echo "Creating service principal for app registration..."
az ad sp create --id "$CLIENT_ID" >/dev/null

# Wait for service principal to be available
for i in {1..12}; do  # up to 1 minute
  SP_SHOW=$(az ad sp show --id "$CLIENT_ID" 2>/dev/null || echo "")
  OBJECT_ID=$(echo "$SP_SHOW" | jq -r '.id')
  if [ "$OBJECT_ID" != "null" ] && [ -n "$OBJECT_ID" ]; then
    break
  fi
  echo "Waiting for service principal to propagate..."
  sleep 5
done

# Fallback: Try to retrieve by display name if still not found
if [ "$OBJECT_ID" == "null" ] || [ -z "$OBJECT_ID" ]; then
  echo "Trying fallback method using display name..."
  OBJECT_ID=$(az ad sp list --filter "displayName eq '$APP_NAME'" --query ".id" -o tsv)
fi

echo "Client ID: $CLIENT_ID"
echo "Service Principal Object ID: $OBJECT_ID"

TENANT_ID=$(az account show | jq -r '.tenantId')

# Get current subscription and resource group for role assignments
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo "Subscription ID: $SUBSCRIPTION_ID"

# Prompt for resource group name if creating a service principal for AI Services
echo ""
echo "Enter the resource group name where your AI Services are deployed (press Enter to skip role assignments):"
read RESOURCE_GROUP

if [ -n "$RESOURCE_GROUP" ]; then
    echo ""
    echo "🔐 Assigning necessary AI Services permissions to service principal..."
    
    # Get AI Foundry Hub name from the resource group
    AI_FOUNDRY_HUB=$(az cognitiveservices account list --resource-group "$RESOURCE_GROUP" --query "[?kind=='AIServices'].name | [0]" -o tsv 2>/dev/null || echo "")
    
    if [ -n "$AI_FOUNDRY_HUB" ]; then
        echo "Found AI Foundry Hub: $AI_FOUNDRY_HUB"
        
        # Assign Cognitive Services User role for general access
        echo "Assigning 'Cognitive Services User' role..."
        az role assignment create \
            --assignee "$CLIENT_ID" \
            --role "Cognitive Services User" \
            --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
            2>/dev/null || echo "Role assignment may already exist"
        
        # Assign Cognitive Services Contributor role for agent creation
        echo "Assigning 'Cognitive Services Contributor' role..."
        az role assignment create \
            --assignee "$CLIENT_ID" \
            --role "Cognitive Services Contributor" \
            --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.CognitiveServices/accounts/$AI_FOUNDRY_HUB" \
            2>/dev/null || echo "Role assignment may already exist"
        
        # Assign Azure AI Developer role for AI Foundry access
        echo "Assigning 'Azure AI Developer' role..."
        az role assignment create \
            --assignee "$CLIENT_ID" \
            --role "Azure AI Developer" \
            --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.CognitiveServices/accounts/$AI_FOUNDRY_HUB" \
            2>/dev/null || echo "Role assignment may already exist"
            
        echo "✅ AI Services permissions assigned successfully"
    else
        echo "⚠️  No AI Foundry Hub found in resource group '$RESOURCE_GROUP'"
        echo "Please assign the following roles manually:"
        echo "   - Cognitive Services User (Resource Group scope)"
        echo "   - Cognitive Services Contributor (AI Foundry Hub scope)"
        echo "   - Azure AI Developer (AI Foundry Hub scope)"
    fi
else
    echo "Skipping role assignments. Please assign necessary roles manually if needed."
fi

echo "App Registration created."
echo "Client ID: $CLIENT_ID"
echo "Service Principal Object ID: $OBJECT_ID"
echo "Directory (tenant) ID: $TENANT_ID"
