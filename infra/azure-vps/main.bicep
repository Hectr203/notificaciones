targetScope = 'resourceGroup'

@description('Nombre del ambiente azd.')
param environmentName string

@description('Region Azure donde se desplegara el VPS.')
param location string = resourceGroup().location

@description('Usuario administrador SSH de la VM.')
param adminUsername string = 'azureuser'

@description('Llave publica SSH para acceder a la VM.')
param sshPublicKey string

@description('Tamano de VM. Standard_B1ls es el mas barato; Standard_B1s es mas seguro para 1 GB RAM.')
param vmSize string = 'Standard_B1ls'

@description('Origenes permitidos para WebSocket. Separar varios con espacios.')
param allowedOrigins string

@secure()
@description('Secreto HMAC usado por Centrifugo y el backend para JWT.')
param centrifugoTokenSecret string

@secure()
@description('API key HTTP usada solo por el backend para publicar eventos.')
param centrifugoHttpApiKey string

var safeEnvName = take(toLower(replace(environmentName, '_', '-')), 40)
var suffix = uniqueString(resourceGroup().id)
var namePrefix = '${safeEnvName}-${suffix}'
var domainLabel = take('${safeEnvName}-${suffix}', 63)
var realtimeDomain = '${domainLabel}.${location}.cloudapp.azure.com'

var cloudInit1 = replace(loadTextContent('cloud-init.yaml'), '__REALTIME_DOMAIN__', realtimeDomain)
var cloudInit2 = replace(cloudInit1, '__ALLOWED_ORIGINS__', allowedOrigins)
var cloudInit3 = replace(cloudInit2, '__TOKEN_SECRET__', centrifugoTokenSecret)
var cloudInit = replace(cloudInit3, '__HTTP_API_KEY__', centrifugoHttpApiKey)

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: '${namePrefix}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.42.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.42.1.0/24'
        }
      }
    ]
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${namePrefix}-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-HTTP'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-HTTPS'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: '${namePrefix}-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: domainLabel
    }
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: '${namePrefix}-nic'
  location: location
  properties: {
    networkSecurityGroup: {
      id: nsg.id
    }
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: '${namePrefix}-vm'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: take('${safeEnvName}-vm', 15)
      adminUsername: adminUsername
      customData: base64(cloudInit)
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        diskSizeGB: 30
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

output realtimeDomain string = realtimeDomain
output websocketUrl string = 'wss://${realtimeDomain}/connection/websocket'
output httpApiUrl string = 'https://${realtimeDomain}/api'
output sshCommand string = 'ssh ${adminUsername}@${realtimeDomain}'
