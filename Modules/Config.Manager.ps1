# ==========================================
# Config.Manager.ps1
# 配置管理模块 - 负责配置的加载、保存、导入和导出
# ==========================================

# 配置路径
$Script:DefaultConfigPath = Join-Path $env:USERPROFILE "Documents\WindowsOptimizerPlusConfig.json"
$Script:EncryptionKey = $null

# 全局配置对象
$Script:GlobalConfig = @{
    ConfigVersion = $Script:ConfigVersion
    LastModified = Get-Date
    Services = @{}
    Network = @{}
    Gaming = @{}
    System = @{}
    Privacy = @{}
    Updates = @{}
    Windows11 = @{}
    Custom = @{}
}

# 初始化加密密钥
function Initialize-EncryptionKey {
    [CmdletBinding()]
    param()
    
    $operation = Start-Operation -Name "初始化配置加密"
    
    try {
        # 使用机器特定信息生成密钥
        $computerInfo = Get-CimInstance -ClassName Win32_ComputerSystem
        $biosInfo = Get-CimInstance -ClassName Win32_BIOS
        
        $keyMaterial = "$($computerInfo.Manufacturer)$($computerInfo.Model)$($biosInfo.SerialNumber)"
        $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($keyMaterial)
        
        # 创建SHA256哈希作为加密密钥
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha256.ComputeHash($keyBytes)
        
        # 将哈希值转换为Base64字符串
        $Script:EncryptionKey = [Convert]::ToBase64String($hashBytes)
        
        Write-Log "配置加密密钥已初始化" -Level Debug -NoConsole
        Complete-Operation
        return $true
    }
    catch {
        Register-OperationError -ErrorRecord $_
        Complete-Operation -WithErrors
        return $false
    }
}

# 加密敏感数据
function Protect-SensitiveData {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Data
    )
    
    if (-not $Script:EncryptionKey) {
        Initialize-EncryptionKey
    }
    
    try {
        $dataBytes = [System.Text.Encoding]::UTF8.GetBytes($Data)
        $keyBytes = [System.Convert]::FromBase64String($Script:EncryptionKey)
        
        # 创建AES加密器
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $keyBytes[0..31] # 使用前32字节作为AES-256密钥
        $aes.GenerateIV() # 生成随机初始化向量
        
        # 加密数据
        $encryptor = $aes.CreateEncryptor()
        $encryptedBytes = $encryptor.TransformFinalBlock($dataBytes, 0, $dataBytes.Length)
        
        # 将IV和加密数据合并
        $resultBytes = $aes.IV + $encryptedBytes
        
        # 返回Base64编码的加密数据
        return [System.Convert]::ToBase64String($resultBytes)
    }
    catch {
        Write-Log "加密数据失败: $_" -Level Error
        return $null
    }
}

# 解密敏感数据
function Unprotect-SensitiveData {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$EncryptedData
    )
    
    if (-not $Script:EncryptionKey) {
        Initialize-EncryptionKey
    }
    
    try {
        $dataBytes = [System.Convert]::FromBase64String($EncryptedData)
        $keyBytes = [System.Convert]::FromBase64String($Script:EncryptionKey)
        
        # 创建AES解密器
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $keyBytes[0..31] # 使用前32字节作为AES-256密钥
        
        # 从加密数据中提取IV (AES块大小为16字节)
        $iv = $dataBytes[0..15]
        $aes.IV = $iv
        
        # 解密数据
        $decryptor = $aes.CreateDecryptor()
        $decryptedBytes = $decryptor.TransformFinalBlock($dataBytes, 16, $dataBytes.Length - 16)
        
        # 返回解密后的字符串
        return [System.Text.Encoding]::UTF8.GetString($decryptedBytes)
    }
    catch {
        Write-Log "解密数据失败: $_" -Level Error
        return $null
    }
}

