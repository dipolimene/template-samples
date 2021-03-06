################
# SCRIPT HEADER
################

# ./agicdeployment.sh #

# Prompt for variables
#$azsubscriptionname = Read-Host 'Enter the name of the Azure Subscription you want to use.'
#$ResourceGroupName = Read-Host 'Enter the name of the Resource Group that contains the AKS Cluster.'
#$AKSClusterName = Read-Host 'Enter the name of the AKS Cluster you want to use.'
#$MgmtName = Read-Host 'Enter the name of the new Managed Identity.'

az login --service-principal -u http://azure-cli-2020-12-01-13-04-20 -p oKl4mE.wTmdVGOKHf96juizai5faH-v3-u --tenant 186fd90f-50d1-4e88-8845-639ce0346a8c

$azsubscriptionname = ""
$ResourceGroupName = ""
$AKSClusterName = ""
$MgmtName = ""

# Set the current Azure subscription
az account set --subscription "$azsubscriptionname"

# Connect to the AKS Cluster 
az aks get-credentials --resource-group $ResourceGroupName --name $AKSClusterName --admin

# Create a managed identity 
az identity create -g $ResourceGroupName -n $MgmtName

# Wait time for ID to be fully created.
Start-Sleep -Seconds 50

# Obtain clientID for the new managed identity
$identityClientId = (az identity show -g $ResourceGroupName -n $MgmtName --query 'clientId' -o tsv)

# Obtain ResourceID for the new managed identity
$identityResourceId = (az identity show -g $ResourceGroupName -n $MgmtName --query 'id' -o tsv)

# Obtain the Subscription ID
$subscriptionId = (az account show --query 'id' -o tsv)

# Get Application Gateway Name
$applicationGatewayName = (az network application-gateway list --resource-group $ResourceGroupName --query '[].name' -o tsv)

# Get the App Gateway ID 
$AppgwID = az network application-gateway list --query "[?name=='$applicationGatewayName']" | jq -r ".[].id"

# Obtain the AKS Node Pool Name
$AKSNodePoolName = (az aks nodepool list --cluster-name $AKSClusterName --resource-group $ResourceGroupName --query '[].name' -o tsv)

# Obtain the AKS Node Pool ID
$AKSNodePoolID = (az aks nodepool show --cluster-name $AKSClusterName --name $AKSNodePoolName --resource-group $ResourceGroupName --query 'id' -o tsv)

# Obtain the AKS Kubelet Identity ObjectId
$kubeletidentityobjectId = (az aks show -g $ResourceGroupName -n $AKSClusterName --query 'identityProfile.kubeletidentity.objectId' -o tsv)

# Obtain ResourceID for the Kubelet Identity
$kubeletidentityResourceID = (az aks show -g $ResourceGroupName -n $AKSClusterName --query 'identityProfile.kubeletidentity.resourceId' -o tsv)

# Obtain ClientID for the Kubelet Identity
$kubeletidentityClientID = (az aks show -g $ResourceGroupName -n $AKSClusterName --query 'identityProfile.kubeletidentity.clientId' -o tsv)

# Obtain the AKS Node Resource Group
$AKSNodeRG = (az aks list --resource-group $ResourceGroupName --subscription $azsubscriptionname --query '[].nodeResourceGroup' -o tsv)

# Give the identity Contributor access to the Application Gateway
az role assignment create --role Contributor --assignee $identityClientId --scope $AppgwID

# Get the Application Gateway resource group ID
$ResourceGroupID = az group list --query "[?name=='$ResourceGroupName']" | jq -r ".[0].id"

# Give the identity Reader access to the Application Gateway resource group
az role assignment create --role Contributor --assignee $identityClientId --scope $ResourceGroupID

# Give the identity Contributor access to the Resource Group
az role assignment create --assignee $identityClientId --role "Contributor" --scope $ResourceGroupID

# Give the identity Contributor access to the AKSNodePool
az role assignment create --assignee $identityClientId --role "Contributor" --scope $AKSNodePoolID

# Assign the Kubelet Identity objectId contributor access to the AKS Node RG
az role assignment create --assignee $kubeletidentityobjectId  --role "Contributor" --scope /subscriptions/$subscriptionId/resourceGroups/$AKSNodeRG

# Assign the Kubelet Identity the Managed Identity Operator role on the new managed identity
az role assignment create --assignee $kubeletidentityobjectId  --role "Managed Identity Operator" --scope $identityResourceId

# Deploy an AAD pod identity in an RBAC-enabled cluster (comment line 62 if not using an RBAC-enabled cluster.)
kubectl create -f https://raw.githubusercontent.com/Azure/aad-pod-identity/master/deploy/infra/deployment-rbac.yaml

# Deploy AAD pod identity in non-RBAC cluster (un-comment line 64 if using a non-RBAC cluster.)
# kubectl apply -f https://raw.githubusercontent.com/Azure/aad-pod-identity/master/deploy/infra/deployment.yaml

# Downloads and renames the sample-helm-config.yaml file to helm-agic-config.yaml.
wget https://raw.githubusercontent.com/Azure/application-gateway-kubernetes-ingress/master/docs/examples/sample-helm-config.yaml -O helm-agic-config.yaml

# Link for reference to content of the sample-helm-config.yaml file
#https://azure.github.io/application-gateway-kubernetes-ingress/examples/sample-helm-config.yaml

# Updates the helm-agic-config.yaml and sets RBAC enabled to true using Sed.
sed -i "" "s|<subscriptionId>|${subscriptionId}|g" helm-agic-config.yaml
sed -i "" "s|<resourceGroupName>|${ResourceGroupName}|g" helm-agic-config.yaml
sed -i "" "s|<applicationGatewayName>|${applicationGatewayName}|g" helm-agic-config.yaml
sed -i "" "s|<identityResourceId>|${identityResourceId}|g" helm-agic-config.yaml
sed -i "" "s|<identityClientId>|${identityClientId}|g" helm-agic-config.yaml
sed -i -e "" "s|enabled: false # true/false|enabled: true # true/false|" helm-agic-config.yaml

# Adds the Application Gateway Ingress Controller helm chart repo and updates the repo on the AKS cluster.
helm repo add application-gateway-kubernetes-ingress https://appgwingress.blob.core.windows.net/ingress-azure-helm-package/
helm repo update

# Installs the Application Gateway Ingress Controller using helm and helm-agic-config.yaml
helm upgrade --install appgw-ingress-azure -f helm-agic-config.yaml application-gateway-kubernetes-ingress/ingress-azure

# Install a sample app
curl https://raw.githubusercontent.com/Azure/application-gateway-kubernetes-ingress/master/docs/examples/aspnetapp.yaml -o aspnetapp.yaml

# Apply the YAML file
kubectl apply -f aspnetapp.yaml