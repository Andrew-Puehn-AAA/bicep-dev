targetScope = 'resourceGroup'

// ============================================================
// PARAMETERS
// ============================================================

@description('Azure region for all resources.')
param location string = 'eastus2'

@description('Linux administrator username.')
param adminUsername string = 'azureadmin'

@description('SSH public key for the Linux administrator account.')
param sshPublicKey string

@description('Azure VM size.')
param vmSize string = 'Standard_B1ms'

@description('Daily VM auto-shutdown time in HHmm 24-hour format.')
param shutdownTime string = '1900'

@description('Windows time zone ID used by Azure auto-shutdown.')
param shutdownTimeZone string = 'Eastern Standard Time'

// ============================================================
// VARIABLES
// ============================================================

var commonTags = {
  Environment: 'Sandbox'
  Workload: 'AxisTest'
  ManagedBy: 'Bicep'
}

// ============================================================
// APPLICATION SECURITY GROUPS
// ============================================================

resource asg001 'Microsoft.Network/applicationSecurityGroups@2024-05-01' = {
  name: 'asg-axistest001-eus2'
  location: location
  tags: commonTags
}

resource asg002 'Microsoft.Network/applicationSecurityGroups@2024-05-01' = {
  name: 'asg-axistest002-eus2'
  location: location
  tags: commonTags
}

resource nsg001 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-axistest001-eus2'
  location: location
  tags: commonTags
  properties: {
    securityRules: []
  }
}

resource nsg002 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-axistest002-eus2'
  location: location
  tags: commonTags
  properties: {
    securityRules: []
  }
}

// ============================================================
// VNET 001
// ============================================================

resource vnet001 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-sandbox-eus2-axistest-001'
  location: location
  tags: commonTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.99.0.0/16'
      ]
    }
  }
}

resource subnet001 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  name: 'sn-axistest001-eus2'
  parent: vnet001
  properties: {
    addressPrefix: '10.99.0.0/24'
    networkSecurityGroup: {
      id: nsg001.id
    }
  }
}

// ============================================================
// VNET 002
// ============================================================

resource vnet002 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-sandbox-eus2-axistest-002'
  location: location
  tags: commonTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.100.0.0/16'
      ]
    }
  }
}

resource subnet002 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  name: 'sn-axistest002-eus2'
  parent: vnet002
  properties: {
    addressPrefix: '10.100.0.0/24'
    networkSecurityGroup: {
      id: nsg002.id
    }
  }
}

// ============================================================
// VNET PEERING
//
// Peering must be configured in both directions.
// The explicit subnet dependencies help avoid concurrent VNet
// child-resource updates during initial deployment.
// ============================================================

resource peering001to002 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  name: 'peer-axistest001-to-axistest002'
  parent: vnet001
  properties: {
    remoteVirtualNetwork: {
      id: vnet002.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
  }
  dependsOn: [
    subnet001
    subnet002
  ]
}

resource peering002to001 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  name: 'peer-axistest002-to-axistest001'
  parent: vnet002
  properties: {
    remoteVirtualNetwork: {
      id: vnet001.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
  }
  dependsOn: [
    subnet001
    subnet002
  ]
}

// ============================================================
// NICS - AXISTEST001
//
// Each NIC:
//   - Is connected to subnet 001.
//   - Receives a dynamic private address.
//   - Is added to ASG 001.
//   - Does not receive a public IP.
// ============================================================

resource nic001 'Microsoft.Network/networkInterfaces@2024-05-01' = [
  for i in range(0, 3): {
    name: 'nic-vm-axisasg-test001-0${i + 1}'
    location: location
    tags: commonTags
    properties: {
      enableAcceleratedNetworking: false
      ipConfigurations: [
        {
          name: 'ipconfig1'
          properties: {
            primary: true
            privateIPAllocationMethod: 'Dynamic'
            subnet: {
              id: subnet001.id
            }
            applicationSecurityGroups: [
              {
                id: asg001.id
              }
            ]
          }
        }
      ]
    }
  }
]

// ============================================================
// NICS - AXISTEST002
//
// Each NIC:
//   - Is connected to subnet 002.
//   - Receives a dynamic private address.
//   - Is added to ASG 002.
//   - Does not receive a public IP.
// ============================================================

resource nic002 'Microsoft.Network/networkInterfaces@2024-05-01' = [
  for i in range(0, 3): {
    name: 'nic-vm-axisasg-test002-0${i + 1}'
    location: location
    tags: commonTags
    properties: {
      enableAcceleratedNetworking: false
      ipConfigurations: [
        {
          name: 'ipconfig1'
          properties: {
            primary: true
            privateIPAllocationMethod: 'Dynamic'
            subnet: {
              id: subnet002.id
            }
            applicationSecurityGroups: [
              {
                id: asg002.id
              }
            ]
          }
        }
      ]
    }
  }
]

// ============================================================
// VMS - AXISTEST001
//
// This loop creates:
//
//   vm-axisasg-test001-01
//   vm-axisasg-test001-02
//   vm-axisasg-test001-03
// ============================================================