# 初始化默认配置
function Initialize-Configuration {
    [CmdletBinding()]
    param()
    
    $operation = Start-Operation -Name "初始化默认配置"
    
    try {
        # 获取可优化的服务列表
        if (Get-Command -Name Get-OptimizableServices -ErrorAction SilentlyContinue) {
            $services = Get-OptimizableServices
            foreach ($service in $services) {
                $Script:GlobalConfig.Services[$service.Name] = $false
            }
            
            $advancedServices = Get-AdvancedOptimizableServices
            foreach ($service in $advancedServices) {
                $Script:GlobalConfig.Services[$service.Name] = $false
            }
        }
        else {
            Write-Log "服务优化模块未正确加载，无法初始化服务配置" -Level Warning
        }
        
        # 获取网络优化选项
        if (Get-Command -Name Get-NetworkOptimizations -ErrorAction SilentlyContinue) {
            $networkOpts = Get-NetworkOptimizations
            foreach ($opt in $networkOpts) {
                $Script:GlobalConfig.Network[$opt.Name] = $false
            }
        }
        else {
            Write-Log "网络优化模块未正确加载，无法初始化网络配置" -Level Warning
        }
        
        # 获取游戏优化选项
        if (Get-Command -Name Get-GamingOptimizations -ErrorAction SilentlyContinue) {
            $gamingOpts = Get-GamingOptimizations
            foreach ($opt in $gamingOpts) {
                $Script:GlobalConfig.Gaming[$opt.Name] = $false
            }
        }
        else {
            Write-Log "游戏优化模块未正确加载，无法初始化游戏配置" -Level Warning
        }
        
        # 获取系统优化选项
        if (Get-Command -Name Get-SystemOptimizations -ErrorAction SilentlyContinue) {
            $systemOpts = Get-SystemOptimizations
            foreach ($opt in $systemOpts) {
                $Script:GlobalConfig.System[$opt.Name] = $false
            }
        }
        else {
            Write-Log "系统优化模块未正确加载，无法初始化系统配置" -Level Warning
        }
        
        # 获取隐私选项
        if (Get-Command -Name Get-PrivacyOptions -ErrorAction SilentlyContinue) {
            $privacyOpts = Get-PrivacyOptions
            foreach ($opt in $privacyOpts) {
                $Script:GlobalConfig.Privacy[$opt.Name] = $false
            }
        }
        
        # 获取更新选项
        if (Get-Command -Name Get-UpdateOptions -ErrorAction SilentlyContinue) {
            $updateOpts = Get-UpdateOptions
            foreach ($opt in $updateOpts) {
                $Script:GlobalConfig.Updates[$opt.Name] = $false
            }
        }
        
        # Windows 11特定选项
        if ($Script:SystemInfo.IsWindows11 -and (Get-Command -Name Get-Windows11Options -ErrorAction SilentlyContinue)) {
            $win11Opts = Get-Windows11Options
            foreach ($opt in $win11Opts) {
                $Script:GlobalConfig.Windows11[$opt.Name] = $false
            }
        }
        
        $Script:GlobalConfig.LastModified = Get-Date
        
        # 保存初始配置
        Save-Configuration
        
        Write-Log "配置已初始化为默认值" -Level Success
        Complete-Operation
        return $true
    }
    catch {
        Register-OperationError -ErrorRecord $_
        Complete-Operation -WithErrors
        return $false
    }
}

# 保存配置
function Save-Configuration {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$Path = $Script:DefaultConfigPath
    )
    
    $operation = Start-Operation -Name "保存配置" -RollbackAction {
        # 如果保存失败但备份存在，则恢复备份
        $backupPath = "$Path.backup"
        if (Test-Path $backupPath) {
            Copy-Item -Path $backupPath -Destination $Path -Force
            Remove-Item -Path $backupPath -Force
        }
    }
    
    try {
        # 更新时间戳
        $Script:GlobalConfig.LastModified = Get-Date
        $Script:GlobalConfig.ConfigVersion = $Script:ConfigVersion
        
        # 创建备份
        if (Test-Path $Path) {
            Copy-Item -Path $Path -Destination "$Path.backup" -Force
        }
        
        # 转换配置为JSON并保存
        $jsonConfig = $Script:GlobalConfig | ConvertTo-Json -Depth 10
        
        # 创建目录（如果不存在）
        $directory = Split-Path -Path $Path -Parent
        if (-not (Test-Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }
        
        # 保存到文件
        $jsonConfig | Set-Content -Path $Path -Force -Encoding UTF8
        
        Write-Log "配置已保存到: $Path" -Level Success
        Complete-Operation
        
        # 如果保存成功，删除备份
        if (Test-Path "$Path.backup") {
            Remove-Item -Path "$Path.backup" -Force
        }
        
        return $true
    }
    catch {
        Register-OperationError -ErrorRecord $_
        Complete-Operation -WithErrors
        return $false
    }
}