resource vm001 'Microsoft.Compute/virtualMachines@2024-07-01' = [
  for i in range(0, 3): {
    name: 'vm-axisasg-test001-0${i + 1}'
    location: location
    tags: commonTags
    properties: {
      hardwareProfile: {
        vmSize: vmSize
      }
      securityProfile: {
        securityType: 'TrustedLaunch'
        uefiSettings: {
          secureBootEnabled: true
          vTpmEnabled: true
        }
      }
      osProfile: {
        computerName: 'axis001-0${i + 1}'
        adminUsername: adminUsername
        linuxConfiguration: {
          disablePasswordAuthentication: true
          provisionVMAgent: true
          patchSettings: {
            patchMode: 'ImageDefault'
            assessmentMode: 'ImageDefault'
          }
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
          offer: '0001-com-ubuntu-server-jammy'
          sku: '22_04-lts-gen2'
          version: 'latest'
        }
        osDisk: {
          name: 'osdisk-vm-axisasg-test001-0${i + 1}'
          createOption: 'FromImage'
          deleteOption: 'Delete'
          diskSizeGB: 30
          managedDisk: {
            storageAccountType: 'Standard_LRS'
          }
        }
      }
      networkProfile: {
        networkInterfaces: [
          {
            id: nic001[i].id
            properties: {
              primary: true
              deleteOption: 'Delete'
            }
          }
        ]
      }
      diagnosticsProfile: {
        bootDiagnostics: {
          enabled: true
        }
      }
    }
  }
]

// ============================================================
// VMS - AXISTEST002
//
// This loop creates:
//
//   vm-axisasg-test002-01
//   vm-axisasg-test002-02
//   vm-axisasg-test002-03
// ============================================================

resource vm002 'Microsoft.Compute/virtualMachines@2024-07-01' = [
  for i in range(0, 3): {
    name: 'vm-axisasg-test002-0${i + 1}'
    location: location
    tags: commonTags
    properties: {
      hardwareProfile: {
        vmSize: vmSize
      }
      securityProfile: {
        securityType: 'TrustedLaunch'
        uefiSettings: {
          secureBootEnabled: true
          vTpmEnabled: true
        }
      }
      osProfile: {
        computerName: 'axis002-0${i + 1}'
        adminUsername: adminUsername
        linuxConfiguration: {
          disablePasswordAuthentication: true
          provisionVMAgent: true
          patchSettings: {
            patchMode: 'ImageDefault'
            assessmentMode: 'ImageDefault'
          }
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
          offer: '0001-com-ubuntu-server-jammy'
          sku: '22_04-lts-gen2'
          version: 'latest'
        }
        osDisk: {
          name: 'osdisk-vm-axisasg-test002-0${i + 1}'
          createOption: 'FromImage'
          deleteOption: 'Delete'
          diskSizeGB: 30
          managedDisk: {
            storageAccountType: 'Standard_LRS'
          }
        }
      }
      networkProfile: {
        networkInterfaces: [
          {
            id: nic002[i].id
            properties: {
              primary: true
              deleteOption: 'Delete'
            }
          }
        ]
      }
      diagnosticsProfile: {
        bootDiagnostics: {
          enabled: true
        }
      }
    }
  }
]

// ============================================================
// AUTO-SHUTDOWN - AXISTEST001
// ============================================================

resource autoShutdown001 'Microsoft.DevTestLab/schedules@2018-09-15' = [
  for i in range(0, 3): {
    name: 'shutdown-computevm-${vm001[i].name}'
    location: location
    tags: commonTags
    properties: {
      status: 'Enabled'
      taskType: 'ComputeVmShutdownTask'
      dailyRecurrence: {
        time: shutdownTime
      }
      timeZoneId: shutdownTimeZone
      targetResourceId: vm001[i].id
      notificationSettings: {
        status: 'Disabled'
      }
    }
  }
]

// ============================================================
// AUTO-SHUTDOWN - AXISTEST002
// ============================================================

resource autoShutdown002 'Microsoft.DevTestLab/schedules@2018-09-15' = [
  for i in range(0, 3): {
    name: 'shutdown-computevm-${vm002[i].name}'
    location: location
    tags: commonTags
    properties: {
      status: 'Enabled'
      taskType: 'ComputeVmShutdownTask'
      dailyRecurrence: {
        time: shutdownTime
      }
      timeZoneId: shutdownTimeZone
      targetResourceId: vm002[i].id
      notificationSettings: {
        status: 'Disabled'
      }
    }
  }
]

// ============================================================
// OUTPUTS
// ============================================================

output vnet001Name string = vnet001.name
output subnet001Name string = subnet001.name
output nsg001Name string = nsg001.name
output asg001Name string = asg001.name

output vnet002Name string = vnet002.name
output subnet002Name string = subnet002.name
output nsg002Name string = nsg002.name
output asg002Name string = asg002.name

output vm001Names array = [
  for i in range(0, 3): vm001[i].name
]

output vm002Names array = [
  for i in range(0, 3): vm002[i].name
]

output vm001PrivateIPs array = [
  for i in range(0, 3): nic001[i].properties.ipConfigurations[0].properties.privateIPAddress
]

output vm002PrivateIPs array = [
  for i in range(0, 3): nic002[i].properties.ipConfigurations[0].properties.privateIPAddress
]

output autoShutdownConfiguration string = '${shutdownTime} ${shutdownTimeZone}'