# 加载配置
function Load-Configuration {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$Path = $Script:DefaultConfigPath
    )
    
    $operation = Start-Operation -Name "加载配置"
    
    if (-not (Test-Path $Path)) {
        Write-Log "配置文件不存在，将创建默认配置: $Path" -Level Warning
        Initialize-Configuration
        Complete-Operation
        return $true
    }
    
    try {
        # 读取配置文件
        $jsonConfig = Get-Content -Path $Path -Raw -Encoding UTF8
        $config = $jsonConfig | ConvertFrom-Json
        
        # 验证配置版本
        if (-not $config.ConfigVersion) {
            Write-Log "配置文件格式无效或不包含版本信息，将使用默认配置" -Level Warning
            Initialize-Configuration
            Complete-Operation
            return $false
        }
        
        # 配置版本兼容性检查
        if ([version]$config.ConfigVersion -lt [version]"1.0") {
            Write-Log "配置版本过旧 ($($config.ConfigVersion))，将升级到当前版本 ($Script:ConfigVersion)" -Level Warning
            # 这里可以添加配置迁移逻辑
            Initialize-Configuration
            Complete-Operation
            return $false
        }
        
        # 重置全局配置
        $Script:GlobalConfig = @{
            ConfigVersion = $Script:ConfigVersion
            LastModified = Get-Date
            Services = @{}
            Network = @{}
            Gaming = @{}
            System = @{}
            Privacy = @{}
            Updates = @{}
            Windows11 = @{}
            Custom = @{}
        }
        
        # 从JSON填充配置
        foreach ($category in @("Services", "Network", "Gaming", "System", "Privacy", "Updates", "Windows11", "Custom")) {
            $categoryObj = $config.PSObject.Properties[$category].Value
            if ($categoryObj) {
                foreach ($key in $categoryObj.PSObject.Properties.Name) {
                    $Script:GlobalConfig[$category][$key] = $categoryObj.$key
                }
            }
        }
        
        # 解析LastModified日期
        if ($config.LastModified) {
            try {
                $Script:GlobalConfig.LastModified = [DateTime]$config.LastModified
            }
            catch {
                $Script:GlobalConfig.LastModified = Get-Date
            }
        }
        
        Write-Log "配置已从 $Path 加载" -Level Success
        Complete-Operation
        return $true
    }
    catch {
        Register-OperationError -ErrorRecord $_
        Complete-Operation -WithErrors
        
        # 如果加载失败，初始化默认配置
        Write-Log "加载配置时出错，将使用默认配置" -Level Warning
        Initialize-Configuration
        return $false
    }
}

# 导入配置
function Import-Configuration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    $operation = Start-Operation -Name "导入配置" -RollbackAction {
        # 如果导入失败，恢复到加载配置之前的状态
        Load-Configuration
    }
    
    try {
        if (-not (Test-Path $Path)) {
            throw "配置文件不存在: $Path"
        }
        
        # 读取并验证导入文件
        $jsonConfig = Get-Content -Path $Path -Raw -Encoding UTF8
        $importedConfig = $jsonConfig | ConvertFrom-Json
        
        # 验证导入的配置
        if (-not $importedConfig.ConfigVersion) {
            throw "导入的配置文件格式无效或不包含版本信息"
        }
        
        # 版本兼容性检查
        if ([version]$importedConfig.ConfigVersion -gt [version]$Script:ConfigVersion) {
            Write-Log "导入的配置版本 ($($importedConfig.ConfigVersion)) 高于当前版本 ($Script:ConfigVersion)，可能出现兼容性问题" -Level Warning
        }
        
        # 备份当前配置
        $backupPath = Join-Path $Script:BackupsPath "Config_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
        Save-Configuration -Path $backupPath
        
        # 将导入的配置应用到全局配置
        $Script:GlobalConfig = @{
            ConfigVersion = $Script:ConfigVersion
            LastModified = Get-Date
            Services = @{}
            Network = @{}
            Gaming = @{}
            System = @{}
            Privacy = @{}
            Updates = @{}
            Windows11 = @{}
            Custom = @{}
        }
        
        # 从导入的配置填充全局配置
        foreach ($category in @("Services", "Network", "Gaming", "System", "Privacy", "Updates", "Windows11", "Custom")) {
            $categoryObj = $importedConfig.PSObject.Properties[$category].Value
            if ($categoryObj) {
                foreach ($key in $categoryObj.PSObject.Properties.Name) {
                    $Script:GlobalConfig[$category][$key] = $categoryObj.$key
                }
            }
        }
        
        # 保存导入的配置
        Save-Configuration
        
        Write-Log "已成功导入配置: $Path" -Level Success
        Write-Log "已创建配置备份: $backupPath" -Level Info
        Complete-Operation
        return $true
    }
    catch {
        Register-OperationError -ErrorRecord $_
        Complete-Operation -WithErrors
        return $false
    }
}

# 导出配置
function Export-Configuration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    $operation = Start-Operation -Name "导出配置"
    
    try {
        # 更新时间戳
        $Script:GlobalConfig.LastModified = Get-Date
        
        # 转换为JSON并保存
        $jsonConfig = $Script:GlobalConfig | ConvertTo-Json -Depth 10
        
        # 创建目录（如果不存在）
        $directory = Split-Path -Path $Path -Parent
        if (-not (Test-Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }
        
        # 保存到文件
        $jsonConfig | Set-Content -Path $Path -Force -Encoding UTF8
        
        Write-Log "配置已导出到: $Path" -Level Success
        Complete-Operation
        return $true
    }
    catch {
        Register-OperationError -ErrorRecord $_
        Complete-Operation -WithErrors
        return $false
    }
}

# 验证配置完整性
function Test-ConfigurationIntegrity {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$Path = $Script:DefaultConfigPath
    )
    
    $operation = Start-Operation -Name "验证配置完整性"
    
    try {
        if (-not (Test-Path $Path)) {
            Write-Log "配置文件不存在: $Path" -Level Warning
            Complete-Operation -WithErrors
            return $false
        }
        
        # 尝试读取文件
        $jsonConfig = Get-Content -Path $Path -Raw -Encoding UTF8
        $null = $jsonConfig | ConvertFrom-Json
        
        # 如果能够成功解析JSON，则认为文件完整
        Write-Log "配置文件完整性验证通过: $Path" -Level Success
        Complete-Operation
        return $true
    }
    catch {
        Register-OperationError -ErrorRecord $_
        Complete-Operation -WithErrors
        
        # 尝试从备份恢复
        $backupPath = "$Path.backup"
        if (Test-Path $backupPath) {
            try {
                Copy-Item -Path $backupPath -Destination $Path -Force
                Write-Log "已从备份恢复配置文件: $backupPath" -Level Success
                return $true
            }
            catch {
                Write-Log "无法从备份恢复配置: $_" -Level Error
            }
        }
        
        return $false
    }
}

# 获取配置项的值
function Get-ConfigValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Category,
        
        [Parameter(Mandatory = $true)]
        [string]$Key,
        
        [Parameter()]
        $DefaultValue = $false
    )
    
    if ($Script:GlobalConfig.ContainsKey($Category) -and $Script:GlobalConfig[$Category].ContainsKey($Key)) {
        return $Script:GlobalConfig[$Category][$Key]
    }
    
    return $DefaultValue
}

# 设置配置项的值
function Set-ConfigValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Category,
        
        [Parameter(Mandatory = $true)]
        [string]$Key,
        
        [Parameter(Mandatory = $true)]
        $Value
    )
    
    if (-not $Script:GlobalConfig.ContainsKey($Category)) {
        $Script:GlobalConfig[$Category] = @{}
    }
    
    $Script:GlobalConfig[$Category][$Key] = $Value
}

# 导出功能函数
Export-ModuleMember -Function Initialize-Configuration
Export-ModuleMember -Function Save-Configuration
Export-ModuleMember -Function Load-Configuration
Export-ModuleMember -Function Import-Configuration
Export-ModuleMember -Function Export-Configuration
Export-ModuleMember -Function Get-ConfigValue
Export-ModuleMember -Function Set-ConfigValue
Export-ModuleMember -Function Test-ConfigurationIntegrity 