#Requires -RunAsAdministrator

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ColorBg      = [System.Drawing.Color]::FromArgb(12,12,12)
$ColorPanelBg = [System.Drawing.Color]::FromArgb(20,20,20)
$ColorRed     = [System.Drawing.Color]::FromArgb(200,20,20)
$ColorRedDark = [System.Drawing.Color]::FromArgb(90,10,10)
$ColorText    = [System.Drawing.Color]::White
$ColorTextDim = [System.Drawing.Color]::FromArgb(180,180,180)

function Get-CodeHash {
    param([string]$Code)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Code))
    return ([System.BitConverter]::ToString($bytes) -replace "-","").ToLower()
}

$ValidCodeHashes = @{
    "E35DDA8C1FCAB84FC927B4C32357D8C2F5A30CE3221E5712658434978EE06488" = "Admin"
}

function Show-CodeGate {
    $gate = New-Object System.Windows.Forms.Form
    $gate.Text = "embofn7tweaks - Zugang"
    $gate.Size = New-Object System.Drawing.Size(380, 200)
    $gate.StartPosition = "CenterScreen"
    $gate.BackColor = $ColorBg
    $gate.ForeColor = $ColorText
    $gate.FormBorderStyle = "FixedDialog"
    $gate.MaximizeBox = $false

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "embofn7tweaks"
    $lbl.ForeColor = $ColorRed
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
    $lbl.AutoSize = $true
    $lbl.Location = New-Object System.Drawing.Point(20, 15)
    $gate.Controls.Add($lbl)

    $lbl2 = New-Object System.Windows.Forms.Label
    $lbl2.Text = "Zugangscode eingeben:"
    $lbl2.ForeColor = $ColorTextDim
    $lbl2.AutoSize = $true
    $lbl2.Location = New-Object System.Drawing.Point(20, 55)
    $gate.Controls.Add($lbl2)

    $codeBox = New-Object System.Windows.Forms.TextBox
    $codeBox.Location = New-Object System.Drawing.Point(20, 80)
    $codeBox.Size = New-Object System.Drawing.Size(320, 25)
    $codeBox.BackColor = $ColorPanelBg
    $codeBox.ForeColor = $ColorText
    $gate.Controls.Add($codeBox)

    $errLbl = New-Object System.Windows.Forms.Label
    $errLbl.ForeColor = $ColorRed
    $errLbl.AutoSize = $true
    $errLbl.Location = New-Object System.Drawing.Point(20, 110)
    $gate.Controls.Add($errLbl)

    $okBtn = New-Object System.Windows.Forms.Button
    $okBtn.Text = "Enter"
    $okBtn.BackColor = $ColorRed
    $okBtn.ForeColor = [System.Drawing.Color]::White
    $okBtn.Location = New-Object System.Drawing.Point(20, 135)
    $okBtn.Size = New-Object System.Drawing.Size(100, 30)
    $gate.Controls.Add($okBtn)

    $script:AuthorizedUser = $null
    $okBtn.Add_Click({
        $entered = $codeBox.Text.Trim()
        $enteredHash = Get-CodeHash $entered
        if ($ValidCodeHashes.ContainsKey($enteredHash)) {
            $script:AuthorizedUser = $ValidCodeHashes[$enteredHash]
            $gate.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $gate.Close()
        } else {
            $errLbl.Text = "Ungueltiger Code."
            $codeBox.Text = ""
        }
    })

    $result = $gate.ShowDialog()
    return ($result -eq [System.Windows.Forms.DialogResult]::OK)
}

if (-not (Show-CodeGate)) {
    [System.Windows.Forms.MessageBox]::Show("Kein gueltiger Code - Programm wird beendet.", "embofn7tweaks") | Out-Null
    exit
}

$AppName    = "embofn7tweaks"
$LogFolder  = "$env:LOCALAPPDATA\$AppName"
$BackupFile = Join-Path $LogFolder "backup.json"
$LogFile    = Join-Path $LogFolder ("{0}_{1}.log" -f $AppName, (Get-Date -Format "yyyy-MM-dd_HH-mm-ss"))

if (-not (Test-Path $LogFolder)) { New-Item -ItemType Directory -Path $LogFolder | Out-Null }

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message
    Add-Content -Path $LogFile -Value $line
    if ($OutputBox) {
        $OutputBox.AppendText("$line`r`n")
        $OutputBox.ScrollToCaret()
    }
}

function Get-Backup {
    if (Test-Path $BackupFile) {
        $obj = Get-Content $BackupFile -Raw | ConvertFrom-Json
        $table = @{}
        if ($obj) {
            $obj.PSObject.Properties | ForEach-Object {
                $entry = @{}
                $_.Value.PSObject.Properties | ForEach-Object { $entry[$_.Name] = $_.Value }
                $table[$_.Name] = $entry
            }
        }
        return $table
    }
    return @{}
}

function Save-Backup($table) {
    $table | ConvertTo-Json -Depth 5 | Set-Content -Path $BackupFile
}

function Set-RegValueTracked {
    param(
        [string]$TweakId,
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = "DWord"
    )
    $backup = Get-Backup
    if (-not $backup.ContainsKey($TweakId)) {
        $old = $null
        if (Test-Path $Path) {
            $prop = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
            if ($prop) { $old = $prop.$Name }
        }
        $backup[$TweakId] = @{ Path = $Path; Name = $Name; OldValue = $old; Existed = ($old -ne $null) }
        Save-Backup $backup
    }
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Restore-RegValueTracked {
    param([string]$TweakId)
    $backup = Get-Backup
    if ($backup.ContainsKey($TweakId)) {
        $entry = $backup[$TweakId]
        if ($entry.Existed) {
            New-ItemProperty -Path $entry.Path -Name $entry.Name -Value $entry.OldValue -Force | Out-Null
        } else {
            Remove-ItemProperty -Path $entry.Path -Name $entry.Name -ErrorAction SilentlyContinue
        }
        $backup.Remove($TweakId)
        Save-Backup $backup
    }
}

function New-SystemRestorePoint {
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "$AppName before tweaks" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Log "Restore point erstellt."
    } catch {
        Write-Log "Restore point konnte nicht erstellt werden: $($_.Exception.Message)"
    }
}

function Get-FortniteExePath {
    $launcherDat = "$env:ProgramData\Epic\UnrealEngineLauncher\LauncherInstalled.dat"
    if (Test-Path $launcherDat) {
        try {
            $data = Get-Content $launcherDat -Raw | ConvertFrom-Json
            $entry = $data.InstallationList | Where-Object { $_.AppName -match "Fortnite" } | Select-Object -First 1
            if ($entry) {
                $exe = Join-Path $entry.InstallLocation "FortniteGame\Binaries\Win64\FortniteClient-Win64-Shipping.exe"
                if (Test-Path $exe) { return $exe }
            }
        } catch {}
    }
    return $null
}

$Tweaks = @(

# ==============================================================================================
# embofn7tweaks - merged build by embofn7
#
# This build contains modified portions derived from unknowntweaks v0.0.67.
# Original project: https://github.com/unknownaimer/unknownutility
# Original project license: MIT. The original attribution/license is retained here.
# The WinForms UI, branding, access-code gate and integration layer are embofn7tweaks.
# ==============================================================================================
#region Get-UTForegroundState.ps1
function Get-UTForegroundState {
    <#
    .SYNOPSIS
        The running game, found by process so windowed and alt-tabbed games count, plus how its window is shown.
    #>
    $blacklist = @()
    try { $blacklist = @($sync.configs.games.ShellBlacklist) } catch { }
    $result = [pscustomobject]@{ Process = ''; Pid = 0; Mode = 'Desktop'; IsGame = $false; Title = ''; Quns = 0; Foreground = $false; Source = '' }
    $game = $null
    try { $game = Get-UTRunningGame } catch { }
    if ($game) {
        $result.Process = $game.Name; $result.Pid = [int]$game.Pid; $result.Title = $game.Title
        $result.IsGame = $true; $result.Source = $game.Source; $result.Mode = 'background'
    }
    if (-not ('UT.NativeV1.Win' -as [type])) { return $result }
    try {
        $f = [UT.NativeV1.Win]::GetForeground()
        $name = [string]$f.ProcessName
        $result.Quns = [int]$f.Quns
        $isShell = $f.IsShell -or [string]::IsNullOrEmpty($name) -or ($blacklist -contains $name)
        $mode = 'Desktop'
        if (-not $isShell) {
            if ($f.Quns -eq 3) { $mode = 'Fullscreen' }
            elseif ($f.CoversMonitor -and $f.Borderless) { $mode = 'Borderless' }
            elseif ($f.CoversMonitor) { $mode = 'Maximized' }
            else { $mode = 'Windowed' }
        }
        if ($game) {
            if ([int]$f.Pid -eq $result.Pid) { $result.Foreground = $true; $result.Mode = $mode }
        } else {
            $result.Process = $name; $result.Pid = [int]$f.Pid; $result.Mode = $mode
            if (-not $isShell -and $mode -in 'Fullscreen', 'Borderless') { $result.IsGame = $true; $result.Title = $name; $result.Foreground = $true; $result.Source = 'window' }
        }
    } catch { }
    return $result
}

function Get-UTNetInterfaceBytes {
    <#
    .SYNOPSIS
        Byte counters of every physical, connected adapter (no counters, no localisation, no instance-name mangling).
    #>
    $virtualRx = 'Virtual|VMware|VirtualBox|Hyper-V|vEthernet|WAN Miniport|Bluetooth|Npcap|WinPcap|TAP-|Wintun|WireGuard|Loopback|ISATAP|Teredo|Pseudo|Kernel Debug|Wi-Fi Direct|Miniport|Tunnel|Tailscale|ZeroTier|Radmin|Hamachi'
    $rows = @()
    foreach ($i in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($i.OperationalStatus -ne 'Up') { continue }
        if ([string]$i.NetworkInterfaceType -in 'Loopback', 'Tunnel', 'Ppp') { continue }
        if ($i.Description -match $virtualRx) { continue }
        try {
            $st = $i.GetIPStatistics()
            $rows += [pscustomobject]@{ Id = $i.Id; Name = $i.Name; Desc = $i.Description; Type = [string]$i.NetworkInterfaceType; SpeedBps = [int64]$i.Speed; Rx = [int64]$st.BytesReceived; Tx = [int64]$st.BytesSent }
        } catch { }
    }
    return $rows
}

function Get-UTNetworkLink {
    <#
    .SYNOPSIS
        The adapter carrying the default route, and whether it is Wi-Fi.
    #>
    $out = [pscustomobject]@{ Adapter = ''; Description = ''; LinkType = 'Unknown'; LinkSpeed = ''; IsWiFi = $false; Gateway = ''; InterfaceIndex = 0; SSID = ''; Signal = '' }
    try {
        # Windows picks the route with the lowest total metric (interface + route), not the lowest route
        # metric, so sorting on RouteMetric alone can pick a VPN or virtual adapter that is not really in use.
        $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
                 Where-Object { $_.NextHop -and $_.NextHop -ne '0.0.0.0' } |
                 Sort-Object @{ Expression = { [int]$_.InterfaceMetric + [int]$_.RouteMetric } } |
                 Select-Object -First 1
        if (-not $route) { return $out }
        $out.Gateway = [string]$route.NextHop
        $out.InterfaceIndex = [int]$route.ifIndex
        $nic = Get-NetAdapter -InterfaceIndex $route.ifIndex -ErrorAction SilentlyContinue
        if ($nic) {
            $out.Adapter = [string]$nic.Name
            $out.Description = [string]$nic.InterfaceDescription
            $out.LinkSpeed = [string]$nic.LinkSpeed
            if ($nic.PhysicalMediaType -eq 'Native 802.11' -or [int]$nic.NdisPhysicalMedium -eq 9) { $out.IsWiFi = $true; $out.LinkType = 'Wi-Fi' }
            elseif ($nic.PhysicalMediaType -eq 'Wireless WAN') { $out.LinkType = 'Cellular' }
            elseif ($nic.PhysicalMediaType -eq '802.3') { $out.LinkType = 'Ethernet' }
            elseif ($nic.Virtual) { $out.LinkType = 'Virtual (VPN?)' }
        }
        if ($out.IsWiFi) {
            $raw = (Invoke-UTNative -FilePath 'netsh.exe' -Arguments @('wlan', 'show', 'interfaces')).Lines
            $ssid = @($raw | Select-String '^\s*SSID\s*:\s*(.+)$' | Select-Object -First 1)
            $sig = @($raw | Select-String '^\s*Signal\s*:\s*(\d+)%' | Select-Object -First 1)
            if ($ssid.Count) { $out.SSID = $ssid[0].Matches[0].Groups[1].Value.Trim() }
            if ($sig.Count) { $out.Signal = $sig[0].Matches[0].Groups[1].Value + '%' }
        }
    } catch { }
    return $out
}

#endregion

#region Get-UTFortnite.ps1
function Get-UTFortnite {
    <#
    .SYNOPSIS
        Everything the Fortnite tab needs: install path, config file, the launcher's settings file, account id,
        the launcher's catalog triple for this game, running state.
    #>
    $fn = [pscustomobject]@{
        Installed = $false; InstallLocation = ''; Version = ''
        GameIni = (Join-Path $env:LOCALAPPDATA 'FortniteGame\Saved\Config\WindowsClient\GameUserSettings.ini')
        GameIniExists = $false
        LauncherIni = ''; LauncherIniExists = $false; LauncherExe = ''
        NamespaceId = ''; ItemId = ''; ArtifactId = ''; LauncherKeyPrefix = ''
        AccountId = ''; GameRunning = $false; LauncherRunning = $false
    }
    try {
        $dat = Join-Path $env:ProgramData 'Epic\UnrealEngineLauncher\LauncherInstalled.dat'
        if (Test-Path -LiteralPath $dat) {
            $list = (Get-Content -LiteralPath $dat -Raw | ConvertFrom-Json).InstallationList
            $entry = @($list | Where-Object { $_.AppName -eq 'Fortnite' -or $_.ArtifactId -eq 'Fortnite' }) | Select-Object -First 1
            if ($entry) {
                $fn.Installed = $true; $fn.InstallLocation = [string]$entry.InstallLocation; $fn.Version = [string]$entry.AppVersion
                $fn.NamespaceId = [string]$entry.NamespaceId; $fn.ItemId = [string]$entry.ItemId; $fn.ArtifactId = [string]$entry.ArtifactId
            }
        }
        # The manifest carries the same catalog triple under different names. It is the fallback both
        # when LauncherInstalled.dat is missing and when it is an older build without those fields.
        if (-not $fn.Installed -or -not $fn.ItemId) {
            $appData = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\WOW6432Node\Epic Games\EpicGamesLauncher' -ErrorAction SilentlyContinue).AppDataPath
            if (-not $appData) { $appData = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\' }
            $manifests = Join-Path $appData 'Manifests'
            if (Test-Path -LiteralPath $manifests) {
                foreach ($f in (Get-ChildItem -LiteralPath $manifests -Filter *.item -ErrorAction SilentlyContinue)) {
                    try { $m = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json } catch { continue }
                    if ($m.AppName -ne 'Fortnite') { continue }
                    if (-not $fn.Installed) { $fn.Installed = $true; $fn.InstallLocation = [string]$m.InstallLocation; $fn.Version = [string]$m.AppVersionString }
                    if (-not $fn.NamespaceId) { $fn.NamespaceId = [string]$m.CatalogNamespace }
                    if (-not $fn.ItemId)      { $fn.ItemId      = [string]$m.CatalogItemId }
                    if (-not $fn.ArtifactId)  { $fn.ArtifactId  = [string]$m.AppName }
                    break
                }
            }
        }
    } catch { }
    # The launcher keys every per-game setting by "namespace:catalogItemId:artifact", the same triple
    # its own com.epicgames.launcher:// URLs use. See Find-UTLaunchArgsKey.
    if ($fn.NamespaceId -and $fn.ItemId -and $fn.ArtifactId) {
        $fn.LauncherKeyPrefix = '{0}:{1}:{2}' -f $fn.NamespaceId, $fn.ItemId, $fn.ArtifactId
    }
    $fn.GameIniExists = (Test-Path -LiteralPath $fn.GameIni)
    $cfg = Join-Path $env:LOCALAPPDATA 'EpicGamesLauncher\Saved\Config'
    $candidates = @((Join-Path $cfg 'WindowsEditor\GameUserSettings.ini'), (Join-Path $cfg 'Windows\GameUserSettings.ini')) | Where-Object { Test-Path -LiteralPath $_ }
    if ($candidates) {
        $fn.LauncherIni = [string](@($candidates | Sort-Object { (Get-Item -LiteralPath $_).LastWriteTime } -Descending)[0])
        $fn.LauncherIniExists = $true
    } else {
        $fn.LauncherIni = Join-Path $cfg 'Windows\GameUserSettings.ini'
    }
    foreach ($exe in @("${env:ProgramFiles(x86)}\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe", "${env:ProgramFiles(x86)}\Epic Games\Launcher\Portal\Binaries\Win32\EpicGamesLauncher.exe")) {
        if (Test-Path -LiteralPath $exe) { $fn.LauncherExe = $exe; break }
    }
    try { $fn.AccountId = [string](Get-ItemProperty -LiteralPath 'HKCU:\Software\Epic Games\Unreal Engine\Identifiers' -Name AccountId -ErrorAction SilentlyContinue).AccountId } catch { }
    if (-not $fn.AccountId -and $fn.LauncherIniExists) {
        try {
            $ini = Read-UTIniFile -Path $fn.LauncherIni
            # _Settings holds the launch arguments, _General is the other account-scoped section; both carry the id.
            foreach ($s in $ini.Sections.Keys) { if ($s -match '^([0-9a-fA-F]{32})_(Settings|General)$') { $fn.AccountId = $Matches[1]; break } }
        } catch { }
    }
    $fn.GameRunning = [bool](Get-Process -Name @($sync.configs.fortnite.BlockingProcesses) -ErrorAction SilentlyContinue)
    $fn.LauncherRunning = [bool](Get-Process -Name @($sync.configs.fortnite.LauncherProcesses) -ErrorAction SilentlyContinue)
    return $fn
}

function Stop-UTEpicLauncher {
    <#
    .SYNOPSIS
        Closes the launcher so it cannot overwrite its settings file. Returns $true only when the main
        launcher window was actually running, so the caller knows whether to start it again afterwards.
    #>
    $names = @($sync.configs.fortnite.LauncherProcesses)
    # Only the main process means "the user had the launcher open"; the EOS helper can linger by itself.
    $wasOpen = [bool](Get-Process -Name 'EpicGamesLauncher' -ErrorAction SilentlyContinue)
    $running = Get-Process -Name $names -ErrorAction SilentlyContinue
    if (-not $running) { return $false }
    Write-UTLog 'Closing the Epic Games Launcher (it rewrites its settings file on exit)'
    $running | Stop-Process -Force -ErrorAction SilentlyContinue
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline -and (Get-Process -Name $names -ErrorAction SilentlyContinue)) { Start-Sleep -Milliseconds 300 }
    if (Get-Process -Name $names -ErrorAction SilentlyContinue) {
        throw 'The Epic Games Launcher is still running after 15 seconds. Close it yourself (tray icon, Exit) and try again, otherwise it would overwrite the change on exit.'
    }
    Start-Sleep -Milliseconds 800
    return $wasOpen
}

function Start-UTEpicLauncher {
    <#
    .SYNOPSIS
        Asks the shell to start the launcher so it runs as the signed-in user.
    .NOTES
        Starting it directly would hand it this tool's administrator token, and every game launched from
        it afterwards would inherit that too. explorer.exe runs unelevated, so it starts the launcher
        with normal rights.
    #>
    $fn = Get-UTFortnite
    if (-not $fn.LauncherExe) { Write-UTLog 'Epic Games Launcher executable not found; start it yourself' -Level Warn; return }
    try {
        Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $fn.LauncherExe + '"') -ErrorAction Stop
        Write-UTLog 'Epic Games Launcher restarted (with normal user rights, not as administrator)'
    } catch {
        Write-UTLog ('Could not restart the Epic Games Launcher: {0}. Start it yourself.' -f $_.Exception.Message) -Level Warn
    }
}

function Backup-UTFile {
    <#
    .SYNOPSIS
        Copies a file next to itself with a timestamp; the very first backup is also kept as *.unknowntweaks.original.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $orig = $Path + '.unknowntweaks.original'
    if (-not (Test-Path -LiteralPath $orig)) { Copy-Item -LiteralPath $Path -Destination $orig -Force }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Copy-Item -LiteralPath $Path -Destination ($Path + '.bak-' + $stamp) -Force
    Write-UTLog "Backup written: $Path.bak-$stamp"
    # Keep the newest few; this writes into the game's own config folder, not ours.
    $leaf = Split-Path -Path $Path -Leaf
    $dir = Split-Path -Path $Path -Parent
    $old = @(Get-ChildItem -LiteralPath $dir -Filter ($leaf + '.bak-*') -File -ErrorAction SilentlyContinue |
             Sort-Object Name -Descending | Select-Object -Skip 5)
    foreach ($f in $old) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
}

#endregion

#region Get-UTFortniteStatus.ps1
function Get-UTFortniteStatus {
    <#
    .SYNOPSIS
        Epic's public status page, through its documented API: every Fortnite component, open incidents
        with their latest update, and scheduled maintenance. Nothing is sent but the request.
    #>
    $lines = New-Object System.Collections.Generic.List[string]
    try {
        $s = Invoke-RestMethod -Uri 'https://status.epicgames.com/api/v2/summary.json' -TimeoutSec 15 -UseBasicParsing -ErrorAction Stop
        $groups = @{}
        foreach ($c in $s.components) { if ($c.group) { $groups[[string]$c.id] = [string]$c.name } }
        $lines.Add(('Epic status page: {0}   (updated {1})' -f $s.status.description, ([datetime]$s.page.updated_at).ToLocalTime().ToString('HH:mm')))
        $lines.Add('')
        foreach ($c in ($s.components | Where-Object { -not $_.group -and $groups.ContainsKey([string]$_.group_id) -and $groups[[string]$_.group_id] -match 'Fortnite' })) {
            $mark = '  '
            if ($c.status -ne 'operational') { $mark = '! ' }
            $lines.Add(('{0}{1,-44} {2}' -f $mark, ($groups[[string]$c.group_id] + ' / ' + $c.name), ($c.status -replace '_', ' ')))
        }
        $open = @($s.incidents)
        $lines.Add('')
        if ($open.Count -eq 0) { $lines.Add('no open incidents') }
        foreach ($i in $open) {
            $lines.Add(('INCIDENT  {0}   [{1}, {2}]' -f $i.name, $i.status, $i.impact))
            $u = @($i.incident_updates) | Select-Object -First 1
            if ($u) { $lines.Add(('  ' + (([string]$u.body) -replace '\s+', ' ').Trim())) }
        }
        foreach ($m in @($s.scheduled_maintenances)) {
            $lines.Add(('MAINTENANCE  {0}   {1} -> {2}' -f $m.name, ([datetime]$m.scheduled_for).ToLocalTime().ToString('ddd dd MMM HH:mm'), ([datetime]$m.scheduled_until).ToLocalTime().ToString('HH:mm')))
        }
        $lines.Add('')
        $lines.Add('known gameplay bugs: https://www.epicgames.com/help/en-US/c-Category_Fortnite/c-Fortnite_Gameplay/fortnite-live-issues-and-bugs-a000084853')
    } catch {
        $lines.Add('status.epicgames.com could not be reached: ' + $_.Exception.Message)
    }
    $sync.fnLiveStatus = ($lines -join "`r`n")
    return $sync.fnLiveStatus
}

#endregion

#region Get-UTGameReady.ps1
function Get-UTNeverKill {
    <#
    .SYNOPSIS
        Processes Game Ready mode never offers, whatever config/gameready.json says.
    .DESCRIPTION
        Everything Windows needs to stay on its feet, the security stack, audio, the GPU vendors'
        display containers, every anti-cheat service and helper, and this tool's own host. The list
        is code, not data, for the same reason the debloat blocklist is: a careless config edit must
        not be able to take the desktop down.
    #>
    return @(
        'System', 'Idle', 'Registry', 'Secure System', 'smss', 'csrss', 'wininit', 'winlogon', 'services', 'lsass', 'lsaiso',
        'svchost', 'dwm', 'fontdrvhost', 'sihost', 'taskhostw', 'RuntimeBroker', 'ctfmon', 'explorer', 'ShellExperienceHost',
        'StartMenuExperienceHost', 'SearchHost', 'SearchApp', 'SearchUI', 'TextInputHost', 'ApplicationFrameHost', 'LogonUI',
        'LockApp', 'SystemSettings', 'Taskmgr', 'conhost', 'OpenConsole', 'cmd', 'powershell', 'powershell_ise', 'pwsh',
        'WindowsTerminal', 'WmiPrvSE', 'dllhost', 'unsecapp', 'dasHost', 'MemCompression', 'audiodg', 'spoolsv', 'WUDFHost',
        'SecurityHealthService', 'SecurityHealthSystray', 'MsMpEng', 'NisSrv', 'SgrmBroker', 'smartscreen',
        'NVDisplay.Container', 'nvcontainer', 'atieclxx', 'atiesrxx', 'AMDRSServ', 'AMDRSSrcExt', 'igfxEM', 'igfxHK', 'igfxTray',
        'igfxCUIService', 'IntelGraphicsSoftware', 'RtkAudUService64', 'RAVBg64', 'NahimicSvc', 'NahimicNotifSys',
        'vgc', 'vgtray', 'vgm', 'EasyAntiCheat', 'EasyAntiCheat_EOS', 'EasyAntiCheat_Setup', 'BEService', 'BEDaisy',
        'EAAntiCheatService', 'FACEITService', 'faceit', 'PnkBstrA', 'PnkBstrB', 'xigncode', 'GameGuard', 'nProtect',
        'GameBar', 'GameBarFTServer', 'gamingservices', 'gamingservicesnet', 'XboxPcAppFT'
    )
}

function Get-UTGameReadyCandidates {
    <#
    .SYNOPSIS
        Processes in this user's session that could be closed before a game, with what each one is.
    .DESCRIPTION
        Only the interactive session is considered, so services and anything owned by SYSTEM never
        appear. The never-kill list, the chosen game, its launcher family and this tool's own tree are
        removed. What remains is labelled from config/gameready.json where a name is known, or by its
        window title, and tagged Keep when gamers usually want it running (voice chat, recording,
        peripheral software), so it is listed but not ticked.
    #>
    param([string]$GameProcess = '')
    $cfg = $sync.configs.gameready
    $never = @{}
    foreach ($n in (Get-UTNeverKill)) { $never[$n] = $true }
    $keep = @{}
    foreach ($p in $cfg.Keep.PSObject.Properties) { $keep[$p.Name] = [string]$p.Value }
    $background = @{}
    foreach ($p in $cfg.Background.PSObject.Properties) { $background[$p.Name] = [string]$p.Value }
    $gameLaunchers = @{}
    if ($GameProcess) {
        $fnCfg = $sync.configs.fortnite; $vCfg = $sync.configs.valorant
        if ($GameProcess -eq $fnCfg.GameProcess) { foreach ($n in @($fnCfg.LauncherProcesses) + @($fnCfg.BlockingProcesses)) { $gameLaunchers[$n] = $true } }
        if ($GameProcess -eq $vCfg.GameProcess) { foreach ($n in @($vCfg.ClientProcesses) + @($vCfg.BlockingProcesses)) { $gameLaunchers[$n] = $true } }
    }
    $me = [System.Diagnostics.Process]::GetCurrentProcess()
    $session = $me.SessionId
    $mine = @{ $me.Id = $true }
    try { $parent = (Get-CimInstance Win32_Process -Filter "ProcessId=$($me.Id)" -ErrorAction Stop).ParentProcessId; if ($parent) { $mine[[int]$parent] = $true } } catch { }
    $byName = @{}
    foreach ($p in [System.Diagnostics.Process]::GetProcesses()) {
        try {
            if ($p.SessionId -ne $session) { continue }
            $name = $p.ProcessName
            if ($never.ContainsKey($name) -or $mine.ContainsKey($p.Id) -or $gameLaunchers.ContainsKey($name)) { continue }
            if ($GameProcess -and $name -eq $GameProcess) { continue }
            if (-not $byName.ContainsKey($name)) {
                $label = $name
                if ($background.ContainsKey($name)) { $label = $background[$name] }
                elseif ($keep.ContainsKey($name)) { $label = $keep[$name] }
                $byName[$name] = [pscustomobject]@{
                    Name = $name; Pids = @(); Count = 0; Label = $label; Title = ''; HasWindow = $false; MemoryMB = 0
                    Keep = $keep.ContainsKey($name); Reason = $(if ($keep.ContainsKey($name)) { $keep[$name] } else { '' })
                }
            }
            $row = $byName[$name]
            $row.Pids += $p.Id; $row.Count++; $row.MemoryMB += [math]::Round($p.WorkingSet64 / 1MB)
            if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $row.HasWindow = $true; if (-not $row.Title) { try { $row.Title = $p.MainWindowTitle } catch { } } }
        } catch { }
        finally { $p.Dispose() }
    }
    foreach ($row in $byName.Values) { if ($row.Label -eq $row.Name -and $row.Title) { $row.Label = $row.Title } }
    return @($byName.Values | Sort-Object @{ Expression = 'Keep' }, @{ Expression = 'HasWindow'; Descending = $true }, @{ Expression = 'MemoryMB'; Descending = $true })
}

function Stop-UTGameReadyProcesses {
    <#
    .SYNOPSIS
        Closes every process with one of the given names: a polite window close first, then a kill for
        anything still alive after the grace period.
    .DESCRIPTION
        Names are re-checked against the never-kill list and this tool's own session before anything is
        signalled, so a stale list from the UI cannot reach a protected process. Nothing here is
        reversible; the log says exactly what was closed so it can be started again.
    #>
    param([Parameter(Mandatory = $true)][string[]]$Names, [int]$GraceSeconds = 3)
    $never = @{}
    foreach ($n in (Get-UTNeverKill)) { $never[$n] = $true }
    $me = [System.Diagnostics.Process]::GetCurrentProcess()
    $targets = @()
    foreach ($name in $Names) {
        if ($never.ContainsKey($name)) { Write-UTLog ("{0} is protected and was not touched" -f $name) -Level Warn; continue }
        $targets += @(Get-Process -Name $name -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $me.SessionId -and $_.Id -ne $me.Id })
    }
    if ($targets.Count -eq 0) { Write-UTLog 'Nothing to close'; return 0 }
    $freed = 0
    foreach ($p in $targets) {
        $freed += $p.WorkingSet64
        try { if ($p.MainWindowHandle -ne [IntPtr]::Zero) { [void]$p.CloseMainWindow() } } catch { }
    }
    $deadline = (Get-Date).AddSeconds($GraceSeconds)
    while ((Get-Date) -lt $deadline -and @($targets | Where-Object { -not $_.HasExited }).Count -gt 0) { Start-Sleep -Milliseconds 200 }
    $closed = 0
    foreach ($p in $targets) {
        try {
            if (-not $p.HasExited) { $p.Kill(); $p.WaitForExit(2000) }
            Write-UTLog ("closed {0} (pid {1})" -f $p.ProcessName, $p.Id)
            $closed++
        } catch { Write-UTLog ("{0} (pid {1}) could not be closed: {2}" -f $p.ProcessName, $p.Id, $_.Exception.Message) -Level Warn }
    }
    Write-UTLog ("Game Ready: {0} process(es) closed, about {1:N0} MB of working set released" -f $closed, ($freed / 1MB)) -Level Ok
    return $closed
}

#endregion

#region Get-UTPowerCfgIndex.ps1
function Get-UTPowerCfgIndex {
    <#
    .SYNOPSIS
        Reads the current AC index of a power setting from the active scheme, language-neutral.
    .NOTES
        powercfg output is localised, but the two "Current ... Power Setting Index" lines are always the last two
        lines that end in an 8-digit hex value: AC first, then DC. Returns $null if the setting is unavailable.
        Values are read as UInt32 because a setting can legitimately be 0xFFFFFFFF (e.g. "never"), which
        overflows Int32.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$SubGroup,
        [Parameter(Mandatory = $true)][string]$Setting,
        [switch]$DC
    )
    try {
        $r = Invoke-UTNative -FilePath 'powercfg.exe' -Arguments @('/q', 'SCHEME_CURRENT', $SubGroup, $Setting)
        if ($r.ExitCode -ne 0) { return $null }
        $hex = @($r.Lines | ForEach-Object { if ($_ -match ':\s*(0x[0-9A-Fa-f]{8})\s*$') { $Matches[1] } })
        if ($hex.Count -lt 2) { return $null }
        $pick = $hex[$hex.Count - 2]
        if ($DC) { $pick = $hex[$hex.Count - 1] }
        return [uint32]([Convert]::ToUInt32($pick.Substring(2), 16))
    } catch { return $null }
}

function Set-UTPowerCfgIndex {
    <#
    .SYNOPSIS
        Writes the AC index of one power setting in the active scheme, activates it, and logs it.
    .NOTES
        The tweak scripts used to pipe powercfg straight to Out-Null, so a refusal looked exactly like
        a success: nothing in the log either way, and the tweak still counted as applied. Throwing
        here lets Invoke-UTTweakApply report the failure and keep the snapshot.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$SubGroup,
        [Parameter(Mandatory = $true)][string]$Setting,
        [Parameter(Mandatory = $true)][uint32]$Index,
        [Parameter(Mandatory = $true)][string]$What
    )
    $r = Invoke-UTNative -FilePath 'powercfg.exe' -Arguments @('/SETACVALUEINDEX', 'SCHEME_CURRENT', $SubGroup, $Setting, ([string]$Index))
    if ($r.ExitCode -ne 0) { throw ("powercfg could not set {0} (exit {1}): {2}" -f $What, $r.ExitCode, $r.Output.Trim()) }
    # The scheme has to be re-activated for a changed index to take effect.
    $a = Invoke-UTNative -FilePath 'powercfg.exe' -Arguments @('/setactive', 'SCHEME_CURRENT')
    if ($a.ExitCode -ne 0) { throw ("powercfg could not re-activate the current scheme (exit {0}): {1}" -f $a.ExitCode, $a.Output.Trim()) }
    Write-UTLog ("{0}: AC power index set to {1}" -f $What, $Index)
}

function Get-UTBitLockerStatus {
    <#
    .SYNOPSIS
        Protection state of the system drive: 'On', 'Off', or 'Unknown' when it cannot be determined.
    .NOTES
        Never returns 'Off' on an error. A bcdedit change on an encrypted drive whose protection was not
        suspended can demand the 48-digit recovery key at the next boot, so "I could not tell" must be
        treated as "assume encrypted".
    #>
    try {
        $vol = Get-CimInstance -Namespace 'root\CIMV2\Security\MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume -ErrorAction Stop |
            Where-Object { $_.DriveLetter -eq $env:SystemDrive } | Select-Object -First 1
        if (-not $vol) { return 'Off' }
        $r = Invoke-CimMethod -InputObject $vol -MethodName GetProtectionStatus -ErrorAction Stop
        if ([int]$r.ReturnValue -ne 0) { return 'Unknown' }
        if ([int]$r.ProtectionStatus -eq 0) { return 'Off' }
        return 'On'
    } catch {
        # The WMI provider is absent on some Home installs that genuinely have no encryption, but it also
        # fails on a locked-down machine that does. Unknown is the safe answer.
        return 'Unknown'
    }
}

function Suspend-UTBitLocker {
    <#
    .SYNOPSIS
        Suspends BitLocker protection for exactly one reboot. Returns $true only when it is safe to
        change boot configuration afterwards.
    #>
    $status = Get-UTBitLockerStatus
    if ($status -eq 'Off') { return $true }
    if ($status -eq 'Unknown') {
        Write-UTLog 'Could not determine whether this drive is encrypted, so it is treated as encrypted. Suspending protection for one reboot before touching boot settings.' -Level Warn
    } else {
        Write-UTLog 'BitLocker / Device Encryption is ON. Suspending protection for one reboot so this boot setting change cannot trigger a recovery key prompt.' -Level Warn
    }
    $r = Invoke-UTNative -FilePath 'manage-bde.exe' -Arguments @('-protectors', '-disable', $env:SystemDrive, '-RebootCount', '1')
    $code = $r.ExitCode
    $text = $r.Output.Trim()
    if ($code -eq 0) {
        Write-UTLog 'BitLocker protection suspended for one reboot; it resumes automatically.' -Level Ok
        return $true
    }
    if ($status -eq 'Unknown') {
        # manage-bde also fails on a machine with no encryption at all; only then is it safe to continue.
        if ($text -match 'ERROR_NOT_ENCRYPTED|not have BitLocker|is not protected|0x80310008') {
            Write-UTLog 'The drive is not encrypted, continuing.'
            return $true
        }
    }
    Write-UTLog ("BitLocker protection could NOT be suspended (exit {0}): {1}. The boot setting was left unchanged to avoid a recovery-key lockout." -f $code, $text) -Level Error
    return $false
}

function Invoke-UTBcdEdit {
    <#
    .SYNOPSIS
        Runs a bcdedit change, but only after BitLocker protection is known to be safe to change.
    #>
    param([Parameter(Mandatory = $true)][string]$Arguments)
    if (-not (Suspend-UTBitLocker)) {
        throw 'Refused to change boot configuration: BitLocker protection could not be suspended, and changing it now could lock you out at the next boot.'
    }
    $argv = @($Arguments -split '\s+' | Where-Object { $_ })
    $r = Invoke-UTNative -FilePath 'bcdedit.exe' -Arguments $argv
    $code = $r.ExitCode
    $text = $r.Output.Trim()
    if ($code -ne 0) { throw "bcdedit $Arguments failed (exit $code): $text" }
    Write-UTLog "bcdedit $Arguments -> $text"
}

#endregion

#region Get-UTRunningGame.ps1
function Get-UTRunningGame {
    <#
    .SYNOPSIS
        The game process running right now, whether or not it owns the foreground window.
    .DESCRIPTION
        Two passes over the process list: a name match against config/games.json first, then any
        windowed process whose executable lives under a game library folder (Steam, Epic, Riot, ...),
        titled by the folder it sits in. Launchers and helpers are excluded by name. A known name wins
        over a path match, and the largest working set wins among several candidates.
    #>
    $cfg = $sync.configs.games
    $known = @{}
    foreach ($p in $cfg.KnownGames.PSObject.Properties) { $known[$p.Name] = [string]$p.Value }
    $launchers = @{}
    foreach ($n in @($cfg.LauncherProcesses)) { $launchers[$n] = $true }
    $libraries = @($cfg.LibraryFolders)
    $best = $null
    foreach ($p in [System.Diagnostics.Process]::GetProcesses()) {
        try {
            $name = $p.ProcessName
            if ($launchers.ContainsKey($name)) { continue }
            $hit = $null
            if ($known.ContainsKey($name)) {
                $hit = [pscustomobject]@{ Name = $name; Pid = $p.Id; Title = $known[$name]; Source = 'known'; WorkingSet = [int64]$p.WorkingSet64; Rank = 2 }
            } elseif ($p.WorkingSet64 -gt 200MB -and $p.MainWindowHandle -ne [IntPtr]::Zero) {
                $path = $p.MainModule.FileName.Replace('\', '/')
                foreach ($lib in $libraries) {
                    $i = $path.IndexOf($lib, [StringComparison]::OrdinalIgnoreCase)
                    if ($i -lt 0) { continue }
                    $rest = $path.Substring($i + $lib.Length)
                    $title = ($rest -split '/')[0]
                    if (-not $title) { $title = $name }
                    $hit = [pscustomobject]@{ Name = $name; Pid = $p.Id; Title = $title; Source = 'library'; WorkingSet = [int64]$p.WorkingSet64; Rank = 1 }
                    break
                }
            }
            if ($hit -and (-not $best -or $hit.Rank -gt $best.Rank -or ($hit.Rank -eq $best.Rank -and $hit.WorkingSet -gt $best.WorkingSet))) { $best = $hit }
        } catch { }
        finally { $p.Dispose() }
    }
    return $best
}

#endregion

#region Get-UTStartupItems.ps1
function Get-UTStartupApprovedPath {
    <#
    .SYNOPSIS
        The StartupApproved key that holds the enable/disable flag for one startup source.
    .NOTES
        StartupApproved is what Task Manager's Startup tab and the Settings app write. Disabling
        through it leaves the Run value or the shortcut exactly where it is, so an entry can be put
        back byte for byte, and Task Manager agrees with us about the state. Deleting Run values,
        the way most debloat scripts do, is not reversible and hides the entry from the user.
    #>
    param([Parameter(Mandatory = $true)][ValidateSet('HKLMRun', 'HKLMRun32', 'HKCURun', 'UserFolder', 'CommonFolder')][string]$Source)
    switch ($Source) {
        'HKLMRun'      { return 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' }
        'HKLMRun32'    { return 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32' }
        'HKCURun'      { return 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' }
        'UserFolder'   { return 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' }
        'CommonFolder' { return 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' }
    }
}

function Test-UTStartupApprovedEnabled {
    <#
    .SYNOPSIS
        Reads one 12-byte StartupApproved blob. $true when the entry runs at logon.
    .NOTES
        Byte 0 carries the flag: 0x02 and 0x06 mean enabled, 0x03 means disabled, i.e. bit 0 set is
        "disabled". Bytes 4..11 hold the FILETIME of when it was disabled and are zero while enabled.
        Read off a live Windows 10 19045 machine and matched against the format documented at
        windowsir.blogspot.com. No value at all means nobody ever disabled it, so: enabled.
    #>
    param($Blob)
    $bytes = @($Blob)
    if ($bytes.Count -lt 1 -or $null -eq $bytes[0]) { return $true }
    return ((([int]$bytes[0]) -band 1) -eq 0)
}

function New-UTStartupApprovedBlob {
    <#
    .SYNOPSIS
        Builds the 12-byte StartupApproved value for an enabled or disabled entry.
    .NOTES
        Byte 0 is the flag, bytes 1..3 are padding, bytes 4..11 are the FILETIME of the moment the
        entry was disabled - what Task Manager shows as "Disabled on ...". An enabled entry carries
        a zero timestamp, which is exactly what Windows writes when you tick something back on.
    #>
    param([Parameter(Mandatory = $true)][bool]$Enabled)
    $bytes = New-Object 'byte[]' 12
    if ($Enabled) {
        $bytes[0] = 2
    } else {
        $bytes[0] = 3
        $stamp = [BitConverter]::GetBytes((Get-Date).ToFileTime())
        [Array]::Copy($stamp, 0, $bytes, 4, 8)
    }
    return $bytes
}

function Get-UTLogonTasks {
    <#
    .SYNOPSIS
        Third-party scheduled tasks that fire at logon: the vendor updaters and tray helpers.
    .NOTES
        Tasks under \Microsoft\ are skipped on purpose. The documented telemetry ones are handled by
        name in config/tweaks.json, and the rest of Windows' own logon tasks are not ours to guess at.
    #>
    $out = @()
    try {
        foreach ($task in @(Get-ScheduledTask -ErrorAction SilentlyContinue)) {
            if ($task.TaskPath -like '\Microsoft\*') { continue }
            $logon = @($task.Triggers | Where-Object { $_ -and $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' })
            if ($logon.Count -eq 0) { continue }
            $full = $task.TaskPath.TrimEnd('\') + '\' + $task.TaskName
            $cmd = (@($task.Actions | ForEach-Object { [string]$_.Execute }) -join ' ').Trim()
            # A task in the library root has TaskPath '\', which trims to nothing; say where it is.
            $folder = $task.TaskPath.TrimEnd('\')
            if ([string]::IsNullOrEmpty($folder)) { $folder = 'Task Scheduler root' }
            $out += [pscustomobject]@{
                Id      = 'Task|' + $full
                Name    = [string]$task.TaskName
                Command = $cmd
                Source  = 'Task'
                Where   = 'scheduled task at logon'
                Scope   = $folder
                Enabled = ([string]$task.State -ne 'Disabled')
            }
        }
    } catch { }
    return $out
}

function Get-UTStartupItems {
    <#
    .SYNOPSIS
        Everything that runs at logon from the Run keys, the Startup folders and third-party logon
        scheduled tasks, with its current enabled state. The read-only half of the STARTUP tab.
    .NOTES
        Deliberately narrower than Sysinternals Autoruns: no drivers, no services, no COM hijacks,
        no Winlogon, AppInit or image-hijack entries. Those are where Autoruns lets an unsure user
        make a machine unbootable, and none of them are what "too much starts with Windows" means.
    #>
    $items = @()
    $runKeys = @(
        @{ Source = 'HKLMRun';   Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';             Scope = 'all users' },
        @{ Source = 'HKLMRun32'; Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Scope = 'all users (32-bit)' },
        @{ Source = 'HKCURun';   Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';             Scope = 'this account' }
    )
    foreach ($k in $runKeys) {
        if (-not (Test-Path -LiteralPath $k.Path)) { continue }
        $approvedPath = Get-UTStartupApprovedPath -Source $k.Source
        $approved = $null
        if (Test-Path -LiteralPath $approvedPath) { $approved = Get-ItemProperty -LiteralPath $approvedPath -ErrorAction SilentlyContinue }
        $props = Get-ItemProperty -LiteralPath $k.Path -ErrorAction SilentlyContinue
        foreach ($v in @($props.PSObject.Properties)) {
            if ($v.Name -like 'PS*') { continue }
            $blobValue = $null
            if ($approved -and $approved.PSObject.Properties[$v.Name]) { $blobValue = $approved.PSObject.Properties[$v.Name].Value }
            $items += [pscustomobject]@{
                Id      = $k.Source + '|' + $v.Name
                Name    = [string]$v.Name
                Command = [string]$v.Value
                Source  = $k.Source
                Where   = 'registry Run'
                Scope   = $k.Scope
                Enabled = (Test-UTStartupApprovedEnabled -Blob $blobValue)
            }
        }
    }
    $folders = @(
        @{ Source = 'UserFolder';   Path = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup');     Scope = 'this account' },
        @{ Source = 'CommonFolder'; Path = (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup'); Scope = 'all users' }
    )
    foreach ($f in $folders) {
        if (-not (Test-Path -LiteralPath $f.Path)) { continue }
        $approvedPath = Get-UTStartupApprovedPath -Source $f.Source
        $approved = $null
        if (Test-Path -LiteralPath $approvedPath) { $approved = Get-ItemProperty -LiteralPath $approvedPath -ErrorAction SilentlyContinue }
        foreach ($file in @(Get-ChildItem -LiteralPath $f.Path -File -ErrorAction SilentlyContinue)) {
            if ($file.Name -eq 'desktop.ini') { continue }
            $blobValue = $null
            if ($approved -and $approved.PSObject.Properties[$file.Name]) { $blobValue = $approved.PSObject.Properties[$file.Name].Value }
            $items += [pscustomobject]@{
                Id      = $f.Source + '|' + $file.Name
                Name    = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                Command = $file.FullName
                Source  = $f.Source
                Where   = 'Startup folder'
                Scope   = $f.Scope
                Enabled = (Test-UTStartupApprovedEnabled -Blob $blobValue)
            }
        }
    }
    foreach ($t in @(Get-UTLogonTasks)) { $items += $t }
    return @($items | Sort-Object Name)
}

function Set-UTStartupItem {
    <#
    .SYNOPSIS
        Enables or disables one startup entry, the same way Task Manager does.
    .OUTPUTS
        $true when the entry is now in the requested state.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][bool]$Enabled
    )
    $parts = $Id -split '\|', 2
    if ($parts.Count -ne 2) { Write-UTLog "Malformed startup id $Id" -Level Error; return $false }
    $source = $parts[0]
    $name = $parts[1]
    if ($source -eq 'Task') {
        try {
            $leaf = Split-Path -Path $name -Leaf
            $path = Split-Path -Path $name -Parent
            if ([string]::IsNullOrEmpty($path)) { $path = '\' }
            if (-not $path.StartsWith('\')) { $path = '\' + $path }
            if (-not $path.EndsWith('\')) { $path = $path + '\' }
            $task = Get-ScheduledTask -TaskPath $path -TaskName $leaf -ErrorAction Stop
            if ($Enabled) { $task | Enable-ScheduledTask -ErrorAction Stop | Out-Null }
            else { $task | Disable-ScheduledTask -ErrorAction Stop | Out-Null }
            Write-UTLog ("Logon task {0} -> {1}" -f $leaf, $(if ($Enabled) { 'enabled' } else { 'disabled' }))
            return $true
        } catch {
            Write-UTLog ("Logon task {0} could not be changed: {1}" -f $name, $_.Exception.Message) -Level Error
            return $false
        }
    }
    $approvedPath = Get-UTStartupApprovedPath -Source $source
    $bytes = New-UTStartupApprovedBlob -Enabled $Enabled
    $csv = (@($bytes | ForEach-Object { '{0:X2}' -f $_ }) -join ',')
    if (-not (Set-UTRegistry -Path $approvedPath -Name $name -Type Binary -Value $csv)) { return $false }
    Write-UTLog ("Startup entry {0} -> {1}" -f $name, $(if ($Enabled) { 'enabled' } else { 'disabled' }))
    return $true
}

function Set-UTStartupItems {
    <#
    .SYNOPSIS
        Bulk enable/disable from the STARTUP tab. Runs inside a worker runspace.
    #>
    param([Parameter(Mandatory = $true)][string[]]$Ids, [switch]$Enable)
    $want = [bool]$Enable
    $ok = 0
    $failed = 0
    foreach ($id in $Ids) {
        if (Set-UTStartupItem -Id $id -Enabled $want) { $ok++ } else { $failed++ }
    }
    $verb = 'disabled'
    if ($want) { $verb = 'enabled' }
    $msg = 'Startup: {0} {1}, {2} failed' -f $ok, $verb, $failed
    if ($failed -gt 0) { Write-UTLog $msg -Level Warn } else { Write-UTLog $msg -Level Ok }
    if (-not $want -and $ok -gt 0) {
        Write-UTLog 'Nothing was deleted. Every entry is still in the registry or the Startup folder, flagged disabled exactly the way Task Manager flags it, so you can turn any of it back on here or in Task Manager.'
    }
    $sync.status = 'ready'
}

#endregion

#region Get-UTSystemInfo.ps1
function Get-UTGpuMemoryBytes {
    <#
    .SYNOPSIS
        64-bit VRAM size from the display class registry (Win32_VideoController.AdapterRAM overflows at 4 GB).
    #>
    param([string]$DriverDesc)
    try {
        $class = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        foreach ($sub in (Get-ChildItem -LiteralPath $class -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty -LiteralPath $sub.PSPath -ErrorAction SilentlyContinue
            if ($p.DriverDesc -eq $DriverDesc -and $p.'HardwareInformation.qwMemorySize') {
                return [int64]$p.'HardwareInformation.qwMemorySize'
            }
        }
    } catch { }
    return $null
}

function Get-UTSystemInfo {
    <#
    .SYNOPSIS
        One-shot hardware / OS facts used by the UI and by tweak guards (laptop, build, GPU vendor, VBS, BitLocker).
    #>
    $info = @{}
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $ver = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
        $info.OSName = [string]$os.Caption
        $info.Build = [int]$os.BuildNumber
        $info.UBR = [int]$ver.UBR
        $info.DisplayVersion = [string]$ver.DisplayVersion
        if (-not $info.DisplayVersion) { $info.DisplayVersion = [string]$ver.ReleaseId }
        $info.Edition = [string]$ver.EditionID
        $info.Is11 = ($info.Build -ge 22000)
        $info.RamGB = [math]::Round(([double]$cs.TotalPhysicalMemory) / 1GB, 1)
        $info.ComputerName = [string]$cs.Name
        $info.ConsoleUser = [string]$cs.UserName
        $info.RunningAs = "$env:USERDOMAIN\$env:USERNAME"
        # Win32_ComputerSystem.UserName is DOMAIN\user, but for a Microsoft account the local profile name
        # is a truncated form, so only the account part is comparable and only when both are known.
        $consoleAccount = ($info.ConsoleUser -split '\\')[-1]
        $info.DifferentUser = ($consoleAccount -and $env:USERNAME -and ($consoleAccount -ne $env:USERNAME))
        $laptop = ([int]$cs.PCSystemType -eq 2)
        try {
            $chassis = @((Get-CimInstance Win32_SystemEnclosure -ErrorAction Stop).ChassisTypes)
            foreach ($c in $chassis) { if ([int]$c -in 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32) { $laptop = $true } }
        } catch { }
        try { if (Get-CimInstance Win32_Battery -ErrorAction Stop) { $laptop = $true } } catch { }
        $info.IsLaptop = $laptop
    } catch {
        $info.OSName = 'Windows'; $info.Build = 0; $info.IsLaptop = $false
    }
    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $info.CPU = ([string]$cpu.Name).Trim()
        $info.Cores = [int]$cpu.NumberOfCores
        $info.Threads = [int]$cpu.NumberOfLogicalProcessors
    } catch { $info.CPU = 'unknown CPU' }
    $gpus = @()
    try {
        foreach ($g in (Get-CimInstance Win32_VideoController -ErrorAction Stop)) {
            if (-not $g.Name) { continue }
            $vendor = 'Other'
            if ($g.Name -match 'NVIDIA|GeForce|RTX|GTX') { $vendor = 'NVIDIA' }
            elseif ($g.Name -match 'AMD|Radeon') { $vendor = 'AMD' }
            elseif ($g.Name -match 'Intel') { $vendor = 'Intel' }
            $vram = Get-UTGpuMemoryBytes -DriverDesc $g.Name
            if (-not $vram) { $vram = [int64]$g.AdapterRAM }
            $gpus += [pscustomobject]@{ Name = $g.Name; Vendor = $vendor; VramGB = [math]::Round($vram / 1GB, 1); Driver = [string]$g.DriverVersion }
        }
    } catch { }
    $info.GPUs = $gpus
    $primary = $gpus | Sort-Object VramGB -Descending | Select-Object -First 1
    if ($primary) { $info.GPU = $primary.Name; $info.GPUVendor = $primary.Vendor; $info.VramGB = $primary.VramGB } else { $info.GPU = 'unknown GPU'; $info.GPUVendor = 'Other'; $info.VramGB = 0 }
    try {
        $sysDisk = Get-Partition -DriveLetter ($env:SystemDrive.TrimEnd(':')) -ErrorAction Stop | Get-Disk -ErrorAction Stop
        $phys = Get-PhysicalDisk -ErrorAction Stop | Where-Object { $_.DeviceId -eq $sysDisk.Number } | Select-Object -First 1
        $info.DiskType = [string]$phys.MediaType
        $info.DiskBus = [string]$phys.BusType
    } catch { $info.DiskType = 'unknown'; $info.DiskBus = '' }
    try {
        $vol = Get-Volume -DriveLetter ($env:SystemDrive.TrimEnd(':')) -ErrorAction Stop
        $info.DiskFreeGB = [math]::Round($vol.SizeRemaining / 1GB, 1)
        $info.DiskSizeGB = [math]::Round($vol.Size / 1GB, 1)
    } catch { }
    try {
        $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop
        $info.VBSStatus = [int]$dg.VirtualizationBasedSecurityStatus
        $info.HVCIRunning = (@($dg.SecurityServicesRunning) -contains 2)
        $info.CredentialGuardRunning = (@($dg.SecurityServicesRunning) -contains 1)
    } catch { $info.VBSStatus = -1; $info.HVCIRunning = $false; $info.CredentialGuardRunning = $false }
    try { $info.SecureBoot = [bool](Confirm-SecureBootUEFI -ErrorAction Stop) } catch { $info.SecureBoot = $false }
    $info.BitLocker = Get-UTBitLockerStatus
    try {
        $plan = (Invoke-UTNative -FilePath 'powercfg.exe' -Arguments @('/getactivescheme')).Output
        if ($plan -match '\(([^)]+)\)') { $info.PowerPlan = $Matches[1] } else { $info.PowerPlan = $plan.Trim() }
    } catch { $info.PowerPlan = '' }
    try {
        $hags = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode -ErrorAction SilentlyContinue).HwSchMode
        $info.HAGS = ($hags -eq 2)
    } catch { $info.HAGS = $false }
    return [pscustomobject]$info
}

#endregion

#region Get-UTValorant.ps1
function Get-UTValorant {
    <#
    .SYNOPSIS
        Install path, Riot client, the active player's two settings files, Vanguard and running state.
    .DESCRIPTION
        The Riot client records every product it manages in %ProgramData%\Riot Games\RiotClientInstalls.json;
        the VALORANT entry is the key of associated_client that contains "VALORANT". Per-player settings
        live under %LOCALAPPDATA%\VALORANT\Saved\Config\<player>\ and the most recently written player
        folder is the one that last played on this machine.
    #>
    $cfg = $sync.configs.valorant
    $v = [pscustomobject]@{
        Installed = $false; InstallLocation = ''; GameExe = ''; ClientExe = ''
        PlayerId = ''; GameIni = ''; RiotIni = ''; GameIniExists = $false; RiotIniExists = $false
        VanguardInstalled = $false; VanguardRunning = $false
        GameRunning = $false; ClientRunning = $false
    }
    try {
        $installs = Join-Path $env:ProgramData 'Riot Games\RiotClientInstalls.json'
        if (Test-Path -LiteralPath $installs) {
            $j = Get-Content -LiteralPath $installs -Raw | ConvertFrom-Json
            foreach ($p in $j.associated_client.PSObject.Properties) {
                if ($p.Name -notmatch 'VALORANT') { continue }
                $v.InstallLocation = ($p.Name -replace '/', '\').TrimEnd('\')
                $v.ClientExe = ([string]$p.Value) -replace '/', '\'
                break
            }
            if (-not $v.ClientExe -and $j.rc_live) { $v.ClientExe = ([string]$j.rc_live) -replace '/', '\' }
        }
        if ($v.InstallLocation) {
            $v.GameExe = Join-Path $v.InstallLocation 'ShooterGame\Binaries\Win64\VALORANT-Win64-Shipping.exe'
            $v.Installed = Test-Path -LiteralPath $v.GameExe
        }
    } catch { }
    try {
        $root = Join-Path $env:LOCALAPPDATA 'VALORANT\Saved\Config'
        $player = Get-ChildItem -LiteralPath $root -Directory -ErrorAction Stop |
                  Where-Object { $_.Name -match '^[0-9a-f-]{36,}' } |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($player) {
            $v.PlayerId = $player.Name
            $v.GameIni = Join-Path $player.FullName 'WindowsClient\GameUserSettings.ini'
            $v.RiotIni = Join-Path $player.FullName 'Windows\RiotUserSettings.ini'
            $v.GameIniExists = Test-Path -LiteralPath $v.GameIni
            $v.RiotIniExists = Test-Path -LiteralPath $v.RiotIni
        }
    } catch { }
    $vg = Get-Service -Name vgc -ErrorAction SilentlyContinue
    if ($vg) { $v.VanguardInstalled = $true; $v.VanguardRunning = ($vg.Status -eq 'Running') }
    $v.GameRunning = [bool](Get-Process -Name @($cfg.BlockingProcesses) -ErrorAction SilentlyContinue)
    $v.ClientRunning = [bool](Get-Process -Name @($cfg.ClientProcesses) -ErrorAction SilentlyContinue)
    return $v
}

function Start-UTValorant {
    $v = Get-UTValorant
    if (-not $v.ClientExe -or -not (Test-Path -LiteralPath $v.ClientExe)) { throw 'The Riot client was not found on this PC' }
    Start-Process -FilePath $v.ClientExe -ArgumentList $sync.configs.valorant.LaunchArguments | Out-Null
    Write-UTLog 'VALORANT launch requested through the Riot client'
}

#endregion

#region Initialize-UTNative.ps1
function Initialize-UTNative {
    <#
    .SYNOPSIS
        Compiles the small C# helper set once per process (types are AppDomain-wide, so worker runspaces see them).
    .DESCRIPTION
        UT.NativeV1.PdhQuery : PDH query with PdhAddEnglishCounterW so counter paths work on non-English Windows.
        UT.NativeV1.Sys      : GetSystemTimes / GlobalMemoryStatusEx (CPU time and RAM without counters).
        UT.NativeV1.Win      : foreground window + fullscreen classification.
        UT.NativeV1.Dwm      : dark title bar.
        C# 5 only (the PowerShell 5.1 compiler does not know newer syntax).
    #>
    if ('UT.NativeV1.PdhQuery' -as [type]) { return $true }
    $src = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace UT.NativeV1 {

  public class PdhSample { public string Instance; public double Value; public uint Status; }

  public static class Pdh {
    public const uint PDH_FMT_DOUBLE = 0x00000200, PDH_FMT_NOCAP100 = 0x00008000;
    public const uint PDH_MORE_DATA = 0x800007D2;
    public const uint PDH_CSTATUS_VALID_DATA = 0, PDH_CSTATUS_NEW_DATA = 1;

    [StructLayout(LayoutKind.Explicit, Size = 16)]
    public struct PDH_FMT_COUNTERVALUE {
      [FieldOffset(0)] public uint CStatus;
      [FieldOffset(8)] public double doubleValue;
    }

    [DllImport("pdh.dll", CharSet = CharSet.Unicode)] public static extern uint PdhOpenQueryW(string szDataSource, IntPtr dwUserData, out IntPtr phQuery);
    [DllImport("pdh.dll", CharSet = CharSet.Unicode)] public static extern uint PdhAddEnglishCounterW(IntPtr hQuery, string szFullCounterPath, IntPtr dwUserData, out IntPtr phCounter);
    [DllImport("pdh.dll")] public static extern uint PdhCollectQueryData(IntPtr hQuery);
    [DllImport("pdh.dll")] public static extern uint PdhGetFormattedCounterValue(IntPtr hCounter, uint dwFormat, IntPtr lpdwType, out PDH_FMT_COUNTERVALUE pValue);
    [DllImport("pdh.dll", CharSet = CharSet.Unicode)] public static extern uint PdhGetFormattedCounterArrayW(IntPtr hCounter, uint dwFormat, ref uint lpdwBufferSize, out uint lpdwItemCount, IntPtr ItemBuffer);
    [DllImport("pdh.dll")] public static extern uint PdhCloseQuery(IntPtr hQuery);
  }

  public class PdhQuery : IDisposable {
    IntPtr _q = IntPtr.Zero;
    readonly Dictionary<string, IntPtr> _counters = new Dictionary<string, IntPtr>(StringComparer.OrdinalIgnoreCase);
    public PdhQuery() {
      uint rc = Pdh.PdhOpenQueryW(null, IntPtr.Zero, out _q);
      if (rc != 0) throw new InvalidOperationException("PdhOpenQuery failed: 0x" + rc.ToString("X8"));
    }
    public bool AddEnglish(string key, string englishPath) {
      IntPtr h; uint rc = Pdh.PdhAddEnglishCounterW(_q, englishPath, IntPtr.Zero, out h);
      if (rc != 0) return false;
      _counters[key] = h; return true;
    }
    public bool Has(string key) { return _counters.ContainsKey(key); }
    public uint Collect() { return Pdh.PdhCollectQueryData(_q); }
    public double GetValue(string key, bool noCap100) {
      IntPtr h; if (!_counters.TryGetValue(key, out h)) return double.NaN;
      Pdh.PDH_FMT_COUNTERVALUE v;
      uint fmt = Pdh.PDH_FMT_DOUBLE | (noCap100 ? Pdh.PDH_FMT_NOCAP100 : 0u);
      uint rc = Pdh.PdhGetFormattedCounterValue(h, fmt, IntPtr.Zero, out v);
      if (rc != 0) return double.NaN;
      if (v.CStatus != Pdh.PDH_CSTATUS_VALID_DATA && v.CStatus != Pdh.PDH_CSTATUS_NEW_DATA) return double.NaN;
      return v.doubleValue;
    }
    public List<PdhSample> GetArray(string key, bool noCap100) {
      List<PdhSample> list = new List<PdhSample>();
      IntPtr h; if (!_counters.TryGetValue(key, out h)) return list;
      uint fmt = Pdh.PDH_FMT_DOUBLE | (noCap100 ? Pdh.PDH_FMT_NOCAP100 : 0u);
      uint size = 0, count = 0;
      uint rc = Pdh.PdhGetFormattedCounterArrayW(h, fmt, ref size, out count, IntPtr.Zero);
      if (rc != Pdh.PDH_MORE_DATA || size == 0) return list;
      IntPtr buf = Marshal.AllocHGlobal((int)size);
      try {
        rc = Pdh.PdhGetFormattedCounterArrayW(h, fmt, ref size, out count, buf);
        if (rc != 0) return list;
        const int itemSize = 24;
        for (int i = 0; i < count; i++) {
          IntPtr item = new IntPtr(buf.ToInt64() + (long)i * itemSize);
          IntPtr namePtr = Marshal.ReadIntPtr(item, 0);
          uint status = (uint)Marshal.ReadInt32(item, 8);
          double val = BitConverter.Int64BitsToDouble(Marshal.ReadInt64(item, 16));
          PdhSample s = new PdhSample();
          s.Instance = namePtr == IntPtr.Zero ? "" : Marshal.PtrToStringUni(namePtr);
          s.Status = status;
          s.Value = (status == Pdh.PDH_CSTATUS_VALID_DATA || status == Pdh.PDH_CSTATUS_NEW_DATA) ? val : double.NaN;
          list.Add(s);
        }
      } finally { Marshal.FreeHGlobal(buf); }
      return list;
    }
    public void Dispose() { if (_q != IntPtr.Zero) { Pdh.PdhCloseQuery(_q); _q = IntPtr.Zero; } }
  }

  public static class Sys {
    [StructLayout(LayoutKind.Sequential)] public struct FILETIME { public uint Low; public uint High; }
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetSystemTimes(out FILETIME idle, out FILETIME kernel, out FILETIME user);
    [StructLayout(LayoutKind.Sequential)]
    public class MEMORYSTATUSEX {
      public uint dwLength = 64; public uint dwMemoryLoad;
      public ulong ullTotalPhys, ullAvailPhys, ullTotalPageFile, ullAvailPageFile, ullTotalVirtual, ullAvailVirtual, ullAvailExtendedVirtual;
    }
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool GlobalMemoryStatusEx([In, Out] MEMORYSTATUSEX lpBuffer);
    static ulong ToU64(FILETIME ft) { return ((ulong)ft.High << 32) | ft.Low; }
    public class CpuTimes { public ulong Idle, Kernel, User; public bool Ok; }
    public static CpuTimes GetCpuTimes() {
      FILETIME i, k, u; CpuTimes t = new CpuTimes();
      t.Ok = GetSystemTimes(out i, out k, out u);
      if (t.Ok) { t.Idle = ToU64(i); t.Kernel = ToU64(k); t.User = ToU64(u); }
      return t;
    }
    public class MemInfo { public ulong TotalPhys, AvailPhys; public uint Load; public bool Ok; }
    public static MemInfo GetMem() {
      MEMORYSTATUSEX m = new MEMORYSTATUSEX(); MemInfo r = new MemInfo();
      r.Ok = GlobalMemoryStatusEx(m);
      if (r.Ok) { r.TotalPhys = m.ullTotalPhys; r.AvailPhys = m.ullAvailPhys; r.Load = m.dwMemoryLoad; }
      return r;
    }
  }

  public static class Win {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }
    public delegate bool EnumChildProc(IntPtr hwnd, IntPtr lParam);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern IntPtr GetShellWindow();
    [DllImport("user32.dll")] static extern IntPtr GetDesktopWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetMonitorInfoW(IntPtr hMon, ref MONITORINFO mi);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassNameW(IntPtr hWnd, StringBuilder sb, int max);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr hWndParent, EnumChildProc cb, IntPtr lParam);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")] static extern int GetWindowLong32(IntPtr hWnd, int nIndex);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out RECT pv, int cb);
    [DllImport("shell32.dll")] static extern int SHQueryUserNotificationState(out int state);
    const int GWL_STYLE = -16, DWMWA_EXTENDED_FRAME_BOUNDS = 9;
    const long WS_CAPTION = 0x00C00000L;
    const uint MONITOR_DEFAULTTONEAREST = 2;
    static long GetWindowLongPtr(IntPtr hWnd, int nIndex) {
      return IntPtr.Size == 8 ? GetWindowLongPtr64(hWnd, nIndex).ToInt64() : (long)GetWindowLong32(hWnd, nIndex);
    }
    public class FgInfo {
      public IntPtr Hwnd; public uint Pid; public string ProcessName = ""; public string ClassName = "";
      public bool CoversMonitor; public bool Borderless; public int Quns; public bool IsShell; public bool HostedUwp;
    }
    public static FgInfo GetForeground() {
      FgInfo f = new FgInfo();
      f.Hwnd = GetForegroundWindow();
      int q; f.Quns = (SHQueryUserNotificationState(out q) == 0) ? q : 0;
      if (f.Hwnd == IntPtr.Zero) return f;
      f.IsShell = (f.Hwnd == GetShellWindow() || f.Hwnd == GetDesktopWindow());
      uint pid; GetWindowThreadProcessId(f.Hwnd, out pid); f.Pid = pid;
      StringBuilder sb = new StringBuilder(256); GetClassNameW(f.Hwnd, sb, 256); f.ClassName = sb.ToString();
      try { f.ProcessName = System.Diagnostics.Process.GetProcessById((int)pid).ProcessName; } catch { }
      if (string.Equals(f.ProcessName, "ApplicationFrameHost", StringComparison.OrdinalIgnoreCase)) {
        uint childPid = 0;
        EnumChildWindows(f.Hwnd, delegate(IntPtr h, IntPtr l) {
          StringBuilder cs = new StringBuilder(256); GetClassNameW(h, cs, 256);
          if (cs.ToString() == "Windows.UI.Core.CoreWindow") { uint p; GetWindowThreadProcessId(h, out p); if (p != pid) { childPid = p; return false; } }
          return true;
        }, IntPtr.Zero);
        if (childPid != 0) { f.Pid = childPid; f.HostedUwp = true; try { f.ProcessName = System.Diagnostics.Process.GetProcessById((int)childPid).ProcessName; } catch { } }
      }
      RECT r;
      if (DwmGetWindowAttribute(f.Hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, out r, Marshal.SizeOf(typeof(RECT))) != 0) GetWindowRect(f.Hwnd, out r);
      IntPtr mon = MonitorFromWindow(f.Hwnd, MONITOR_DEFAULTTONEAREST);
      MONITORINFO mi = new MONITORINFO(); mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
      if (mon != IntPtr.Zero && GetMonitorInfoW(mon, ref mi)) {
        const int tol = 2;
        f.CoversMonitor = r.Left <= mi.rcMonitor.Left + tol && r.Top <= mi.rcMonitor.Top + tol &&
                          r.Right >= mi.rcMonitor.Right - tol && r.Bottom >= mi.rcMonitor.Bottom - tol;
      }
      long style = GetWindowLongPtr(f.Hwnd, GWL_STYLE);
      f.Borderless = (style & WS_CAPTION) == 0;
      return f;
    }
  }

  public static class Dwm {
    [DllImport("dwmapi.dll", PreserveSig = true)] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
    [DllImport("Shcore.dll")] public static extern int SetProcessDpiAwareness(int value);
  }

  public static class Display {
    public class Mode { public int Width; public int Height; public int Hz; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct DEVMODE {
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
      public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra; public int dmFields;
      public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
      public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
      public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
      public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
    }
    [StructLayout(LayoutKind.Sequential)] public struct LUID { public uint LowPart; public int HighPart; }
    [StructLayout(LayoutKind.Sequential)] public struct RATIONAL { public uint Numerator, Denominator; }
    [StructLayout(LayoutKind.Sequential)] public struct PATH_SOURCE_INFO { public LUID adapterId; public uint id, modeInfoIdx, statusFlags; }
    [StructLayout(LayoutKind.Sequential)] public struct PATH_TARGET_INFO { public LUID adapterId; public uint id, modeInfoIdx, outputTechnology, rotation, scaling; public RATIONAL refreshRate; public uint scanLineOrdering; public int targetAvailable; public uint statusFlags; }
    [StructLayout(LayoutKind.Sequential)] public struct PATH_INFO { public PATH_SOURCE_INFO sourceInfo; public PATH_TARGET_INFO targetInfo; public uint flags; }
    [StructLayout(LayoutKind.Sequential)] public struct REGION2D { public uint cx, cy; }
    [StructLayout(LayoutKind.Sequential)] public struct VIDEO_SIGNAL_INFO { public ulong pixelRate; public RATIONAL hSyncFreq, vSyncFreq; public REGION2D activeSize, totalSize; public uint videoStandard, scanLineOrdering; }
    [StructLayout(LayoutKind.Sequential)] public struct SOURCE_MODE { public uint width, height, pixelFormat; public int x, y; }
    [StructLayout(LayoutKind.Explicit, Size = 48)] public struct MODE_UNION { [FieldOffset(0)] public VIDEO_SIGNAL_INFO targetVideoSignalInfo; [FieldOffset(0)] public SOURCE_MODE sourceMode; }
    [StructLayout(LayoutKind.Sequential)] public struct MODE_INFO { public uint infoType, id; public LUID adapterId; public MODE_UNION u; }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplaySettingsW(string dev, int mode, ref DEVMODE dm);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int ChangeDisplaySettingsExW(string dev, ref DEVMODE dm, IntPtr hwnd, uint flags, IntPtr lparam);
    [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPaths, out uint numModes);
    [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint numPaths, [Out] PATH_INFO[] paths, ref uint numModes, [Out] MODE_INFO[] modes, IntPtr topology);
    [DllImport("user32.dll")] static extern int SetDisplayConfig(uint numPaths, PATH_INFO[] paths, uint numModes, MODE_INFO[] modes, uint flags);
    const int DM_PELSWIDTH = 0x80000, DM_PELSHEIGHT = 0x100000, DM_DISPLAYFREQUENCY = 0x400000;
    const uint CDS_UPDATEREGISTRY = 1, QDC_ONLY_ACTIVE_PATHS = 2;
    const uint SDC_USE_SUPPLIED_DISPLAY_CONFIG = 0x20, SDC_APPLY = 0x80, SDC_SAVE_TO_DATABASE = 0x200, SDC_ALLOW_CHANGES = 0x400;
    static DEVMODE Blank() { DEVMODE d = new DEVMODE(); d.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE)); return d; }
    public static Mode GetCurrent() {
      DEVMODE d = Blank(); Mode m = new Mode();
      if (EnumDisplaySettingsW(null, -1, ref d)) { m.Width = d.dmPelsWidth; m.Height = d.dmPelsHeight; m.Hz = d.dmDisplayFrequency; }
      return m;
    }
    public static List<Mode> EnumModes() {
      List<Mode> list = new List<Mode>(); HashSet<string> seen = new HashSet<string>();
      DEVMODE d = Blank();
      for (int i = 0; EnumDisplaySettingsW(null, i, ref d); i++) {
        if (d.dmBitsPerPel != 32) continue;
        string k = d.dmPelsWidth + "x" + d.dmPelsHeight + "@" + d.dmDisplayFrequency;
        if (!seen.Add(k)) continue;
        Mode m = new Mode(); m.Width = d.dmPelsWidth; m.Height = d.dmPelsHeight; m.Hz = d.dmDisplayFrequency; list.Add(m);
      }
      return list;
    }
    public static int SetMode(int width, int height, int hz, bool persist) {
      DEVMODE d = Blank();
      d.dmPelsWidth = width; d.dmPelsHeight = height; d.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT;
      if (hz > 0) { d.dmDisplayFrequency = hz; d.dmFields |= DM_DISPLAYFREQUENCY; }
      return ChangeDisplaySettingsExW(null, ref d, IntPtr.Zero, persist ? CDS_UPDATEREGISTRY : 0, IntPtr.Zero);
    }
    static int Query(out PATH_INFO[] paths, out MODE_INFO[] modes, out uint np, out uint nm) {
      paths = null; modes = null; np = 0; nm = 0;
      int rc = GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out np, out nm);
      if (rc != 0) return rc;
      paths = new PATH_INFO[np]; modes = new MODE_INFO[nm];
      return QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref np, paths, ref nm, modes, IntPtr.Zero);
    }
    static int Primary(PATH_INFO[] paths, MODE_INFO[] modes, uint np) {
      for (int i = 0; i < np; i++) {
        uint idx = paths[i].sourceInfo.modeInfoIdx;
        if (idx < modes.Length && modes[idx].u.sourceMode.x == 0 && modes[idx].u.sourceMode.y == 0) return i;
      }
      return np > 0 ? 0 : -1;
    }
    public static uint GetScaling() {
      PATH_INFO[] paths; MODE_INFO[] modes; uint np, nm;
      if (Query(out paths, out modes, out np, out nm) != 0) return 0;
      int p = Primary(paths, modes, np);
      return p < 0 ? 0 : paths[p].targetInfo.scaling;
    }
    public static int SetScaling(uint scaling) {
      PATH_INFO[] paths; MODE_INFO[] modes; uint np, nm;
      int rc = Query(out paths, out modes, out np, out nm);
      if (rc != 0) return rc;
      int p = Primary(paths, modes, np);
      if (p < 0) return -1;
      paths[p].targetInfo.scaling = scaling;
      return SetDisplayConfig(np, paths, nm, modes, SDC_APPLY | SDC_USE_SUPPLIED_DISPLAY_CONFIG | SDC_SAVE_TO_DATABASE | SDC_ALLOW_CHANGES);
    }
    public static string StructSizes() { return Marshal.SizeOf(typeof(PATH_INFO)) + "," + Marshal.SizeOf(typeof(MODE_INFO)); }
  }

  public static class NvApi {
    [StructLayout(LayoutKind.Sequential, Pack = 8)] public struct TIMINGEXT { public uint flag; public ushort rr; public uint rrx1k, aspect; public ushort rep; public uint status; [MarshalAs(UnmanagedType.ByValArray, SizeConst = 40)] public byte[] name; }
    [StructLayout(LayoutKind.Sequential, Pack = 8)] public struct TIMING { public ushort HVisible, HBorder, HFrontPorch, HSyncWidth, HTotal; public byte HSyncPol; public ushort VVisible, VBorder, VFrontPorch, VSyncWidth, VTotal; public byte VSyncPol; public ushort interlaced; public uint pclk; public TIMINGEXT etc; }
    [StructLayout(LayoutKind.Sequential, Pack = 8)] public struct TIMING_FLAG { public uint interlacedAndReserved, formatUnion, scaling; }
    [StructLayout(LayoutKind.Sequential, Pack = 8)] public struct TIMING_INPUT { public uint version, width, height; public float rr; public TIMING_FLAG flag; public uint type; }
    [StructLayout(LayoutKind.Sequential, Pack = 8)] public struct VIEWPORTF { public float x, y, w, h; }
    [StructLayout(LayoutKind.Sequential, Pack = 8)] public struct CUSTOM_DISPLAY { public uint version, width, height, depth, colorFormat; public VIEWPORTF srcPartition; public float xRatio, yRatio; public TIMING timing; public uint hwModeSetOnly; }
    [DllImport("nvapi64.dll", EntryPoint = "nvapi_QueryInterface", CallingConvention = CallingConvention.Cdecl)] static extern IntPtr QueryInterface(uint id);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int InitializeFn();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int PrimaryIdFn(out uint displayId);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int GetTimingFn(uint displayId, ref TIMING_INPUT input, out TIMING timing);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int TryFn(ref uint displayId, uint count, ref CUSTOM_DISPLAY cd);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int SaveFn(ref uint displayId, uint count, uint outputOnly, uint monitorOnly);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int RevertFn(ref uint displayId, uint count);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int EnumFn(uint displayId, uint index, ref CUSTOM_DISPLAY cd);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DeleteFn(ref uint displayId, uint count, ref CUSTOM_DISPLAY cd);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int ErrorFn(int status, StringBuilder text);
    const uint ID_Initialize = 0x0150E828, ID_PrimaryId = 0x1E9D8A31, ID_GetTiming = 0x175167E9, ID_Try = 0x1F7DB630, ID_Save = 0x49882876, ID_Revert = 0xCBBD40F0, ID_Enum = 0xA2072D59, ID_Delete = 0x552E5B9B, ID_Error = 0x6C2D048C;
    const uint TIMING_INPUT_VER = 32 | (1 << 16), CUSTOM_DISPLAY_VER = 144 | (1 << 16);
    const uint OVERRIDE_AUTO = 1, OVERRIDE_CVT_RB = 6;
    static T Fn<T>(uint id) where T : class {
      IntPtr p = QueryInterface(id);
      if (p == IntPtr.Zero) throw new InvalidOperationException("NvAPI function 0x" + id.ToString("X") + " not exported by this driver");
      return Marshal.GetDelegateForFunctionPointer(p, typeof(T)) as T;
    }
    static string Err(int status) {
      try { StringBuilder sb = new StringBuilder(64); Fn<ErrorFn>(ID_Error)(status, sb); return "NvAPI error " + status + " (" + sb + ")"; }
      catch { return "NvAPI error " + status; }
    }
    public static string StructSizes() { return Marshal.SizeOf(typeof(TIMING_INPUT)) + "," + Marshal.SizeOf(typeof(TIMING)) + "," + Marshal.SizeOf(typeof(CUSTOM_DISPLAY)); }
    public static bool IsAvailable() {
      try { return Fn<InitializeFn>(ID_Initialize)() == 0; } catch { return false; }
    }
    static uint PrimaryId() {
      int rc = Fn<InitializeFn>(ID_Initialize)(); if (rc != 0) throw new InvalidOperationException(Err(rc));
      uint id; rc = Fn<PrimaryIdFn>(ID_PrimaryId)(out id); if (rc != 0) throw new InvalidOperationException(Err(rc));
      return id;
    }
    public static bool HasMode(int width, int height) {
      uint id = PrimaryId(); EnumFn e = Fn<EnumFn>(ID_Enum);
      for (uint i = 0; i < 64; i++) {
        CUSTOM_DISPLAY cd = new CUSTOM_DISPLAY(); cd.version = CUSTOM_DISPLAY_VER;
        if (e(id, i, ref cd) != 0) break;
        if (cd.width == width && cd.height == height) return true;
      }
      return false;
    }
    public static string AddMode(int width, int height, int hz) {
      if (Marshal.SizeOf(typeof(CUSTOM_DISPLAY)) != 144 || Marshal.SizeOf(typeof(TIMING_INPUT)) != 32) return "struct layout mismatch " + StructSizes();
      uint id = PrimaryId();
      TIMING_INPUT ti = new TIMING_INPUT(); ti.version = TIMING_INPUT_VER; ti.width = (uint)width; ti.height = (uint)height; ti.rr = hz; ti.type = OVERRIDE_AUTO;
      TIMING timing;
      int rc = Fn<GetTimingFn>(ID_GetTiming)(id, ref ti, out timing);
      if (rc != 0) { ti.type = OVERRIDE_CVT_RB; rc = Fn<GetTimingFn>(ID_GetTiming)(id, ref ti, out timing); }
      if (rc != 0) return "GetTiming: " + Err(rc);
      CUSTOM_DISPLAY cd = new CUSTOM_DISPLAY();
      cd.version = CUSTOM_DISPLAY_VER; cd.width = (uint)width; cd.height = (uint)height; cd.depth = 32; cd.colorFormat = 0;
      cd.srcPartition.x = 0; cd.srcPartition.y = 0; cd.srcPartition.w = 1; cd.srcPartition.h = 1; cd.xRatio = 1; cd.yRatio = 1; cd.timing = timing; cd.hwModeSetOnly = 0;
      rc = Fn<TryFn>(ID_Try)(ref id, 1, ref cd);
      if (rc != 0) return "TryCustomDisplay: " + Err(rc);
      rc = Fn<SaveFn>(ID_Save)(ref id, 1, 0, 0);
      int rv = Fn<RevertFn>(ID_Revert)(ref id, 1);
      if (rc != 0) return "SaveCustomDisplay: " + Err(rc);
      return rv == 0 ? "ok" : "ok (revert of the trial mode reported " + Err(rv) + ")";
    }
    // ---- driver settings repository: the database NVIDIA Control Panel and Profile Inspector write ----
    [StructLayout(LayoutKind.Sequential, Pack = 4)] public struct DRS_PROFILE {
      public uint version;
      [MarshalAs(UnmanagedType.ByValArray, SizeConst = 2048)] public ushort[] profileName;
      public uint gpuSupport, isPredefined, numOfApps, numOfSettings;
    }
    [StructLayout(LayoutKind.Sequential, Pack = 4)] public struct DRS_APPLICATION {
      public uint version, isPredefined;
      [MarshalAs(UnmanagedType.ByValArray, SizeConst = 2048)] public ushort[] appName;
      [MarshalAs(UnmanagedType.ByValArray, SizeConst = 2048)] public ushort[] userFriendlyName;
      [MarshalAs(UnmanagedType.ByValArray, SizeConst = 2048)] public ushort[] launcher;
    }
    // NVDRS_SETTING_V1 exists in two shapes in the wild: the original unions are 4-byte aligned
    // (4100 bytes each, struct 12320) and the later ones carry an NvU64 member that pushes them to
    // 8-byte alignment (4104 each, struct 12328), moving the current value by four bytes. Which one a
    // driver accepts is not discoverable up front, so the setting buffer is built by offset and both
    // are tried; the one that works is remembered. Everything before the unions is identical.
    struct SettingLayout { public int Size; public int CurrentValue; public int IsPredefined; }
    static readonly SettingLayout[] SettingLayouts = new SettingLayout[] {
      new SettingLayout { Size = 12328, CurrentValue = 8224, IsPredefined = 4112 },
      new SettingLayout { Size = 12320, CurrentValue = 8220, IsPredefined = 4112 }
    };
    static int settingLayout = -1;
    const int OFF_SETTING_ID = 4100, OFF_SETTING_TYPE = 4104, OFF_SETTING_LOCATION = 4108;
    static IntPtr NewSettingBuffer(SettingLayout l, uint id) {
      IntPtr buf = Marshal.AllocHGlobal(l.Size);
      for (int i = 0; i < l.Size; i += 4) Marshal.WriteInt32(buf, i, 0);
      Marshal.WriteInt32(buf, 0, (int)((uint)l.Size | (1u << 16)));
      Marshal.WriteInt32(buf, OFF_SETTING_ID, (int)id);
      Marshal.WriteInt32(buf, OFF_SETTING_TYPE, 0);
      Marshal.WriteInt32(buf, OFF_SETTING_LOCATION, 0);
      return buf;
    }
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DrsOpenFn(out IntPtr session);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DrsSessionFn(IntPtr session);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DrsFindAppFn(IntPtr session, ushort[] appName, out IntPtr profile, ref DRS_APPLICATION app);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DrsCreateProfileFn(IntPtr session, ref DRS_PROFILE profile, out IntPtr handle);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DrsCreateAppFn(IntPtr session, IntPtr profile, ref DRS_APPLICATION app);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DrsSettingFn(IntPtr session, IntPtr profile, IntPtr setting);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DrsGetSettingFn(IntPtr session, IntPtr profile, uint id, IntPtr setting);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DrsRestoreFn(IntPtr session, IntPtr profile, uint id);
    const uint ID_DrsCreateSession = 0x0694D52E, ID_DrsDestroySession = 0xDAD9CFF8, ID_DrsLoadSettings = 0x375DBD6B,
               ID_DrsSaveSettings = 0xFCBC7E14, ID_DrsCreateProfile = 0xCC176068, ID_DrsFindApp = 0xEEE566B2,
               ID_DrsCreateApp = 0x4347A9DE, ID_DrsSetSetting = 0x577DD202, ID_DrsGetSetting = 0x73BF8338,
               ID_DrsRestoreSetting = 0x53F0381E;
    static ushort[] Wide(string s) {
      ushort[] a = new ushort[2048];
      if (s != null) for (int i = 0; i < s.Length && i < 2047; i++) a[i] = s[i];
      return a;
    }
    static uint Ver(Type t, int v) { return (uint)(Marshal.SizeOf(t) | (v << 16)); }
    public static string DrsSizes() {
      return Marshal.SizeOf(typeof(DRS_PROFILE)) + "," + Marshal.SizeOf(typeof(DRS_APPLICATION)) + "," + SettingLayouts[0].Size;
    }
    public static int DrsLayout() { return settingLayout; }
    // Finds the profile that owns this executable, creating one only when the driver has none.
    static int OpenAppProfile(IntPtr session, string exe, string profileName, bool create, out IntPtr profile) {
      DRS_APPLICATION app = new DRS_APPLICATION();
      app.version = Ver(typeof(DRS_APPLICATION), 1);
      app.appName = Wide(exe); app.userFriendlyName = Wide(exe); app.launcher = Wide("");
      int rc = Fn<DrsFindAppFn>(ID_DrsFindApp)(session, Wide(exe), out profile, ref app);
      if (rc == 0 || !create) return rc;
      DRS_PROFILE p = new DRS_PROFILE();
      p.version = Ver(typeof(DRS_PROFILE), 1); p.profileName = Wide(profileName); p.gpuSupport = 1;
      rc = Fn<DrsCreateProfileFn>(ID_DrsCreateProfile)(session, ref p, out profile);
      if (rc != 0) return rc;
      DRS_APPLICATION na = new DRS_APPLICATION();
      na.version = Ver(typeof(DRS_APPLICATION), 1); na.isPredefined = 0;
      na.appName = Wide(exe); na.userFriendlyName = Wide(exe); na.launcher = Wide("");
      return Fn<DrsCreateAppFn>(ID_DrsCreateApp)(session, profile, ref na);
    }
    public static string DrsApply(string exe, string profileName, uint[] ids, uint[] values) {
      if (ids.Length != values.Length) return "id and value counts differ";
      int rc = Fn<InitializeFn>(ID_Initialize)(); if (rc != 0) return Err(rc);
      IntPtr session;
      rc = Fn<DrsOpenFn>(ID_DrsCreateSession)(out session); if (rc != 0) return "CreateSession: " + Err(rc);
      try {
        rc = Fn<DrsSessionFn>(ID_DrsLoadSettings)(session); if (rc != 0) return "LoadSettings: " + Err(rc);
        IntPtr profile;
        rc = OpenAppProfile(session, exe, profileName, true, out profile);
        if (rc != 0) return "profile for " + exe + ": " + Err(rc);
        DrsSettingFn set = Fn<DrsSettingFn>(ID_DrsSetSetting);
        for (int i = 0; i < ids.Length; i++) {
          rc = -1;
          for (int attempt = 0; attempt < SettingLayouts.Length; attempt++) {
            int which = settingLayout >= 0 ? settingLayout : attempt;
            SettingLayout l = SettingLayouts[which];
            IntPtr buf = NewSettingBuffer(l, ids[i]);
            try {
              Marshal.WriteInt32(buf, l.CurrentValue, (int)values[i]);
              rc = set(session, profile, buf);
            } finally { Marshal.FreeHGlobal(buf); }
            if (rc == 0) { settingLayout = which; break; }
            if (settingLayout >= 0) break;
          }
          if (rc != 0) return "SetSetting 0x" + ids[i].ToString("X8") + ": " + Err(rc);
        }
        rc = Fn<DrsSessionFn>(ID_DrsSaveSettings)(session);
        return rc == 0 ? "ok" : "SaveSettings: " + Err(rc);
      } finally { Fn<DrsSessionFn>(ID_DrsDestroySession)(session); }
    }
    public static string DrsRestore(string exe, uint[] ids) {
      int rc = Fn<InitializeFn>(ID_Initialize)(); if (rc != 0) return Err(rc);
      IntPtr session;
      rc = Fn<DrsOpenFn>(ID_DrsCreateSession)(out session); if (rc != 0) return "CreateSession: " + Err(rc);
      try {
        rc = Fn<DrsSessionFn>(ID_DrsLoadSettings)(session); if (rc != 0) return "LoadSettings: " + Err(rc);
        IntPtr profile;
        rc = OpenAppProfile(session, exe, "", false, out profile);
        if (rc != 0) return "no driver profile for " + exe;
        DrsRestoreFn restore = Fn<DrsRestoreFn>(ID_DrsRestoreSetting);
        for (int i = 0; i < ids.Length; i++) restore(session, profile, ids[i]);
        rc = Fn<DrsSessionFn>(ID_DrsSaveSettings)(session);
        return rc == 0 ? "ok" : "SaveSettings: " + Err(rc);
      } finally { Fn<DrsSessionFn>(ID_DrsDestroySession)(session); }
    }
    // "id:value:isDefault" per setting, so the UI can show what the driver holds right now.
    public static string DrsRead(string exe, uint[] ids) {
      int rc = Fn<InitializeFn>(ID_Initialize)(); if (rc != 0) return "";
      IntPtr session;
      if (Fn<DrsOpenFn>(ID_DrsCreateSession)(out session) != 0) return "";
      try {
        if (Fn<DrsSessionFn>(ID_DrsLoadSettings)(session) != 0) return "";
        IntPtr profile;
        if (OpenAppProfile(session, exe, "", false, out profile) != 0) return "";
        DrsGetSettingFn get = Fn<DrsGetSettingFn>(ID_DrsGetSetting);
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < ids.Length; i++) {
          for (int attempt = 0; attempt < SettingLayouts.Length; attempt++) {
            int which = settingLayout >= 0 ? settingLayout : attempt;
            SettingLayout l = SettingLayouts[which];
            IntPtr buf = NewSettingBuffer(l, ids[i]);
            try {
              if (get(session, profile, ids[i], buf) == 0) {
                settingLayout = which;
                if (sb.Length > 0) sb.Append(';');
                sb.Append("0x").Append(ids[i].ToString("X8")).Append(':')
                  .Append((uint)Marshal.ReadInt32(buf, l.CurrentValue)).Append(':')
                  .Append((uint)Marshal.ReadInt32(buf, l.IsPredefined));
                break;
              }
            } finally { Marshal.FreeHGlobal(buf); }
            if (settingLayout >= 0) break;
          }
        }
        return sb.ToString();
      } finally { Fn<DrsSessionFn>(ID_DrsDestroySession)(session); }
    }
    public static string DeleteMode(int width, int height) {
      uint id = PrimaryId(); EnumFn e = Fn<EnumFn>(ID_Enum);
      for (uint i = 0; i < 64; i++) {
        CUSTOM_DISPLAY cd = new CUSTOM_DISPLAY(); cd.version = CUSTOM_DISPLAY_VER;
        if (e(id, i, ref cd) != 0) break;
        if (cd.width != width || cd.height != height) continue;
        int rc = Fn<DeleteFn>(ID_Delete)(ref id, 1, ref cd);
        return rc == 0 ? "ok" : "DeleteCustomDisplay: " + Err(rc);
      }
      return "not found";
    }
  }

  public static class Bench {
    static ulong sink;
    static double Loop(int ms) {
      ulong x = 88172645463325252UL; double f = 1.0; long n = 0;
      System.Diagnostics.Stopwatch sw = System.Diagnostics.Stopwatch.StartNew();
      while (sw.ElapsedMilliseconds < ms) {
        for (int i = 0; i < 100000; i++) { x ^= x << 13; x ^= x >> 7; x ^= x << 17; f = f * 1.0000001 + (x & 0xFF); }
        n += 100000;
      }
      sink += x + (ulong)f;
      return n / sw.Elapsed.TotalSeconds;
    }
    public static double CpuSingle(int ms) { return Loop(ms); }
    public static double CpuMulti(int ms, int threads) {
      double[] r = new double[threads]; System.Threading.Thread[] t = new System.Threading.Thread[threads];
      for (int i = 0; i < threads; i++) { int k = i; t[i] = new System.Threading.Thread(delegate() { r[k] = Loop(ms); }); t[i].Start(); }
      for (int i = 0; i < threads; i++) t[i].Join();
      double sum = 0; foreach (double v in r) sum += v; return sum;
    }
    public static double MemCopy(int mb, int passes) {
      byte[] a = new byte[mb * 1024 * 1024], b = new byte[mb * 1024 * 1024];
      Buffer.BlockCopy(a, 0, b, 0, a.Length);
      System.Diagnostics.Stopwatch sw = System.Diagnostics.Stopwatch.StartNew();
      for (int i = 0; i < passes; i++) { Buffer.BlockCopy(a, 0, b, 0, a.Length); Buffer.BlockCopy(b, 0, a, 0, a.Length); }
      return (2.0 * passes * a.Length) / sw.Elapsed.TotalSeconds / (1024.0 * 1024.0 * 1024.0);
    }
  }
}
'@
    try {
        Add-Type -TypeDefinition $src -ErrorAction Stop
        return $true
    } catch {
        Write-UTLog ('Native helpers could not be compiled ({0}); the monitor falls back to WMI and the title bar stays light' -f $_.Exception.Message) -Level Warn
        return $false
    }
}

#endregion

#region Install-UTApps.ps1
function Get-UTWinget {
    <#
    .SYNOPSIS
        Full path to winget.exe, or $null. Elevated sessions often lack the App Execution Alias on PATH.
    #>
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path -LiteralPath $alias) { return $alias }
    try {
        $pkg = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
        if ($pkg) {
            $exe = Join-Path $pkg.InstallLocation 'winget.exe'
            if (Test-Path -LiteralPath $exe) { return $exe }
        }
    } catch { }
    # An elevated session runs under a different profile, so the per-user App Execution Alias above can be
    # missing even though winget is installed machine-wide. The package directory always has the real exe.
    try {
        $dir = Get-ChildItem -LiteralPath (Join-Path $env:ProgramFiles 'WindowsApps') -Filter 'Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe' -Directory -ErrorAction SilentlyContinue |
               Sort-Object Name -Descending | Select-Object -First 1
        if ($dir) {
            $exe = Join-Path $dir.FullName 'winget.exe'
            if (Test-Path -LiteralPath $exe) { return $exe }
        }
    } catch { }
    return $null
}

function Install-UTWinget {
    <#
    .SYNOPSIS
        Best-effort winget bootstrap: re-register App Installer if present, otherwise download the current bundle.
    #>
    Write-UTLog 'winget not found, trying to install App Installer...'
    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop
        if (Get-UTWinget) { Write-UTLog 'winget registered' -Level Ok; return $true }
    } catch { }
    try {
        $tmp = Join-Path $env:TEMP 'unknowntweaks-winget.msixbundle'
        Invoke-WebRequest -Uri 'https://aka.ms/getwinget' -OutFile $tmp -UseBasicParsing -ErrorAction Stop
        Add-AppxPackage -Path $tmp -ErrorAction Stop
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        if (Get-UTWinget) { Write-UTLog 'winget installed' -Level Ok; return $true }
    } catch {
        Write-UTLog ("winget could not be installed automatically: {0}. Install 'App Installer' from the Microsoft Store, then retry." -f $_.Exception.Message) -Level Error
    }
    return $false
}

function Install-UTApps {
    <#
    .SYNOPSIS
        Installs the selected applications.json entries with winget, silently, logging progress. Runs in a worker job.
    #>
    param([Parameter(Mandatory = $true)][string[]]$Names)
    $winget = Get-UTWinget
    if (-not $winget) { if (-not (Install-UTWinget)) { return }; $winget = Get-UTWinget }
    $ok = 0; $failed = 0
    foreach ($name in $Names) {
        $app = $sync.configs.applications.$name
        if (-not $app) { Write-UTLog "Unknown app $name" -Level Warn; continue }
        $id = [string]$app.Winget
        $sync.status = "Installing $name"
        Write-UTLog "----- winget install $id"
        try {
            $r = Invoke-UTNative -FilePath $winget -Arguments @(
                'install', '--id', $id, '--exact', '--silent',
                '--accept-source-agreements', '--accept-package-agreements',
                '--disable-interactivity', '--source', 'winget')
            $output = $r.Lines
            $code = $r.ExitCode
            foreach ($line in @($output)) {
                $text = ([string]$line).Trim()
                if (-not $text) { continue }
                # progress bars, spinners and download counters are noise in a log file
                if ($text -match '^[\\|/\-]+$') { continue }
                if ($text -match '^[\u2500-\u25FF\s\-]+$') { continue }
                if ($text -match '(KB|MB|GB)\s*/\s*[0-9.]+\s*(KB|MB|GB)') { continue }
                Write-UTLog "  $text"
            }
            if ($code -eq 0) { $ok++; Write-UTLog "$name installed" -Level Ok }
            elseif ($code -in @(-1978335189, -1978335135, -1978334963, -1978334962)) { $ok++; Write-UTLog "$name is already installed or newer" -Level Ok }
            elseif ($code -in @(-1978334967, -1978334965)) { $ok++; Write-UTLog "$name installed, but it needs a reboot to finish" -Level Ok; $sync.needReboot = $true }
            elseif ($code -eq -1978335146) { $failed++; Write-UTLog "$name refuses to install from an elevated window. Open a normal PowerShell (not as administrator) and run: winget install --id $id --exact" -Level Warn }
            elseif ($code -eq -1978335212) { $failed++; Write-UTLog "$name was not found in the winget catalogue under the id $id; it may have been renamed or removed" -Level Warn }
            else { $failed++; Write-UTLog ("{0} failed with winget exit code {1} (0x{2:X8})" -f $name, $code, $code) -Level Warn }
        } catch {
            $failed++
            Write-UTLog ("{0} failed: {1}" -f $name, $_.Exception.Message) -Level Error
        }
    }
    Write-UTLog ("Install done: {0} succeeded, {1} failed" -f $ok, $failed) -Level Ok
}

#endregion

#region Invoke-UTBenchmark.ps1
function Invoke-UTBenchmark {
    <#
    .SYNOPSIS
        A short synthetic run: CPU single and all-core throughput, memory copy bandwidth, system-disk
        sequential read and write with the cache bypassed. About ten seconds. Numbers are relative to
        the machine the tool was calibrated on (Ryzen 7 5800XT, DDR4-3200, NVMe = 100).
    #>
    if (-not ('UT.NativeV1.Bench' -as [type])) { throw 'The native benchmark helper is not available on this PC' }
    $r = [ordered]@{}
    Write-UTLog 'benchmark: CPU single core (3 s)'
    $r.CpuSingleMops = [math]::Round([UT.NativeV1.Bench]::CpuSingle(3000) / 1e6, 1)
    $threads = [Environment]::ProcessorCount
    Write-UTLog ("benchmark: CPU all cores, {0} threads (3 s)" -f $threads)
    $r.CpuMultiMops = [math]::Round([UT.NativeV1.Bench]::CpuMulti(3000, $threads) / 1e6, 1)
    Write-UTLog 'benchmark: memory copy (256 MB x 8)'
    $r.MemoryGBps = [math]::Round([UT.NativeV1.Bench]::MemCopy(256, 8), 1)
    Write-UTLog 'benchmark: system disk, 256 MB sequential, cache bypassed'
    $r.DiskWriteMBps = 0; $r.DiskReadMBps = 0
    try {
        $disk = Measure-UTDiskSequential -SizeMB 256
        $r.DiskWriteMBps = $disk.WriteMBps
        $r.DiskReadMBps = $disk.ReadMBps
    } catch { Write-UTLog ('benchmark: disk test skipped (' + $_.Exception.Message + ')') -Level Warn }
    $ref = @{ CpuSingleMops = 670.0; CpuMultiMops = 9100.0; MemoryGBps = 17.8; DiskReadMBps = 2500.0 }
    $r.CpuSingleScore = [math]::Round(100.0 * $r.CpuSingleMops / $ref.CpuSingleMops)
    $r.CpuMultiScore = [math]::Round(100.0 * $r.CpuMultiMops / $ref.CpuMultiMops)
    $r.MemoryScore = [math]::Round(100.0 * $r.MemoryGBps / $ref.MemoryGBps)
    $r.DiskScore = [math]::Round(100.0 * $r.DiskReadMBps / $ref.DiskReadMBps)
    $r.Tier = Get-UTPerformanceTier -CpuSingle $r.CpuSingleScore -CpuMulti $r.CpuMultiScore -Gpu $sync.sysinfo.GPU
    $r.When = (Get-Date).ToString('s')
    $sync.benchmark = [pscustomobject]$r
    Write-UTLog ("benchmark: CPU single {0} / multi {1} / memory {2} / disk {3}   (Ryzen 7 5800XT + NVMe = 100)   tier: {4}" -f $r.CpuSingleScore, $r.CpuMultiScore, $r.MemoryScore, $r.DiskScore, $r.Tier) -Level Ok
    return $sync.benchmark
}

function Measure-UTDiskSequential {
    param([int]$SizeMB = 256)
    $dir = Join-Path $env:LOCALAPPDATA 'unknowntweaks'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $path = Join-Path $dir ('bench-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $block = New-Object byte[] (4MB)
    (New-Object System.Random).NextBytes($block)
    $noBuffer = [System.IO.FileOptions]0x20000000 -bor [System.IO.FileOptions]::WriteThrough
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $fs = New-Object System.IO.FileStream($path, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None, 4MB, $noBuffer)
        try { for ($i = 0; $i -lt $SizeMB / 4; $i++) { $fs.Write($block, 0, $block.Length) }; $fs.Flush($true) } finally { $fs.Dispose() }
        $write = $SizeMB / $sw.Elapsed.TotalSeconds
        $sw.Restart()
        $fs = New-Object System.IO.FileStream($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None, 4MB, ([System.IO.FileOptions]0x20000000))
        try { while ($fs.Read($block, 0, $block.Length) -gt 0) { } } finally { $fs.Dispose() }
        $read = $SizeMB / $sw.Elapsed.TotalSeconds
        return [pscustomobject]@{ WriteMBps = [math]::Round($write); ReadMBps = [math]::Round($read) }
    } finally { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
}

function Get-UTPerformanceTier {
    param([int]$CpuSingle, [int]$CpuMulti, [string]$Gpu)
    $gpuTier = 1
    if ($Gpu -match 'RTX (40|50)\d\d|RX (7[89]|9[0-9])\d\d') { $gpuTier = 3 }
    elseif ($Gpu -match 'RTX (20|30)\d\d|RX (6[6-9]|7[0-7])\d\d|GTX 16[68]0|RTX 4060') { $gpuTier = 2 }
    elseif ($Gpu -match 'Intel|Vega|Radeon\(TM\) Graphics|UHD|Iris') { $gpuTier = 0 }
    $cpuTier = 1
    if ($CpuSingle -ge 90 -and $CpuMulti -ge 80) { $cpuTier = 3 } elseif ($CpuSingle -ge 65) { $cpuTier = 2 } elseif ($CpuSingle -lt 45) { $cpuTier = 0 }
    switch ([math]::Min($gpuTier, $cpuTier)) {
        3 { return 'high-end' }
        2 { return 'mid-range' }
        1 { return 'entry' }
        default { return 'low' }
    }
}

function Get-UTRecommendations {
    <#
    .SYNOPSIS
        Tweaks worth ticking on this PC, each with the reason, from the hardware facts and the last
        benchmark. Safe and optional ones can be ticked automatically; risky ones are only ever named.
    #>
    $si = $sync.sysinfo
    $b = $sync.benchmark
    $tw = $sync.configs.tweaks
    $out = New-Object System.Collections.Generic.List[object]
    $add = {
        param($Id, $Why, $Tick)
        if (-not $tw.$Id) { return }
        $out.Add([pscustomobject]@{ Id = $Id; Content = [string]$tw.$Id.Content; Tier = [string]$tw.$Id.Tier; Why = $Why; Tick = [bool]$Tick })
    }
    foreach ($p in $tw.PSObject.Properties) { if ($p.Value.Tier -eq 'safe' -and $p.Value.Recommended -and (Test-UTTweakEligible -Tweak $p.Value)) { & $add $p.Name 'in the safe preset: documented mechanism, no downside' $true } }
    if ($si.VBSStatus -eq 2 -or $si.HVCIRunning) {
        & $add 'UTHVCIOff' 'memory integrity is running on this PC: the largest measured FPS cost in the catalogue (4 to 8 percent, more when CPU-bound)' $false
        & $add 'UTVBSOff' 'virtualization-based security is running: turning the hypervisor off is the rest of that gain. Breaks WSL2, Hyper-V and Sandbox' $false
    }
    if ($si.IsLaptop) {
        & $add 'UTPowerThrottlingOff' 'laptop: Windows throttles background CPU frequency on battery-class hardware' $true
        & $add 'UTNicPowerSaving' 'laptop: NIC link power states add latency and are on by default here' $true
    } else {
        & $add 'UTHibernateOff' 'desktop: hibernation only costs disk space here' $true
        if ($b -and $b.CpuSingleScore -lt 70) { & $add 'UTUltimatePerf' 'older CPU without hardware P-states: the Ultimate Performance plan removes clock ramp-up delay' $true }
    }
    if ($si.DiskType -eq 'HDD') { & $add 'UTSearchIndexOff' 'the system drive is a hard disk: the indexer causes I/O stutter there' $true }
    if ($si.GPUVendor -eq 'NVIDIA' -or $si.GPUVendor -eq 'AMD') { & $add 'UTVendorGpuTasks' ($si.GPUVendor + ' driver: its telemetry and update-check tasks run in the background') $true }
    if ($si.GPU -match 'RTX|RX (5|6|7|9)\d\d\d|GTX 1[06]\d0') { & $add 'UTHAGS' 'this GPU supports hardware scheduling; required for DLSS Frame Generation, otherwise neutral' $false }
    if ($si.Is11 -and $si.Build -ge 22621) { & $add 'UTWindowedGamesOpt' 'Windows 11 22H2+: flip-model presentation for windowed games lowers latency' $true }
    if ($si.CPU -match 'X3D') { & $add 'UTCoreParkingOff' 'X3D CPU: this tweak is refused on purpose, Windows parks cores to keep games on the V-Cache die' $false }
    if ($b -and $b.Tier -in 'low', 'entry') {
        & $add 'UTGameModeOff' 'entry-level PC: try Game Mode off if you see stutter, it helps some low-end systems' $false
    }
    return $out.ToArray()
}

#endregion

#region Invoke-UTNetworkTool.ps1
function Invoke-UTNetworkTool {
    <#
    .SYNOPSIS
        Network repair and diagnosis commands. Runs in a worker job; output is streamed to the console.
    #>
    param(
        [Parameter(Mandatory = $true)][ValidateSet('flush', 'reset', 'tracert', 'linkinfo')][string]$Tool,
        [string]$Target
    )
    switch ($Tool) {
        'flush' {
            $null = Invoke-UTNative -FilePath 'ipconfig.exe' -Arguments @('/flushdns')
            Clear-DnsClientCache -ErrorAction SilentlyContinue
            Write-UTLog 'DNS resolver cache flushed' -Level Ok
        }
        'reset' {
            Write-UTLog 'Resetting Winsock and the TCP/IP stack. This is a repair, not a tune: it also removes any static IP/DNS and per-interface registry tweaks. Reboot afterwards.' -Level Warn
            $bad = 0
            $r1 = Invoke-UTNative -FilePath 'netsh.exe' -Arguments @('winsock', 'reset')
            Write-UTLog ("winsock reset (exit {0}): {1}" -f $r1.ExitCode, $r1.Output.Trim())
            if ($r1.ExitCode -ne 0) { $bad++ }
            $r2 = Invoke-UTNative -FilePath 'netsh.exe' -Arguments @('int', 'ip', 'reset')
            Write-UTLog ("int ip reset (exit {0}): {1}" -f $r2.ExitCode, $r2.Output.Trim())
            if ($r2.ExitCode -ne 0) { $bad++ }
            $null = Invoke-UTNative -FilePath 'ipconfig.exe' -Arguments @('/flushdns')
            if ($bad -gt 0) { throw "$bad of the 2 reset commands failed; the network stack was not fully reset" }
            Write-UTLog 'Network stack reset done. Reboot to complete it.' -Level Ok
            $sync.needReboot = $true
        }
        'tracert' {
            if (-not $Target) { throw 'No target' }
            Write-UTLog "tracert -d -w 1000 -h 24 $Target (intermediate hops that drop ICMP are normal; only the last hop matters)"
            $r = Invoke-UTNative -FilePath 'tracert.exe' -Arguments @('-d', '-w', '1000', '-h', '24', $Target)
            foreach ($t in $r.Lines) { $t = $t.Trim(); if ($t) { Write-UTLog "  $t" } }
            Write-UTLog 'tracert finished' -Level Ok
        }
        'linkinfo' {
            $l = Get-UTNetworkLink
            Write-UTLog ("Active link: {0} via {1} ({2}) {3} gateway {4}" -f $l.LinkType, $l.Adapter, $l.Description, $l.LinkSpeed, $l.Gateway)
            if ($l.IsWiFi) {
                Write-UTLog ("Wi-Fi network {0}, signal {1}. For competitive play a cable beats any tweak in this tool: Wi-Fi adds jitter and retransmits, not just ping." -f $l.SSID, $l.Signal) -Level Warn
            }
            try {
                $tcp = Get-NetTCPSetting -SettingName Internet -ErrorAction Stop
                Write-UTLog ("TCP: autotuning {0}, ECN {1}, congestion {2}" -f $tcp.AutoTuningLevelLocal, $tcp.EcnCapability, $tcp.CongestionProvider)
                if ([string]$tcp.AutoTuningLevelLocal -ne 'Normal') { Write-UTLog 'TCP receive window autotuning is not Normal. That caps download speed and helps nothing; a tweak pack probably changed it. Reset with: netsh int tcp set global autotuninglevel=normal' -Level Warn }
            } catch { }
            try {
                $teredo = Invoke-UTNative -FilePath 'netsh.exe' -Arguments @('interface', 'teredo', 'show', 'state')
                Write-UTLog ("Teredo: " + ((@($teredo.Lines) | Where-Object { $_ -match 'State|Type' } | ForEach-Object { $_.Trim() }) -join '; '))
            } catch { }
        }
    }
}

#endregion

#region Invoke-UTRunspace.ps1
function New-UTSessionState {
    <#
    .SYNOPSIS
        InitialSessionState carrying $sync and every *-UT* function, so worker runspaces can call any helper.
    #>
    if ($sync.sessionState) { return $sync.sessionState }
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach ($f in (Get-ChildItem -Path function:\ | Where-Object { $_.Name -match '-UT' })) {
        $iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $f.Name, $f.Definition))
    }
    $iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'sync', $sync, $null))
    $sync.sessionState = $iss
    return $iss
}

function Start-UTJob {
    <#
    .SYNOPSIS
        Runs a script in a background runspace. The script sees $sync and all UT functions, never WPF objects.
        When it finishes, its Kind is pushed to $sync.jobDone so the UI timer can react.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Kind,
        [Parameter(Mandatory = $true)][string]$Script,
        [hashtable]$Arguments
    )
    $wrapped = @"
param(`$Arguments)
`$ErrorActionPreference = 'Stop'
try {
$Script
} catch {
    Write-UTLog ('Job $Kind failed: ' + `$_.Exception.Message) -Level Error
} finally {
    # Announce completion first and release the lock last: between the two the UI thread may start a
    # new job, and clearing status afterwards would report 'ready' while that job is running.
    try { `$sync.jobDone.Enqueue('$Kind') } catch { }
    `$sync.status = 'ready'
    `$sync.busy = `$false
}
"@
    $rs = [runspacefactory]::CreateRunspace((New-UTSessionState))
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($wrapped)
    if ($null -eq $Arguments) { $Arguments = @{} }
    [void]$ps.AddArgument($Arguments)
    $handle = $ps.BeginInvoke()
    $job = @{ Kind = $Kind; PowerShell = $ps; Runspace = $rs; Handle = $handle; Started = (Get-Date) }
    [void]$sync.jobs.Add($job)
    return $job
}

function Remove-UTFinishedJobs {
    <#
    .SYNOPSIS
        Disposes completed worker runspaces and surfaces their error streams. Called from the UI timer.
    #>
    foreach ($job in @($sync.jobs)) {
        if (-not $job.Handle.IsCompleted) { continue }
        try {
            foreach ($e in $job.PowerShell.Streams.Error) { Write-UTLog ("Job {0}: {1}" -f $job.Kind, $e.ToString()) -Level Error }
            $job.PowerShell.EndInvoke($job.Handle) | Out-Null
        } catch {
            Write-UTLog ("Job {0} ended with: {1}" -f $job.Kind, $_.Exception.Message) -Level Error
        }
        try { $job.PowerShell.Dispose(); $job.Runspace.Close(); $job.Runspace.Dispose() } catch { }
        $sync.jobs.Remove($job)
    }
}

function Stop-UTJobs {
    foreach ($job in @($sync.jobs)) {
        try { $job.PowerShell.Stop() } catch { }
        try { $job.PowerShell.Dispose(); $job.Runspace.Close(); $job.Runspace.Dispose() } catch { }
    }
    $sync.jobs.Clear()
}

#endregion

#region Invoke-UTSimple.ps1
function Test-UTSimpleCondition {
    <#
    .SYNOPSIS
        Whether one step of a Simple-mode plan applies to this PC, and the reason when it does not.
    .DESCRIPTION
        Conditions are named rather than scripted so a config edit can never run code. "legacy-gpu" is
        the one that matters: forcing the DX11 renderer helps older NVIDIA cards and hurts modern ones,
        so a one-click mode has to decide per machine instead of writing the same argument everywhere.
    #>
    param([string]$Name)
    $si = $sync.sysinfo
    switch ($Name) {
        'nvidia' {
            if ($si.GPUVendor -eq 'NVIDIA') { return @{ Ok = $true } }
            return @{ Ok = $false; Why = 'no NVIDIA GPU on this PC' }
        }
        'legacy-gpu' {
            if ($si.GPUVendor -ne 'NVIDIA') { return @{ Ok = $false; Why = 'the DX11 switch is an NVIDIA-era setting' } }
            if ($si.GPU -match 'GTX\s*(9|10|16)\d0' -or [double]$si.VramGB -le 4) { return @{ Ok = $true } }
            return @{ Ok = $false; Why = ('{0} does better on DX12 Performance Mode' -f $si.GPU) }
        }
        'modern-gpu' {
            $legacy = Test-UTSimpleCondition -Name 'legacy-gpu'
            if ($legacy.Ok) { return @{ Ok = $false; Why = 'this GPU takes the DX11 route instead' } }
            return @{ Ok = $true }
        }
        default { return @{ Ok = $true } }
    }
}

function Get-UTSimplePlan {
    <#
    .SYNOPSIS
        The steps a Simple-mode game would run here, each already resolved against this PC.
    #>
    param([Parameter(Mandatory = $true)][string]$Game)
    $cfg = $sync.configs.simple.Games.$Game
    if (-not $cfg) { throw "Unknown Simple-mode game $Game" }
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($step in @($cfg.Steps)) {
        $c = Test-UTSimpleCondition -Name ([string]$step.When)
        $out.Add([pscustomobject]@{
            Kind = [string]$step.Kind; Value = [string]$step.Value
            Text = [string]$step.Text; Detail = [string]$step.Detail
            Applies = [bool]$c.Ok; Why = [string]$c.Why
        })
    }
    return $out.ToArray()
}

function Invoke-UTSimpleOptimize {
    <#
    .SYNOPSIS
        Runs one Simple-mode plan top to bottom.
    .DESCRIPTION
        Every step is independent: a game that is not installed, or is running, fails its own step and
        the rest still run, because a newbie pressing one button should not be left half done with no
        idea which half. Each step reports itself and the tally is logged at the end.
    #>
    param([Parameter(Mandatory = $true)][string]$Game)
    $plan = @(Get-UTSimplePlan -Game $Game | Where-Object { $_.Applies })
    $done = 0; $failed = 0
    Write-UTLog ("Simple mode: optimizing for {0} ({1} step(s))" -f $sync.configs.simple.Games.$Game.Content, $plan.Count)
    foreach ($step in $plan) {
        try {
            switch ($step.Kind) {
                'restorepoint'     { [void](New-UTRestorePoint) }
                'tweaks'           {
                    $ids = @($sync.configs.tweaks.PSObject.Properties |
                             Where-Object { $_.Value.Tier -eq 'safe' -and $_.Value.Recommended -and (Test-UTTweakEligible -Tweak $_.Value) } |
                             ForEach-Object { $_.Name })
                    Invoke-UTTweaks -Ids ([string[]]$ids)
                }
                'fortnite-profile' { Set-UTFortniteSettings -ProfileName $step.Value }
                'fortnite-args'    { Set-UTLaunchArgs -Arguments $step.Value }
                'valorant-profile' { Set-UTValorantSettings -ProfileName $step.Value }
                'nvprofile'        { Set-UTNvProfile -PresetName $step.Value }
                default            { Write-UTLog ("unknown Simple step {0}" -f $step.Kind) -Level Warn }
            }
            $done++
        } catch {
            $failed++
            Write-UTLog ('{0}: {1}' -f $step.Text, $_.Exception.Message) -Level Error
        }
    }
    if ($failed -eq 0) {
        Write-UTLog ("Simple mode finished: {0} step(s) done. Restart the game, and reboot when you get the chance." -f $done) -Level Ok
    } else {
        Write-UTLog ("Simple mode finished: {0} step(s) done, {1} could not run (each one is logged above). Everything that did run is still undoable." -f $done, $failed) -Level Warn
    }
}

#endregion

#region Invoke-UTTweaks.ps1
function Invoke-UTScript {
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][string]$Script)
    $block = [scriptblock]::Create($Script)
    & $block
}

function Test-UTTweakGuard {
    <#
    .SYNOPSIS
        Runs a tweak's GuardScript BEFORE anything is snapshotted or changed. A guard that throws stops
        the tweak cleanly, leaving no snapshot and no "applied" label behind.
    #>
    param([Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)]$Tweak)
    foreach ($g in @($Tweak.GuardScript | Where-Object { $_ })) {
        Invoke-UTScript -Name $Id -Script $g
    }
}
function Test-UTTweakEligible {
    <#
    .SYNOPSIS
        $true when this Windows build is new enough for the tweak.
    .DESCRIPTION
        A tweak that names a MinBuild the machine does not meet is not a failure, it simply does not
        exist on this Windows. The UI says so on the label and leaves it out of the recommended
        preset, so "Select recommended" does not end in red on every Windows 10 machine.
    #>
    param([Parameter(Mandatory = $true)]$Tweak)
    if (-not $Tweak.MinBuild) { return $true }
    if (-not $sync.sysinfo) { return $true }
    return ([int]$sync.sysinfo.Build -ge [int]$Tweak.MinBuild)
}


function Invoke-UTTweakApply {
    param([Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)]$Tweak)
    if (-not (Test-UTTweakEligible -Tweak $Tweak)) {
        # Not a failure: the tweak simply does not exist on this Windows. Reporting it as one makes
        # "Select recommended" end in red on every Windows 10 machine.
        Write-UTLog ("{0} needs Windows build {1} or newer and this PC is {2}, so it was skipped." -f $Tweak.Content, $Tweak.MinBuild, $sync.sysinfo.Build) -Level Warn
        return 'skipped'
    }
    if ($Tweak.LaptopWarning -and $sync.sysinfo -and $sync.sysinfo.IsLaptop) {
        Write-UTLog "Laptop detected: $($Tweak.LaptopWarning)" -Level Warn
    }
    # Anything that can refuse this tweak runs first, so a refusal cannot leave a half-applied machine.
    Test-UTTweakGuard -Id $Id -Tweak $Tweak

    if (Test-UTBackupExists -Id $Id) {
        Write-UTLog "$($Tweak.Content) is already applied; re-running it would record the tweaked values as the originals, so it was skipped. Undo it first if you want to apply it again." -Level Warn
        return 'skipped'
    }

    Save-UTBackup -Id $Id -Tweak $Tweak
    $failed = 0
    foreach ($r in @($Tweak.registry | Where-Object { $_ })) {
        if (-not (Set-UTRegistry -Path $r.Path -Name $r.Name -Type $r.Type -Value ([string]$r.Value))) { $failed++ }
    }
    foreach ($s in @($Tweak.service | Where-Object { $_ })) {
        if (-not (Set-UTService -Name $s.Name -StartupType $s.StartupType)) { $failed++ }
    }
    foreach ($t in @($Tweak.ScheduledTask | Where-Object { $_ })) {
        if (-not (Set-UTScheduledTask -Name $t.Name -State $t.State)) { $failed++ }
    }
    foreach ($script in @($Tweak.InvokeScript | Where-Object { $_ })) {
        Invoke-UTScript -Name $Id -Script $script
    }
    if ($failed -gt 0) { throw "$failed change(s) could not be made; the snapshot was kept so Undo still works" }
    return 'done'
}

function Invoke-UTTweakUndo {
    param([Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)]$Tweak, [switch]$Force)
    $backup = Get-UTBackup -Id $Id
    if (-not $backup) {
        if (-not $Force) {
            # Without a snapshot the tool would be writing its own idea of the Windows default onto a
            # machine it may never have touched. Refuse instead of guessing.
            Write-UTLog "$($Tweak.Content) was not applied by unknowntweaks on this PC (no snapshot), so there is nothing to undo. Nothing was changed." -Level Warn
            return 'skipped'
        }
        Write-UTLog "No snapshot for $($Tweak.Content); forcing the documented Windows defaults" -Level Warn
    } else {
        Write-UTLog "Restoring from the snapshot taken when $Id was applied"
    }

    # The snapshot, not the catalogue, is the record of what this machine actually had changed. An
    # entry dropped from config/tweaks.json after someone applied it would otherwise never be put
    # back: the undo would walk the new, shorter list and silently leave the old change in place.
    $failed = 0
    $regTargets = @()
    foreach ($r in @($Tweak.registry | Where-Object { $_ })) {
        $regTargets += [pscustomobject]@{ Path = [string]$r.Path; Name = [string]$r.Name; Type = [string]$r.Type; OriginalValue = [string]$r.OriginalValue }
    }
    foreach ($e in @($backup.Registry | Where-Object { $_ })) {
        if (@($regTargets | Where-Object { $_.Path -eq $e.Path -and $_.Name -eq $e.Name }).Count -gt 0) { continue }
        Write-UTLog ("{0}\{1} is in the snapshot but no longer in the catalogue; restoring it anyway" -f $e.Path, $e.Name)
        $regTargets += [pscustomobject]@{ Path = [string]$e.Path; Name = [string]$e.Name; Type = [string]$e.Kind; OriginalValue = '' }
    }
    foreach ($r in $regTargets) {
        $entry = $null
        if ($backup -and $backup.Registry) {
            $entry = @($backup.Registry) | Where-Object { $_.Path -eq $r.Path -and $_.Name -eq $r.Name } | Select-Object -First 1
        }
        $ok = $true
        if ($entry) {
            if ($entry.Exists) { $ok = Set-UTRegistry -Path $r.Path -Name $r.Name -Type $entry.Kind -Value ([string]$entry.Value) }
            else { $ok = Set-UTRegistry -Path $r.Path -Name $r.Name -Type $r.Type -Value '<RemoveEntry>' }
        } else {
            $orig = [string]$r.OriginalValue
            if ([string]::IsNullOrEmpty($orig)) { $orig = '<RemoveEntry>' }
            $ok = Set-UTRegistry -Path $r.Path -Name $r.Name -Type $r.Type -Value $orig
        }
        if (-not $ok) { $failed++ }
    }

    $svcNames = @(@($Tweak.service | Where-Object { $_ }) | ForEach-Object { [string]$_.Name })
    foreach ($e in @($backup.Service | Where-Object { $_ })) {
        if ($e.Name -and $svcNames -notcontains [string]$e.Name) {
            Write-UTLog ("Service {0} is in the snapshot but no longer in the catalogue; restoring it anyway" -f $e.Name)
            $svcNames += [string]$e.Name
        }
    }
    foreach ($name in $svcNames) {
        $target = $null
        if ($backup -and $backup.Service) {
            $entry = @($backup.Service) | Where-Object { $_.Name -eq $name } | Select-Object -First 1
            if ($entry -and $entry.StartupType) { $target = [string]$entry.StartupType }
        }
        if (-not $target) {
            $cfg = @($Tweak.service | Where-Object { $_ -and $_.Name -eq $name }) | Select-Object -First 1
            if ($cfg) { $target = [string]$cfg.OriginalType }
        }
        if ($target) { if (-not (Set-UTService -Name $name -StartupType $target)) { $failed++ } }
    }

    $taskNames = @(@($Tweak.ScheduledTask | Where-Object { $_ }) | ForEach-Object { [string]$_.Name })
    foreach ($e in @($backup.Task | Where-Object { $_ })) {
        if ($e.Name -and $taskNames -notcontains [string]$e.Name) {
            Write-UTLog ("Task {0} is in the snapshot but no longer in the catalogue; restoring it anyway" -f $e.Name)
            $taskNames += [string]$e.Name
        }
    }
    foreach ($name in $taskNames) {
        $target = $null
        if ($backup -and $backup.Task) {
            $entry = @($backup.Task) | Where-Object { $_.Name -eq $name } | Select-Object -First 1
            if ($entry -and $entry.State) { $target = [string]$entry.State }
        }
        if (-not $target) {
            $cfg = @($Tweak.ScheduledTask | Where-Object { $_ -and $_.Name -eq $name }) | Select-Object -First 1
            if ($cfg) { $target = [string]$cfg.OriginalState }
        }
        if ($target -in 'Enabled', 'Disabled') { if (-not (Set-UTScheduledTask -Name $name -State $target)) { $failed++ } }
    }

    foreach ($script in @($Tweak.UndoScript | Where-Object { $_ })) {
        Invoke-UTScript -Name $Id -Script $script
    }
    if ($failed -gt 0) { throw "$failed change(s) could not be reverted; the snapshot was kept so you can retry" }
    Remove-UTBackup -Id $Id
    return 'done'
}

function Invoke-UTTweaks {
    <#
    .SYNOPSIS
        Applies or undoes a list of tweak ids from $sync.configs.tweaks. Runs inside a worker runspace.
    #>
    param([Parameter(Mandatory = $true)][string[]]$Ids, [switch]$Undo, [switch]$Force)
    $verb = 'Applying'
    if ($Undo) { $verb = 'Undoing' }
    $ok = 0; $failed = 0; $skipped = 0; $reboot = $false; $signOut = $false
    foreach ($id in $Ids) {
        $tweak = $sync.configs.tweaks.$id
        if (-not $tweak) { Write-UTLog "Unknown tweak id $id" -Level Warn; continue }
        $sync.status = '{0}: {1}' -f $verb, $tweak.Content
        Write-UTLog ('----- {0}: {1}' -f $verb, $tweak.Content)
        try {
            # The worker reports what it did; inferring it from the snapshot file would miscount one-shot
            # actions (clearing temp files), which deliberately leave no snapshot behind.
            $result = if ($Undo) { Invoke-UTTweakUndo -Id $id -Tweak $tweak -Force:$Force } else { Invoke-UTTweakApply -Id $id -Tweak $tweak }
            if (@($result) -contains 'skipped') {
                $skipped++
            } else {
                $ok++
                if ($tweak.Reboot) { $reboot = $true }
                if ($tweak.SignOut) { $signOut = $true }
            }
        } catch {
            $failed++
            Write-UTLog ('{0} failed: {1}' -f $tweak.Content, $_.Exception.Message) -Level Error
        }
    }
    $summary = '{0} done: {1} succeeded, {2} failed, {3} skipped' -f $verb, $ok, $failed, $skipped
    if ($failed -gt 0) { Write-UTLog $summary -Level Warn } else { Write-UTLog $summary -Level Ok }
    if ($reboot) { Write-UTLog 'At least one change needs a reboot to take effect' -Level Warn }
    elseif ($signOut) { Write-UTLog 'At least one change needs a sign-out (or reboot) to take effect' -Level Warn }
    # Never clear a pending reboot that an earlier run raised.
    if ($reboot) { $sync.needReboot = $true }
    $sync.status = 'ready'
}

#endregion

#region Measure-UTRegionPing.ps1
function Measure-UTRegionPing {
    <#
    .SYNOPSIS
        Pings every Fortnite region host (plus the internet baseline) several rounds in parallel and returns
        avg / min / max / jitter / loss per region, sorted by average. Runs in a worker job.
    #>
    param([int]$Rounds = 6, [int]$TimeoutMs = 1200)
    $targets = @()
    foreach ($r in @($sync.configs.gameservers.Fortnite.Regions)) { $targets += [pscustomobject]@{ Region = $r.Region; Host = $r.Host; Location = $r.Location } }
    foreach ($r in @($sync.configs.gameservers.Baseline)) { $targets += [pscustomobject]@{ Region = $r.Region; Host = $r.Host; Location = $r.Location } }

    # Resolve every name once up front. SendPingAsync would otherwise do a blocking DNS lookup inside the
    # shared WaitAll budget, and a cold cache would show up as 100 percent loss on the first round.
    foreach ($t in $targets) {
        $t | Add-Member -NotePropertyName Address -NotePropertyValue $t.Host -Force
        try {
            $ip = @([System.Net.Dns]::GetHostAddresses($t.Host) | Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork })
            if ($ip.Count -gt 0) { $t.Address = $ip[0].IPAddressToString }
        } catch {
            Write-UTLog ("{0}: {1} could not be resolved" -f $t.Region, $t.Host) -Level Warn
        }
    }

    $samples = @{}
    foreach ($t in $targets) { $samples[$t.Host] = New-Object System.Collections.Generic.List[double] }
    $sent = @{}
    foreach ($t in $targets) { $sent[$t.Host] = 0 }

    for ($round = 1; $round -le $Rounds; $round++) {
        $tasks = @{}
        $pingers = @()
        foreach ($t in $targets) {
            $p = New-Object System.Net.NetworkInformation.Ping
            $pingers += $p
            try { $tasks[$t.Host] = $p.SendPingAsync($t.Address, $TimeoutMs); $sent[$t.Host]++ } catch { }
        }
        if ($tasks.Count -gt 0) {
            try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($tasks.Values), ($TimeoutMs + 800)) } catch { }
        }
        foreach ($h in @($tasks.Keys)) {
            $task = $tasks[$h]
            try {
                if ($task.IsCompleted -and -not $task.IsFaulted) {
                    $reply = $task.Result
                    if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) { $samples[$h].Add([double]$reply.RoundtripTime) }
                }
            } catch { }
        }
        foreach ($p in $pingers) { try { $p.Dispose() } catch { } }
        if ($round -lt $Rounds) { Start-Sleep -Milliseconds 250 }
    }

    $results = @()
    foreach ($t in $targets) {
        $list = $samples[$t.Host]
        $n = $sent[$t.Host]
        $avg = $null; $min = $null; $max = $null; $jitter = $null
        if ($list.Count -gt 0) {
            $m = $list | Measure-Object -Average -Minimum -Maximum
            $avg = [math]::Round($m.Average, 0); $min = [int]$m.Minimum; $max = [int]$m.Maximum
            if ($list.Count -gt 1) {
                $d = 0.0
                for ($i = 1; $i -lt $list.Count; $i++) { $d += [math]::Abs($list[$i] - $list[$i - 1]) }
                $jitter = [math]::Round($d / ($list.Count - 1), 1)
            } else { $jitter = 0 }
        }
        $loss = 100
        if ($n -gt 0) { $loss = [math]::Round(100.0 * ($n - $list.Count) / $n, 0) }
        $results += [pscustomobject]@{ Region = $t.Region; Host = $t.Host; Location = $t.Location; AvgMs = $avg; MinMs = $min; MaxMs = $max; JitterMs = $jitter; LossPct = $loss; Replies = $list.Count; Sent = $n }
    }
    $sorted = @($results | Sort-Object @{ Expression = { if ($null -eq $_.AvgMs) { 99999 } else { $_.AvgMs } } })
    $sync.regions = $sorted
    $best = $sorted | Where-Object { $_.Host -like '*epicgames.com' -and $null -ne $_.AvgMs } | Select-Object -First 1
    if ($best) { $sync.bestRegion = '{0} {1} ms' -f $best.Region, $best.AvgMs } else { $sync.bestRegion = 'no reply' }
    return $sorted
}

function Format-UTRegionTable {
    param($Rows)
    $rows = @($Rows | Where-Object { $null -ne $_ })
    # The REGION column is sized from the data, not fixed: the baseline row is labelled
    # "Internet (Cloudflare)" (21 characters), and a -14 pad pushed every later column of that one
    # row seven places to the right, in a monospaced box where the whole point is that they line up.
    $w = 'REGION'.Length
    foreach ($r in $rows) { if (([string]$r.Region).Length -gt $w) { $w = ([string]$r.Region).Length } }
    $fmt = '{0,-' + $w + '} {1,6} {2,6} {3,6} {4,7} {5,5}  {6}'
    $row = '{0,-' + $w + '} {1,6} {2,6} {3,6} {4,7} {5,4}%  {6}'
    $lines = @()
    $lines += $fmt -f 'REGION', 'AVG', 'MIN', 'MAX', 'JITTER', 'LOSS', 'LOCATION'
    foreach ($r in $rows) {
        if ($null -eq $r.AvgMs) {
            $lines += $row -f $r.Region, 'n/a', '-', '-', '-', $r.LossPct, ($r.Location + '   (no ICMP reply; not proof the region is down)')
        } else {
            # Kept out of the location text itself: "Dallas jitter!" read as though the place were
            # called that. An arrow makes it obvious the note is about the numbers on this row.
            $flags = @()
            if ($r.JitterMs -gt 5) { $flags += 'high jitter' }
            if ($r.LossPct -gt 0) { $flags += 'packet loss' }
            $note = [string]$r.Location
            if ($flags.Count) { $note += '   <- ' + ($flags -join ', ') }
            $lines += $row -f $r.Region, $r.AvgMs, $r.MinMs, $r.MaxMs, $r.JitterMs, $r.LossPct, $note
        }
    }
    return ($lines -join "`r`n")
}

#endregion

#region New-UTRestorePoint.ps1
function New-UTRestorePoint {
    <#
    .SYNOPSIS
        Creates a System Restore point (Windows PowerShell 5.1 only). Returns $true on success.
    .NOTES
        Windows refuses a second restore point within 24 hours unless SystemRestorePointCreationFrequency is 0.
        System Protection is off by default on many PCs; Enable-ComputerRestore turns it on for the system drive.
    #>
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $previous = Get-UTRegistryValue -Path $key -Name 'SystemRestorePointCreationFrequency'
    try {
        Write-UTLog 'Creating a System Restore point, this can take a minute...'
        # Windows refuses a second restore point within 24 hours unless this is 0. It is a system-wide
        # setting, so it is put back exactly as it was in the finally block below.
        Set-ItemProperty -LiteralPath $key -Name SystemRestorePointCreationFrequency -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
        Checkpoint-Computer -Description ('unknowntweaks {0:yyyy-MM-dd HH:mm}' -f (Get-Date)) -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-UTLog 'Restore point created' -Level Ok
        return $true
    } catch {
        Write-UTLog ('Restore point could not be created: {0}' -f $_.Exception.Message) -Level Warn
        return $false
    } finally {
        if ($previous.Exists) {
            Set-ItemProperty -LiteralPath $key -Name SystemRestorePointCreationFrequency -Type DWord -Value ([int]$previous.Value) -Force -ErrorAction SilentlyContinue
        } else {
            Remove-ItemProperty -LiteralPath $key -Name SystemRestorePointCreationFrequency -Force -ErrorAction SilentlyContinue
        }
    }
}

#endregion

#region Remove-UTAppxPackages.ps1
function Get-UTAppxNeverRemove {
    <#
    .SYNOPSIS
        Packages this tool refuses to remove, whatever config/debloat.json says.
    .DESCRIPTION
        A second lock on the door. config/debloat.json is data and could be edited by hand or by a
        future careless commit; this list is code, and Remove-UTBloatApps checks it last. Everything
        here either cannot be reinstalled from the Store, or takes a documented piece of Windows with
        it. The Xbox two are the ones that matter for a gaming machine:

          XboxIdentityProvider - Xbox sign-in for PC games. Removing it is the documented cause of
                                 Minecraft, Forza and Game Pass titles refusing to sign in.
          GamingServices       - the Game Pass install and licensing service. Removing it breaks
                                 installing or launching Game Pass games and is painful to restore.
    #>
    return @(
        'Microsoft.WindowsStore',
        'Microsoft.StorePurchaseApp',
        'Microsoft.DesktopAppInstaller',
        'Microsoft.XboxIdentityProvider',
        'Microsoft.GamingServices',
        'Microsoft.GamingApp',
        'Microsoft.Windows.SecHealthUI',
        'Microsoft.SecHealthUI',
        'Microsoft.Windows.ShellExperienceHost',
        'Microsoft.Windows.StartMenuExperienceHost',
        'Microsoft.Windows.Search',
        'Microsoft.Windows.CloudExperienceHost',
        'Microsoft.Windows.ContentDeliveryManager',
        'Microsoft.AAD.BrokerPlugin',
        'Microsoft.AccountsControl',
        'Microsoft.CredDialogHost',
        'Microsoft.LockApp',
        'Microsoft.UI.Xaml',
        'Microsoft.VCLibs',
        'Microsoft.NET',
        'Microsoft.WindowsAppRuntime',
        'Microsoft.WebView2',
        'Microsoft.HEIFImageExtension',
        'Microsoft.VP9VideoExtensions',
        'Microsoft.WebMediaExtensions',
        'Microsoft.WebpImageExtension',
        'Microsoft.MicrosoftEdge.Stable',
        'NVIDIACorp.NVIDIAControlPanel',
        'AdvancedMicroDevicesInc',
        'RealtekSemiconductorCorp'
    )
}

function Test-UTAppxRemovable {
    <#
    .SYNOPSIS
        $true when a package name may be removed. Returns the reason in -Reason when it may not.
    #>
    param([Parameter(Mandatory = $true)][string]$Name, [ref]$Reason)
    foreach ($blocked in (Get-UTAppxNeverRemove)) {
        # Prefix match: framework and vendor packages carry a version or product suffix.
        if ($Name -eq $blocked -or $Name -like ($blocked + '.*')) {
            if ($Reason) { $Reason.Value = "on the never-remove list ($blocked)" }
            return $false
        }
    }
    return $true
}

function Get-UTBloatApps {
    <#
    .SYNOPSIS
        The debloat catalogue joined against what is actually installed on this machine.
    .NOTES
        Only packages present here are offered, so the list is never a wall of things that are
        already gone. Anything Windows marks NonRemovable, or that is a framework other packages
        link against, is dropped before the user ever sees it.
    #>
    $installed = @{}
    try {
        foreach ($p in @(Get-AppxPackage -ErrorAction SilentlyContinue)) {
            if ($p.IsFramework -or $p.NonRemovable) { continue }
            $installed[[string]$p.Name] = $p
        }
    } catch { }
    $out = @()
    foreach ($prop in @($sync.configs.debloat.PSObject.Properties)) {
        $name = $prop.Name
        if (-not $installed.ContainsKey($name)) { continue }
        $reason = ''
        if (-not (Test-UTAppxRemovable -Name $name -Reason ([ref]$reason))) { continue }
        $out += [pscustomobject]@{
            Name        = $name
            Content     = [string]$prop.Value.Content
            Category    = [string]$prop.Value.Category
            Note        = [string]$prop.Value.Note
            Recommended = [bool]$prop.Value.Recommended
        }
    }
    return @($out | Sort-Object Category, Content)
}

function Remove-UTBloatApps {
    <#
    .SYNOPSIS
        Removes Store apps for this account, and optionally deprovisions them so a new account or a
        feature update does not bring them back. Runs inside a worker runspace.
    .DESCRIPTION
        This is the one thing in the tool that is NOT reversible from a snapshot: an appx package is
        uninstalled, not flagged off. Every name removed is written to
        %ProgramData%\unknowntweaks\backup\removed-apps.txt so there is a list to reinstall from the
        Store afterwards. The UI asks for confirmation and says this in as many words.
    #>
    param([Parameter(Mandatory = $true)][string[]]$Names, [switch]$AllUsers)
    $removed = @()
    $failed = 0
    $skipped = 0
    foreach ($name in $Names) {
        $reason = ''
        if (-not (Test-UTAppxRemovable -Name $name -Reason ([ref]$reason))) {
            Write-UTLog ("Refused to remove {0}: {1}" -f $name, $reason) -Level Warn
            $skipped++
            continue
        }
        $pkgs = @(Get-AppxPackage -Name $name -ErrorAction SilentlyContinue | Where-Object { -not $_.NonRemovable })
        if ($pkgs.Count -eq 0) {
            Write-UTLog ("{0} is not installed for this account, nothing to do" -f $name)
            $skipped++
            continue
        }
        $ok = $true
        foreach ($pkg in $pkgs) {
            try { Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop }
            catch {
                $ok = $false
                Write-UTLog ("{0} could not be removed: {1}" -f $name, $_.Exception.Message) -Level Error
            }
        }
        if (-not $ok) { $failed++; continue }
        Write-UTLog ("Removed {0}" -f $name) -Level Ok
        $removed += $name
        if ($AllUsers) {
            # Deprovisioning stops the package being installed into new accounts and reinstated by a
            # feature update. It needs DISM and therefore elevation, which the tool already has.
            try {
                $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq $name })
                foreach ($p in $prov) {
                    Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop | Out-Null
                    Write-UTLog ("Deprovisioned {0}: it will not come back for new accounts or after a feature update" -f $name)
                }
            } catch {
                Write-UTLog ("{0} was removed for this account but could not be deprovisioned: {1}" -f $name, $_.Exception.Message) -Level Warn
            }
        }
    }
    if ($removed.Count -gt 0) {
        try {
            $file = Join-Path $sync.backupDir 'removed-apps.txt'
            $stamp = Get-Date -Format 's'
            Add-Content -LiteralPath $file -Value (@($removed | ForEach-Object { "$stamp`t$_" })) -Encoding UTF8
            Write-UTLog ("The list of removed apps was appended to {0}. Reinstall any of them from the Microsoft Store." -f $file)
        } catch { }
    }
    $msg = 'Debloat done: {0} removed, {1} failed, {2} skipped' -f $removed.Count, $failed, $skipped
    if ($failed -gt 0) { Write-UTLog $msg -Level Warn } else { Write-UTLog $msg -Level Ok }
    $sync.status = 'ready'
}

#endregion

#region Save-UTBackup.ps1
function Get-UTBackupPath {
    param([Parameter(Mandatory = $true)][string]$Id, [string]$Suffix = '.json')
    if (-not (Test-Path -LiteralPath $sync.backupDir)) { New-Item -ItemType Directory -Path $sync.backupDir -Force | Out-Null }
    return (Join-Path $sync.backupDir ($Id + $Suffix))
}

function Save-UTBackup {
    <#
    .SYNOPSIS
        Snapshots the current state of everything a tweak is about to change, so undo restores the real
        previous values instead of assumed Windows defaults. The first snapshot is never overwritten.
    #>
    param([Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)]$Tweak)
    # A one-shot action (clearing temp files) changes no state that can be restored, so it gets no
    # snapshot and is never labelled "applied".
    # @($null).Count is 1, not 0, so every list has to be filtered before it is counted.
    $hasState = ((@($Tweak.registry | Where-Object { $_ }).Count -gt 0) -or
                 (@($Tweak.service | Where-Object { $_ }).Count -gt 0) -or
                 (@($Tweak.ScheduledTask | Where-Object { $_ }).Count -gt 0) -or
                 (@($Tweak.UndoScript | Where-Object { $_ }).Count -gt 0))
    if (-not $hasState) { return }
    $file = Get-UTBackupPath -Id $Id
    if (Test-Path -LiteralPath $file) { Write-UTLog "Keeping the existing snapshot for $Id"; return }
    $snap = @{ Id = $Id; Date = (Get-Date -Format 's'); Registry = @(); Service = @(); Task = @() }
    foreach ($r in @($Tweak.registry)) {
        if (-not $r) { continue }
        $cur = Get-UTRegistryValue -Path $r.Path -Name $r.Name
        $snap.Registry += @{ Path = $r.Path; Name = $r.Name; Exists = $cur.Exists; Kind = $cur.Kind; Value = $cur.Value }
    }
    foreach ($s in @($Tweak.service)) {
        if (-not $s) { continue }
        $snap.Service += @{ Name = $s.Name; StartupType = (Get-UTServiceStartup -Name $s.Name) }
    }
    foreach ($t in @($Tweak.ScheduledTask)) {
        if (-not $t) { continue }
        $snap.Task += @{ Name = $t.Name; State = (Get-UTScheduledTaskState -FullName $t.Name) }
    }
    # No snapshot means no reliable undo, so this is fatal for the tweak rather than a warning.
    $snap | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $file -Encoding UTF8 -Force -ErrorAction Stop
    Write-UTLog "Snapshot saved: $file"
}

function Get-UTBackup {
    param([Parameter(Mandatory = $true)][string]$Id)
    $file = Get-UTBackupPath -Id $Id
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    try { return (Get-Content -LiteralPath $file -Raw | ConvertFrom-Json) } catch { return $null }
}

function Remove-UTBackup {
    param([Parameter(Mandatory = $true)][string]$Id)
    foreach ($suffix in '.json', '.state.json') {
        $file = Get-UTBackupPath -Id $Id -Suffix $suffix
        if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
    }
}

function Test-UTBackupExists {
    param([Parameter(Mandatory = $true)][string]$Id)
    return (Test-Path -LiteralPath (Get-UTBackupPath -Id $Id))
}

function Get-UTAppliedTweaks {
    <#
    .SYNOPSIS
        Ids of every tweak that has a snapshot on disk, i.e. everything unknowntweaks has applied and
        not yet undone, even from an earlier session.
    #>
    $ids = @()
    if (-not (Test-Path -LiteralPath $sync.backupDir)) { return $ids }
    foreach ($f in (Get-ChildItem -LiteralPath $sync.backupDir -Filter *.json -File -ErrorAction SilentlyContinue)) {
        if ($f.Name -like '*.state.json') { continue }
        $id = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        if ($sync.configs.tweaks.PSObject.Properties.Name -contains $id) { $ids += $id }
    }
    return @($ids | Sort-Object)
}

function Get-UTScriptState {
    <#
    .SYNOPSIS
        Reads values a tweak's InvokeScript saved for its UndoScript. Returns the whole hashtable when -Key is omitted.
    #>
    param([Parameter(Mandatory = $true)][string]$Id, [string]$Key)
    $file = Get-UTBackupPath -Id $Id -Suffix '.state.json'
    $state = @{}
    if (Test-Path -LiteralPath $file) {
        try {
            $obj = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
            foreach ($p in $obj.PSObject.Properties) { $state[$p.Name] = $p.Value }
        } catch { }
    }
    if ([string]::IsNullOrEmpty($Key)) { return $state }
    if ($state.ContainsKey($Key)) { return $state[$Key] }
    return $null
}

function Save-UTScriptState {
    <#
    .SYNOPSIS
        Records a value an InvokeScript needs to hand to its UndoScript.
    .NOTES
        A key is written once and then kept. Re-applying a tweak that is already applied must not
        overwrite the pre-tweak value with the post-tweak one, or undo would restore the tweak itself.
        Pass -Force for state that is genuinely meant to change on every apply.
    #>
    param([Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)][string]$Key, $Value, [switch]$Force)
    $file = Get-UTBackupPath -Id $Id -Suffix '.state.json'
    $state = Get-UTScriptState -Id $Id
    if ($state.ContainsKey($Key) -and -not $Force) {
        Write-UTLog "Keeping the value recorded for $Id/$Key when it was first applied"
        return
    }
    if ($null -eq $Value) { $state[$Key] = $null } else { $state[$Key] = [string]$Value }
    try { $state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $file -Encoding UTF8 -Force } catch { }
}

#endregion

#region Set-UTFortniteSettings.ps1
function Set-UTFortniteSettings {
    <#
    .SYNOPSIS
        Applies a profile from config/fortnite.json (plus optional hidden keys) to Fortnite's GameUserSettings.ini
        with a key-level merge. Refuses while the game runs, backs up first, clears and restores the read-only flag.
    #>
    param([string]$ProfileName, [string[]]$HiddenKeys = @())
    $fn = Get-UTFortnite
    if (-not $fn.GameIniExists) { throw "Fortnite's GameUserSettings.ini was not found at $($fn.GameIni). Start Fortnite once so it creates the file." }
    if ($fn.GameRunning) { throw 'Fortnite is running. Close it first, the game rewrites this file on exit.' }
    $settings = @{}
    if ($ProfileName) {
        $p = $sync.configs.fortnite.Profiles.$ProfileName
        if (-not $p) { throw "Unknown profile $ProfileName" }
        foreach ($sec in $p.Settings.PSObject.Properties) {
            $settings[$sec.Name] = @{}
            foreach ($kv in $sec.Value.PSObject.Properties) { $settings[$sec.Name][$kv.Name] = [string]$kv.Value }
        }
    }
    foreach ($hid in $HiddenKeys) {
        $h = $sync.configs.fortnite.HiddenKeys.$hid
        if (-not $h) { continue }
        if (-not $settings.ContainsKey($h.Section)) { $settings[$h.Section] = @{} }
        $settings[$h.Section][$h.Key] = [string]$h.Value
    }
    if ($settings.Count -eq 0) { Write-UTLog 'Nothing selected for Fortnite'; return }
    # Clear read-only first: a copy inherits the attribute, and a read-only backup would restore a file
    # the game can no longer write, which silently stops it saving video settings.
    $item = Get-Item -LiteralPath $fn.GameIni
    $wasReadOnly = $item.IsReadOnly
    if ($wasReadOnly) { $item.IsReadOnly = $false }
    Backup-UTFile -Path $fn.GameIni
    try {
        $n = Set-UTIniValues -Path $fn.GameIni -Settings $settings
        $label = 'hidden keys only'
        if ($ProfileName) { $label = $sync.configs.fortnite.Profiles.$ProfileName.Content }
        Write-UTLog ("Fortnite settings written: {0} ({1} key(s) changed). Start the game to see them." -f $label, $n) -Level Ok
    } finally {
        if ($wasReadOnly) { (Get-Item -LiteralPath $fn.GameIni).IsReadOnly = $true; Write-UTLog 'The file was read-only before; the flag was restored' }
    }
}

function Restore-UTFortniteSettings {
    $fn = Get-UTFortnite
    $orig = $fn.GameIni + '.unknowntweaks.original'
    if (-not (Test-Path -LiteralPath $orig)) { throw 'No original backup exists (nothing was changed by unknowntweaks yet)' }
    if ($fn.GameRunning) { throw 'Fortnite is running. Close it first.' }
    $item = Get-Item -LiteralPath $fn.GameIni -ErrorAction SilentlyContinue
    if ($item -and $item.IsReadOnly) { $item.IsReadOnly = $false }
    Copy-Item -LiteralPath $orig -Destination $fn.GameIni -Force
    (Get-Item -LiteralPath $fn.GameIni).IsReadOnly = $false
    Write-UTLog 'Fortnite GameUserSettings.ini restored from the original backup, and left writable so the game can save settings' -Level Ok
}

function Set-UTFortniteReadOnly {
    param([bool]$ReadOnly)
    $fn = Get-UTFortnite
    if (-not $fn.GameIniExists) { throw 'GameUserSettings.ini not found' }
    (Get-Item -LiteralPath $fn.GameIni).IsReadOnly = $ReadOnly
    if ($ReadOnly) { Write-UTLog 'GameUserSettings.ini is now read-only: in-game Video changes will NOT persist until you unlock it' -Level Warn }
    else { Write-UTLog 'GameUserSettings.ini is writable again' -Level Ok }
}

function Clear-UTShaderCache {
    <#
    .SYNOPSIS
        Deletes the NVIDIA / AMD DirectX shader caches. Epic's own DX12 stutter fix. Only with game and launcher closed.
    #>
    $fn = Get-UTFortnite
    if ($fn.GameRunning) { throw 'Close Fortnite first' }
    if ($fn.LauncherRunning) { throw 'Close the Epic Games Launcher too: it holds shader cache files open' }
    $dirs = @(
        (Join-Path $env:LOCALAPPDATA 'NVIDIA\DXCache'), (Join-Path $env:LOCALAPPDATA 'NVIDIA\GLCache'), (Join-Path $env:ProgramData 'NVIDIA Corporation\NV_Cache'),
        (Join-Path $env:LOCALAPPDATA 'AMD\DxCache'), (Join-Path $env:LOCALAPPDATA 'AMD\DxcCache'), (Join-Path $env:LOCALAPPDATA 'AMD\GLCache'), (Join-Path $env:LOCALAPPDATA 'AMD\VkCache')
    )
    $freed = 0
    foreach ($d in $dirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        $size = (Get-ChildItem -LiteralPath $d -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        $freed += [int64]$size
        Write-UTLog ("Cleared {0} ({1:N0} MB)" -f $d, ($size / 1MB))
    }
    Write-UTLog ("Shader caches cleared, {0:N0} MB freed. The first match will stutter while shaders rebuild, then it settles." -f ($freed / 1MB)) -Level Ok
}

#endregion

#region Set-UTIniValue.ps1
function Read-UTIniFile {
    <#
    .SYNOPSIS
        Parses an Unreal-style INI into an ordered structure: Sections (name -> ordered key/value list) plus raw lines.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)
    $result = @{ Path = $Path; Exists = $false; HasBom = $false; Lines = @(); Sections = @{} }
    if (-not (Test-Path -LiteralPath $Path)) { return $result }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $result.Exists = $true
    $result.HasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $result.Lines = @([System.IO.File]::ReadAllLines($Path))
    $current = ''
    foreach ($line in $result.Lines) {
        if ($line -match '^\s*\[(.+)\]\s*$') { $current = $Matches[1]; if (-not $result.Sections.ContainsKey($current)) { $result.Sections[$current] = @{} }; continue }
        if ($line -match '^\s*([^=;#\s][^=]*?)\s*=(.*)$') {
            if (-not $result.Sections.ContainsKey($current)) { $result.Sections[$current] = @{} }
            $result.Sections[$current][$Matches[1]] = $Matches[2]
        }
    }
    return $result
}

function Get-UTIniValue {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Section, [Parameter(Mandatory = $true)][string]$Key)
    $ini = Read-UTIniFile -Path $Path
    foreach ($s in $ini.Sections.Keys) {
        if ($s -ne $Section) { continue }
        foreach ($k in $ini.Sections[$s].Keys) { if ($k -eq $Key) { return $ini.Sections[$s][$k] } }
    }
    return $null
}

function Set-UTIniValues {
    <#
    .SYNOPSIS
        Key-level merge into an INI file: existing keys are replaced in place, missing keys are appended to their
        section, missing sections are created at the end. Unknown keys, comments, BOM and CRLF are preserved.
    .PARAMETER Settings
        Hashtable: section name -> hashtable of key -> value (values are written verbatim).
    #>
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][hashtable]$Settings)
    $ini = Read-UTIniFile -Path $Path
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($l in $ini.Lines) { $lines.Add($l) }
    $changed = 0

    foreach ($section in $Settings.Keys) {
        $pairs = $Settings[$section]
        # locate section bounds
        $start = -1; $end = $lines.Count
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*\[(.+)\]\s*$') {
                if ($start -ge 0) { $end = $i; break }
                if ($Matches[1] -eq $section) { $start = $i }
            }
        }
        if ($start -lt 0) {
            if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -ne '') { $lines.Add('') }
            $lines.Add("[$section]")
            $start = $lines.Count - 1
            $end = $lines.Count
        }
        foreach ($key in $pairs.Keys) {
            $value = [string]$pairs[$key]
            $found = $false
            # A key can appear more than once in a hand-edited file. Unreal's config parser keeps the last
            # occurrence, so every one has to be rewritten or the file would still hold the old value.
            for ($i = $start + 1; $i -lt $end; $i++) {
                if ($lines[$i] -match '^\s*([^=;#\s][^=]*?)\s*=(.*)$' -and $Matches[1] -eq $key) {
                    if ($lines[$i] -ne "$key=$value") { $lines[$i] = "$key=$value"; $changed++ }
                    $found = $true
                }
            }
            if (-not $found) {
                # insert before trailing blank lines of the section so the file stays tidy
                $insertAt = $end
                while ($insertAt -gt ($start + 1) -and $lines[$insertAt - 1].Trim() -eq '') { $insertAt-- }
                $lines.Insert($insertAt, "$key=$value")
                $end++
                $changed++
            }
        }
    }
    $enc = New-Object System.Text.UTF8Encoding($ini.HasBom)
    $text = ($lines -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($Path, $text, $enc)
    return $changed
}

#endregion

#region Set-UTLaunchArgs.ps1
function Find-UTLaunchArgsKey {
    <#
    .SYNOPSIS
        Locates the Epic launcher's per-game "Additional Command Line Arguments" entry for Fortnite in its settings file.
    .DESCRIPTION
        Read off a live Epic Games Launcher 20.2.6 install (see docs/DECISIONS.md), the layout in
        %LOCALAPPDATA%\EpicGamesLauncher\Saved\Config\WindowsEditor\GameUserSettings.ini is:

            [<AccountId>_Settings]
            fn:<CatalogItemId>:Fortnite_AdditionalCommandsEnabled=True
            fn:<CatalogItemId>:Fortnite_AdditionalCommands=-NOSPLASH

        The section is the signed-in Epic account id; the key is the catalog triple the launcher uses
        everywhere else (NamespaceId:ItemId:ArtifactId, i.e. Get-UTFortnite's LauncherKeyPrefix)
        suffixed with _AdditionalCommands, and the tick box next to the text field is the same key
        plus "Enabled".

        Order of preference: (1) a location learned earlier by the probe (saved state), (2) this
        game's *_AdditionalCommands key already present in the file, (3) the layout above.
        Source is 'unknown' when neither the account id nor the catalog triple could be determined;
        callers must refuse to write in that case rather than invent a section.
    #>
    param([Parameter(Mandatory = $true)]$Fortnite)
    $res = [pscustomobject]@{ Section = ''; Key = ''; Source = 'known'; Current = $null; Enabled = $null; File = $Fortnite.LauncherIni; EnableKey = '' }
    # If the probe learned the real location on this machine, that file wins over the newest-timestamp guess.
    $learnedFile = Get-UTScriptState -Id UTLaunchArgs -Key File
    if ($learnedFile -and (Test-Path -LiteralPath $learnedFile)) { $res.File = $learnedFile }
    $ini = $null
    if (Test-Path -LiteralPath $res.File) { $ini = Read-UTIniFile -Path $res.File }
    $learnedSection = Get-UTScriptState -Id UTLaunchArgs -Key Section
    $learnedKey = Get-UTScriptState -Id UTLaunchArgs -Key Key
    $wanted = ''
    if ($Fortnite.LauncherKeyPrefix) { $wanted = $Fortnite.LauncherKeyPrefix + '_AdditionalCommands' }
    if ($learnedSection -and $learnedKey) {
        $res.Section = $learnedSection; $res.Key = $learnedKey; $res.Source = 'probe'
    } elseif ($ini) {
        # What the launcher has already written on this machine beats any name we construct.
        foreach ($s in $ini.Sections.Keys) {
            foreach ($k in $ini.Sections[$s].Keys) {
                if ($k -notlike '*_AdditionalCommands') { continue }
                # Every other Epic game has its own key in the same section, so match this game only.
                if ($wanted) { if ($k -ne $wanted) { continue } } elseif ($k -notmatch 'Fortnite') { continue }
                $res.Section = $s; $res.Key = $k; $res.Source = 'existing'; break
            }
            if ($res.Source -eq 'existing') { break }
        }
    }
    if (-not $res.Key) { $res.Key = $wanted }
    if (-not $res.Section -and $Fortnite.AccountId) { $res.Section = $Fortnite.AccountId + '_Settings' }
    if (-not $res.Key -or -not $res.Section) { $res.Source = 'unknown'; return $res }

    if ($res.Source -eq 'probe') {
        $learnedEnable = Get-UTScriptState -Id UTLaunchArgs -Key EnableKey
        if ($learnedEnable) { $res.EnableKey = $learnedEnable }
    }
    if (-not $res.EnableKey) { $res.EnableKey = $res.Key + 'Enabled' }
    if ($ini -and $ini.Sections.ContainsKey($res.Section)) {
        foreach ($k in $ini.Sections[$res.Section].Keys) {
            if ($k -eq $res.Key) { $res.Current = $ini.Sections[$res.Section][$k] }
            if ($k -eq $res.EnableKey) { $res.Enabled = $ini.Sections[$res.Section][$k] }
        }
    }
    return $res
}

function Set-UTLaunchArgs {
    <#
    .SYNOPSIS
        Writes Fortnite's launch arguments into the Epic Games Launcher settings file, closing the launcher first
        (it overwrites the file on exit) and restarting it afterwards if it was running.
    #>
    param([string]$Arguments = '')
    $fn = Get-UTFortnite
    if ($fn.GameRunning) { throw 'Fortnite is running. Close it first.' }
    $loc = Find-UTLaunchArgsKey -Fortnite $fn
    if ($loc.Source -eq 'unknown') {
        throw 'The launcher entry for Fortnite could not be identified: neither your Epic account id nor the game''s catalog id could be read. Sign in to the Epic Games Launcher once and open it, then try again, or use "Probe launcher key".'
    }
    $wasRunning = Stop-UTEpicLauncher
    try {
        if (Test-Path -LiteralPath $loc.File) { Backup-UTFile -Path $loc.File }
        else {
            $dir = Split-Path -Path $loc.File -Parent
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        }
        # The text box and its tick box are separate keys: writing arguments without enabling them means
        # the launcher ignores them entirely.
        $pairs = @{ $loc.Key = $Arguments; $loc.EnableKey = $(if ($Arguments) { 'True' } else { 'False' }) }
        $settings = @{ $loc.Section = $pairs }
        $n = Set-UTIniValues -Path $loc.File -Settings $settings
        Save-UTScriptState -Id UTLaunchArgs -Key LastWritten -Value $Arguments -Force
        Write-UTLog ("Launch arguments written to [{0}] {1} = '{2}' ({3}, {4} change(s)) in {5}" -f $loc.Section, $loc.Key, $Arguments, $loc.Source, $n, $loc.File) -Level Ok
        Write-UTLog 'Check it in the launcher: profile icon > Settings > Manage Games > Fortnite. If Additional Command Line Arguments is empty or unticked, your launcher build stores this somewhere else: run "Probe launcher key" once and this tool will learn the real location.'
    } finally {
        if ($wasRunning) { Start-UTEpicLauncher }
    }
}
function Start-UTLaunchArgsProbe {
    <#
    .SYNOPSIS
        Step 1 of the probe: snapshot the launcher settings file so step 2 can diff it after the user types a marker.
    #>
    $fn = Get-UTFortnite
    if (-not $fn.LauncherIniExists) { throw "Launcher settings file not found at $($fn.LauncherIni). Open the launcher once, then retry." }
    $snap = Join-Path $sync.backupDir 'launcher-probe-before.ini'
    Copy-Item -LiteralPath $fn.LauncherIni -Destination $snap -Force
    Save-UTScriptState -Id UTLaunchArgs -Key ProbeFile -Value $fn.LauncherIni
    Write-UTLog 'Probe armed. Now in the Epic Games Launcher: profile icon > Settings > Manage Games > Fortnite > tick Additional Command Line Arguments and type exactly  -UTPROBE12345  then fully EXIT the launcher (tray icon > Exit). Then click Finish probe.' -Level Warn
}

function Complete-UTLaunchArgsProbe {
    <#
    .SYNOPSIS
        Step 2: find which section/key now contains the marker and remember it for future writes.
    #>
    $fn = Get-UTFortnite
    $candidates = @()
    $cfg = Join-Path $env:LOCALAPPDATA 'EpicGamesLauncher\Saved\Config'
    foreach ($f in (Get-ChildItem -LiteralPath $cfg -Recurse -Filter *.ini -ErrorAction SilentlyContinue)) { $candidates += $f.FullName }
    $hit = $null
    foreach ($file in $candidates) {
        $ini = Read-UTIniFile -Path $file
        foreach ($s in $ini.Sections.Keys) {
            foreach ($k in $ini.Sections[$s].Keys) {
                if ($ini.Sections[$s][$k] -match 'UTPROBE12345') { $hit = [pscustomobject]@{ File = $file; Section = $s; Key = $k; Others = @($ini.Sections[$s].Keys) } }
            }
        }
    }
    if (-not $hit) {
        Write-UTLog 'Marker not found in any launcher INI. Either the launcher is still running (exit it completely), the checkbox was not ticked, or the launcher stores this setting elsewhere (a web-cache store). Check the log folder of this tool for details.' -Level Warn
        return
    }
    Save-UTScriptState -Id UTLaunchArgs -Key Section -Value $hit.Section -Force
    Save-UTScriptState -Id UTLaunchArgs -Key Key -Value $hit.Key -Force
    Save-UTScriptState -Id UTLaunchArgs -Key File -Value $hit.File -Force
    # The boolean the launcher writes for the tick box lives in the same section.
    $enableKey = @($hit.Others | Where-Object { $_ -ne $hit.Key -and $_ -match 'CommandLine|Additional' -and $_ -match 'Enable|Use|Custom|^b' }) | Select-Object -First 1
    if ($enableKey) { Save-UTScriptState -Id UTLaunchArgs -Key EnableKey -Value $enableKey -Force; Write-UTLog "Its tick box key is $enableKey" -Level Ok }
    Write-UTLog ("Learned: launcher stores Fortnite launch arguments in {0} under [{1}] {2}. Other keys in that section: {3}" -f $hit.File, $hit.Section, $hit.Key, ($hit.Others -join ', ')) -Level Ok
    Write-UTLog 'Please report this section/key on the project page so it can be hard-coded for everyone.' -Level Ok
}

#endregion

#region Set-UTNvProfile.ps1
function Get-UTNvProfileIds {
    <#
    .SYNOPSIS
        The setting ids and values of one preset from config/nvprofile.json, parsed from hex.
    #>
    param([Parameter(Mandatory = $true)][string]$PresetName)
    $p = $sync.configs.nvprofile.Presets.$PresetName
    if (-not $p) { throw "Unknown NVIDIA profile preset $PresetName" }
    $ids = New-Object System.Collections.Generic.List[uint32]
    $values = New-Object System.Collections.Generic.List[uint32]
    foreach ($s in @($p.Settings)) {
        $ids.Add([Convert]::ToUInt32([string]$s.Id, 16))
        $values.Add([Convert]::ToUInt32([string]$s.Value, 16))
    }
    return [pscustomobject]@{ Ids = $ids.ToArray(); Values = $values.ToArray(); Settings = @($p.Settings); Content = [string]$p.Content }
}

function Get-UTNvProfileState {
    <#
    .SYNOPSIS
        What the driver currently holds for the settings this tool writes, and how many of them already
        match the given preset. Read-only.
    .DESCRIPTION
        NVIDIA ships its own Fortnite profile with most of these already set, so "is this the driver
        default" tells the user nothing useful. What does is whether the values on disk are the ones a
        preset would write, which is how the tab reports whether a preset is live.
    #>
    param([string]$PresetName = 'Potato')
    $out = [pscustomobject]@{ Available = $false; Application = ''; Preset = $PresetName; Matching = 0; Total = 0; Lines = @() }
    if (-not ('UT.NativeV1.NvApi' -as [type])) { return $out }
    if (-not [UT.NativeV1.NvApi]::IsAvailable()) { return $out }
    $cfg = $sync.configs.nvprofile
    $out.Available = $true
    $out.Application = [string]$cfg.Application
    $names = @{}; $wanted = @{}
    foreach ($preset in $cfg.Presets.PSObject.Properties) {
        foreach ($s in @($preset.Value.Settings)) { $names[[string]$s.Id] = [string]$s.Name }
    }
    if ($cfg.Presets.$PresetName) {
        foreach ($s in @($cfg.Presets.$PresetName.Settings)) { $wanted[[string]$s.Id] = [Convert]::ToUInt32([string]$s.Value, 16) }
    }
    $ids = @($names.Keys | ForEach-Object { [Convert]::ToUInt32($_, 16) })
    $raw = [UT.NativeV1.NvApi]::DrsRead($cfg.Application, $ids)
    if (-not $raw) { return $out }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($entry in ($raw -split ';')) {
        $parts = $entry -split ':'
        if ($parts.Count -lt 3) { continue }
        $id = [string]$parts[0]
        $value = [uint32]$parts[1]
        $name = [string]$names[$id]
        if (-not $name) { $name = $id }
        $mark = ''
        if ($wanted.ContainsKey($id)) {
            $out.Total++
            if ($wanted[$id] -eq $value) { $out.Matching++; $mark = "matches $PresetName" } else { $mark = "preset wants 0x{0:X8}" -f $wanted[$id] }
        }
        $lines.Add(('{0,-52} {1,-12} {2}' -f $name, ('0x' + $value.ToString('X8')), $mark))
    }
    $out.Lines = $lines.ToArray()
    return $out
}

function Set-UTNvProfile {
    <#
    .SYNOPSIS
        Writes a preset into the NVIDIA driver profile for Fortnite's executable.
    .DESCRIPTION
        Uses the driver's own settings repository through NVAPI - the same database NVIDIA Control
        Panel writes - so no third-party tool is downloaded or run. Only the settings named in
        config/nvprofile.json are touched, and Restore-UTNvProfile puts each of them back to the
        driver default. Nothing is injected into the game and no game file is changed.
    #>
    param([Parameter(Mandatory = $true)][string]$PresetName)
    if (-not ('UT.NativeV1.NvApi' -as [type]) -or -not [UT.NativeV1.NvApi]::IsAvailable()) {
        throw 'This PC has no NVIDIA driver, so there is no NVIDIA profile to write. AMD and Intel expose their own equivalents in their control panels.'
    }
    $cfg = $sync.configs.nvprofile
    $p = Get-UTNvProfileIds -PresetName $PresetName
    $r = [UT.NativeV1.NvApi]::DrsApply($cfg.Application, $cfg.ProfileName, $p.Ids, $p.Values)
    if ($r -ne 'ok') { throw ("the NVIDIA driver refused the profile write: {0}" -f $r) }
    foreach ($s in $p.Settings) { Write-UTLog ('  {0} -> {1}' -f $s.Name, $s.Means) }
    Write-UTLog ("NVIDIA profile for {0}: {1} ({2} setting(s)). Restart Fortnite for it to take effect." -f $cfg.Application, $p.Content, $p.Ids.Count) -Level Ok
}

function Restore-UTNvProfile {
    <#
    .SYNOPSIS
        Puts every setting this tool can write back to the driver default for Fortnite's executable.
    #>
    if (-not ('UT.NativeV1.NvApi' -as [type]) -or -not [UT.NativeV1.NvApi]::IsAvailable()) { throw 'No NVIDIA driver on this PC' }
    $cfg = $sync.configs.nvprofile
    $all = @{}
    foreach ($preset in $cfg.Presets.PSObject.Properties) {
        foreach ($s in @($preset.Value.Settings)) { $all[[string]$s.Id] = $true }
    }
    $ids = @($all.Keys | ForEach-Object { [Convert]::ToUInt32($_, 16) })
    $r = [UT.NativeV1.NvApi]::DrsRestore($cfg.Application, $ids)
    if ($r -ne 'ok') { throw ("the NVIDIA driver refused the restore: {0}" -f $r) }
    Write-UTLog ("NVIDIA profile for {0} restored to driver defaults ({1} setting(s))" -f $cfg.Application, $ids.Count) -Level Ok
}

#endregion

#region Set-UTRegistry.ps1
function ConvertTo-UTRegistryValue {
    <#
    .SYNOPSIS
        Converts the string form used in tweaks.json / backups into the .NET value Set-ItemProperty expects.
    #>
    param([string]$Type, [string]$Value)
    switch ($Type) {
        'DWord' {
            # DWord values above Int32.MaxValue (e.g. 4294967295) must be passed as the equivalent negative Int32
            $u = [uint32]0
            if ([uint32]::TryParse($Value, [ref]$u)) { return [BitConverter]::ToInt32([BitConverter]::GetBytes($u), 0) }
            return [int]$Value
        }
        'QWord'       { return [int64]$Value }
        'Binary'      { return [byte[]](@($Value -split ',' | Where-Object { $_.Trim() } | ForEach-Object { [Convert]::ToByte($_.Trim(), 16) })) }
        'MultiString' { return [string[]](@($Value -split '\|')) }
        default       { return [string]$Value }
    }
}

function ConvertFrom-UTRegistryValue {
    <#
    .SYNOPSIS
        Serialises a value read from the registry into the string form used by backups.
    #>
    param($Raw, [string]$Kind)
    if ($null -eq $Raw) { return '' }
    switch ($Kind) {
        'DWord'       { return ([BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$Raw), 0)).ToString() }
        'QWord'       { return ([int64]$Raw).ToString() }
        'Binary'      { return ((@($Raw) | ForEach-Object { '{0:X2}' -f $_ }) -join ',') }
        'MultiString' { return ((@($Raw)) -join '|') }
        default       { return [string]$Raw }
    }
}

function Get-UTRegistryValue {
    <#
    .SYNOPSIS
        Reads a registry value with its kind, reporting whether it exists at all (needed for undo).
    #>
    param([string]$Path, [string]$Name)
    $result = @{ Exists = $false; Kind = ''; Value = '' }
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $result }
        $key = Get-Item -LiteralPath $Path -ErrorAction Stop
        $names = @($key.GetValueNames())
        $match = $names | Where-Object { $_ -eq $Name } | Select-Object -First 1
        if ($null -eq $match) { return $result }
        $kind = [string]$key.GetValueKind($match)
        $raw = $key.GetValue($match, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $result.Exists = $true
        $result.Kind = $kind
        $result.Value = ConvertFrom-UTRegistryValue -Raw $raw -Kind $kind
    } catch { }
    return $result
}

function Set-UTRegistryValueDirect {
    <#
    .SYNOPSIS
        Writes one value through Microsoft.Win32.Registry instead of the PowerShell provider.
    .DESCRIPTION
        The registry provider reuses key handles it opened earlier in the session, so a key that was
        first read through a read-only handle can refuse a later write with "Requested registry access
        is not allowed" even though the ACL grants FullControl. Opening our own writable handle side
        steps that, and fails with a genuine access error when the ACL really does say no.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Type,
        $Value
    )
    # Plain string work, not a regex: the hive prefix is a fixed 6 characters and a backslash class
    # in a pattern is one more thing to get wrong.
    $hive = $null
    if ($Path.StartsWith('HKLM:' + [char]92, [System.StringComparison]::OrdinalIgnoreCase))      { $hive = [Microsoft.Win32.Registry]::LocalMachine }
    elseif ($Path.StartsWith('HKCU:' + [char]92, [System.StringComparison]::OrdinalIgnoreCase)) { $hive = [Microsoft.Win32.Registry]::CurrentUser }
    else { throw "unsupported hive in $Path" }
    $sub = $Path.Substring(6)
    $key = $hive.OpenSubKey($sub, $true)
    if (-not $key) { $key = $hive.CreateSubKey($sub) }
    if (-not $key) { throw "could not open $Path for writing" }
    # An array loses its element type crossing an untyped parameter boundary: a byte[] arrives as
    # Object[] and SetValue then refuses it. Put the type back before handing it over.
    $kind = [Microsoft.Win32.RegistryValueKind]$Type
    if ($kind -eq [Microsoft.Win32.RegistryValueKind]::Binary) { $Value = [byte[]]$Value }
    elseif ($kind -eq [Microsoft.Win32.RegistryValueKind]::MultiString) { $Value = [string[]]$Value }
    try { $key.SetValue($Name, $Value, $kind) }
    finally { $key.Close() }
}

function Set-UTRegistry {
    <#
    .SYNOPSIS
        Creates the key if needed and sets (or removes, for '<RemoveEntry>') a registry value.
    .OUTPUTS
        $true when the change was made, $false when it failed. The caller must not report a tweak as
        applied when this returns $false.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Type = 'DWord',
        [string]$Value = ''
    )
    try {
        if ($Value -eq '<RemoveEntry>') {
            if (Test-Path -LiteralPath $Path) {
                Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction SilentlyContinue
            }
            Write-UTLog "Removed $Path\$Name"
            return $true
        }
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }
        if ([string]::IsNullOrEmpty($Type)) { $Type = 'String' }
        $converted = ConvertTo-UTRegistryValue -Type $Type -Value $Value
        try {
            Set-ItemProperty -LiteralPath $Path -Name $Name -Type $Type -Value $converted -Force -ErrorAction Stop
        } catch [System.Security.SecurityException] {
            Set-UTRegistryValueDirect -Path $Path -Name $Name -Type $Type -Value $converted
        } catch [System.UnauthorizedAccessException] {
            Set-UTRegistryValueDirect -Path $Path -Name $Name -Type $Type -Value $converted
        }
        Write-UTLog "Set $Path\$Name = $Value ($Type)"
        return $true
    } catch [System.Security.SecurityException] {
        # Keep the real message: "access denied" on its own is not enough to tell a locked-down
        # policy key apart from a hive that belongs to another account.
        Write-UTLog "Access denied writing $Path\$Name : $($_.Exception.Message)" -Level Error
        return $false
    } catch [System.UnauthorizedAccessException] {
        Write-UTLog "Access denied writing $Path\$Name : $($_.Exception.Message)" -Level Error
        return $false
    } catch {
        Write-UTLog "Failed to write $Path\$Name : $($_.Exception.GetType().Name): $($_.Exception.Message)" -Level Error
        return $false
    }
}

#endregion

#region Set-UTScheduledTask.ps1
function Get-UTScheduledTaskParts {
    param([Parameter(Mandatory = $true)][string]$FullName)
    $leaf = Split-Path -Path $FullName -Leaf
    $folder = Split-Path -Path $FullName -Parent
    if ([string]::IsNullOrEmpty($folder)) { $folder = '\' }
    if (-not $folder.StartsWith('\')) { $folder = '\' + $folder }
    if (-not $folder.EndsWith('\')) { $folder = $folder + '\' }
    return @{ Path = $folder; Name = $leaf }
}

function Get-UTScheduledTaskState {
    <#
    .SYNOPSIS
        Returns 'Enabled', 'Disabled', or $null when the task does not exist on this build.
    #>
    param([Parameter(Mandatory = $true)][string]$FullName)
    $parts = Get-UTScheduledTaskParts -FullName $FullName
    $task = Get-ScheduledTask -TaskPath $parts.Path -TaskName $parts.Name -ErrorAction SilentlyContinue
    if (-not $task) { return $null }
    if ([string]$task.State -eq 'Disabled') { return 'Disabled' }
    return 'Enabled'
}

function Set-UTScheduledTask {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('Enabled', 'Disabled')][string]$State
    )
    $parts = Get-UTScheduledTaskParts -FullName $Name
    $task = Get-ScheduledTask -TaskPath $parts.Path -TaskName $parts.Name -ErrorAction SilentlyContinue
    if (-not $task) { Write-UTLog "Task $($parts.Name) not present on this Windows build, skipped"; return $true }
    try {
        if ($State -eq 'Disabled') { $task | Disable-ScheduledTask -ErrorAction Stop | Out-Null }
        else { $task | Enable-ScheduledTask -ErrorAction Stop | Out-Null }
        Write-UTLog "Task $($parts.Name) -> $State"
        return $true
    } catch {
        Write-UTLog "Task $($parts.Name) could not be changed: $($_.Exception.Message)" -Level Error
        return $false
    }
}

#endregion

#region Set-UTService.ps1
function Get-UTServiceStartup {
    <#
    .SYNOPSIS
        Returns Automatic / AutomaticDelayedStart / Manual / Disabled / Boot / System, or $null if the service is missing.
    #>
    param([Parameter(Mandatory = $true)][string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { return $null }
    $start = [string]$svc.StartType
    if ($start -eq 'Automatic') {
        $delayed = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" -Name DelayedAutostart -ErrorAction SilentlyContinue).DelayedAutostart
        if ($delayed -eq 1) { $start = 'AutomaticDelayedStart' }
    }
    return $start
}

function Set-UTService {
    <#
    .SYNOPSIS
        Changes a service startup type. Handles Automatic (Delayed Start) on Windows PowerShell 5.1 via sc.exe.
    .OUTPUTS
        $true when the startup type is now what was asked for (including a service that does not exist on
        this build, which is a normal skip), $false when the change failed.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$StartupType
    )
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { Write-UTLog "Service $Name not present on this Windows build, skipped" -Level Warn; return $true }
    try {
        $current = Get-UTServiceStartup -Name $Name
        if ($current -eq $StartupType) { Write-UTLog "Service $Name already $StartupType"; return $true }
        if ($StartupType -eq 'AutomaticDelayedStart') {
            $out = & sc.exe config $Name start= delayed-auto 2>&1
            if ($LASTEXITCODE -ne 0) { throw "sc.exe config failed: $out" }
        } elseif ($StartupType -eq 'Automatic' -and $current -eq 'AutomaticDelayedStart') {
            # Set-Service writes the start type but not the delayed-auto flag, so a service that was
            # "Automatic (Delayed Start)" would still read back delayed and the undo would not round
            # trip. sc.exe owns that flag; start= auto and start= delayed-auto are distinct values.
            $out = & sc.exe config $Name start= auto 2>&1
            if ($LASTEXITCODE -ne 0) { throw "sc.exe config failed: $out" }
        } else {
            Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop
        }
        # Stopping a running service also stops whatever depends on it, which is not recorded anywhere,
        # so leave it running: the new startup type takes effect at the next boot either way.
        if ($StartupType -eq 'Disabled' -and $svc.Status -eq 'Running') {
            Write-UTLog "Service $Name is set to Disabled but is still running; it stays stopped from the next reboot"
        }
        Write-UTLog "Service $Name : $current -> $StartupType"
        return $true
    } catch {
        Write-UTLog "Service $Name could not be changed: $($_.Exception.Message)" -Level Error
        return $false
    }
}

#endregion

#region Set-UTStretched.ps1
function Get-UTStretchedStatePath { return (Join-Path $sync.backupDir 'stretched-state.json') }

function Test-UTStretchedState { return (Test-Path -LiteralPath (Get-UTStretchedStatePath)) }

function Get-UTDisplayState {
    <#
    .SYNOPSIS
        Current desktop mode, the modes Windows lists, the scaling the active path uses, NVIDIA availability
        and the monitor devices, so the STRETCHED tab can say what will happen before it happens.
    #>
    $s = [pscustomobject]@{ Width = 0; Height = 0; Hz = 0; Scaling = 0; ScalingName = 'unknown'; Modes = @(); Nvidia = $false; Monitors = @(); Active = (Test-UTStretchedState) }
    if (-not ('UT.NativeV1.Display' -as [type])) { return $s }
    try {
        $cur = [UT.NativeV1.Display]::GetCurrent()
        $s.Width = $cur.Width; $s.Height = $cur.Height; $s.Hz = $cur.Hz
        $s.Modes = @([UT.NativeV1.Display]::EnumModes() | ForEach-Object { [pscustomobject]@{ Width = $_.Width; Height = $_.Height; Hz = $_.Hz } })
        $s.Scaling = [int][UT.NativeV1.Display]::GetScaling()
        $s.ScalingName = switch ($s.Scaling) { 1 { 'identity' } 2 { 'centered' } 3 { 'stretched' } 4 { 'aspect ratio' } 5 { 'custom' } 128 { 'preferred' } default { 'unknown' } }
        $s.Nvidia = [UT.NativeV1.NvApi]::IsAvailable()
    } catch { }
    $s.Monitors = @(Get-UTMonitorDevices)
    return $s
}

function Get-UTMonitorDevices {
    @(Get-PnpDevice -Class Monitor -ErrorAction SilentlyContinue | Where-Object { $_.Present } |
      ForEach-Object { [pscustomobject]@{ InstanceId = [string]$_.InstanceId; Name = [string]$_.FriendlyName; Status = [string]$_.Status } })
}

function Set-UTMonitorDevice {
    param([Parameter(Mandatory = $true)][string]$InstanceId, [Parameter(Mandatory = $true)][bool]$Enable)
    $verb = '/disable-device'
    if ($Enable) { $verb = '/enable-device' }
    $r = Invoke-UTNative -FilePath 'pnputil.exe' -Arguments @($verb, $InstanceId)
    if ($r.ExitCode -ne 0 -and $r.ExitCode -ne 259) { throw ("pnputil {0} failed (exit {1}): {2}" -f $verb, $r.ExitCode, $r.Output.Trim()) }
    Write-UTLog ("monitor device {0}: {1}" -f $InstanceId, $(if ($Enable) { 'enabled' } else { 'disabled' }))
}

function Test-UTDisplayMode {
    param([int]$Width, [int]$Height)
    foreach ($m in [UT.NativeV1.Display]::EnumModes()) { if ($m.Width -eq $Width -and $m.Height -eq $Height) { return $true } }
    return $false
}

function Get-UTMaxRefresh {
    <#
    .SYNOPSIS
        The highest refresh rate this panel offers at any resolution.
    .DESCRIPTION
        A stretched mode is worth nothing at 60 Hz on a 240 Hz monitor, and a custom mode is timed by
        the driver from whatever rate is asked for, so the panel's maximum is what to ask for.
    #>
    $rates = @([UT.NativeV1.Display]::EnumModes() | ForEach-Object { [int]$_.Hz })
    if ($rates.Count -eq 0) { return 60 }
    return ($rates | Sort-Object -Descending)[0]
}

function Get-UTBestRefresh {
    <#
    .SYNOPSIS
        The highest refresh Windows lists for this exact mode, falling back to the panel's maximum.
    #>
    param([int]$Width, [int]$Height)
    $rates = @([UT.NativeV1.Display]::EnumModes() | Where-Object { $_.Width -eq $Width -and $_.Height -eq $Height } | ForEach-Object { [int]$_.Hz })
    if ($rates.Count -gt 0) { return ($rates | Sort-Object -Descending)[0] }
    return (Get-UTMaxRefresh)
}

function Get-UTStretchedPresets {
    <#
    .SYNOPSIS
        The stretched modes worth offering on this monitor: every ratio from config/stretched.json at
        every sensible vertical resolution, with whether Windows already lists it and whether VALORANT
        will take it.
    .DESCRIPTION
        Heights are 1080 (fewer pixels, the reason most people do this) plus the panel's own height
        when it is taller, so a 1440p or 4K owner can stretch without dropping to 1080p. Widths are
        rounded to an even number because odd widths upset some timings.

        The VALORANT column is three-state, because black bars have two different causes. Riot
        documents support for 4:3, 5:4, 16:9, 16:10 and 21:9; those ratios fill. A ratio outside that
        set is not refused, and plenty of players use 1680x1080, but whether it fills rests entirely
        on the driver scaler, so it is labelled rather than promised. Anything at or wider than 16:9
        is pillarboxed by the game itself on purpose and is never generated here. Below the game's
        1280x720 minimum nothing works at all.
    #>
    $cur = [UT.NativeV1.Display]::GetCurrent()
    $heights = New-Object System.Collections.Generic.List[int]
    foreach ($h in @(1080, [int]$cur.Height)) { if ($h -ge 720 -and -not $heights.Contains($h)) { [void]$heights.Add($h) } }
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($h in ($heights | Sort-Object)) {
        foreach ($r in @($sync.configs.stretched.Ratios)) {
            $w = [int]([math]::Round(($h * [double]$r.Ratio) / 2.0) * 2)
            if ($w -ge [int]$cur.Width) { continue }
            $fill = 'fills'
            if ($w -lt 1280 -or $h -lt 720) { $fill = 'too small' }
            elseif (-not [bool]$r.ValorantRatio) { $fill = 'non-standard' }
            $out.Add([pscustomobject]@{
                Width = $w; Height = $h; Tag = ('{0}x{1}' -f $w, $h)
                RatioName = [string]$r.Name; Label = [string]$r.Label; Common = [string]$r.Common
                ValorantFill = $fill
                Valorant = ($fill -ne 'too small')
                Offered = (Test-UTDisplayMode -Width $w -Height $h)
            })
        }
    }
    return $out.ToArray()
}

function Add-UTCustomMode {
    <#
    .SYNOPSIS
        Makes sure Windows offers WidthxHeight. Standard 4:3 modes already exist; the wide stretched ones
        (1440x1080, 1600x1080, 1728x1080) need a custom mode, created through the NVIDIA driver's own API.
    #>
    param([Parameter(Mandatory = $true)][int]$Width, [Parameter(Mandatory = $true)][int]$Height, [int]$Hz = 0)
    if (Test-UTDisplayMode -Width $Width -Height $Height) { Write-UTLog ("{0}x{1} is already offered by Windows" -f $Width, $Height); return $true }
    if (-not [UT.NativeV1.NvApi]::IsAvailable()) {
        throw ("{0}x{1} is not offered by Windows and this PC has no NVIDIA driver to create it with. Add it in your GPU's control panel (AMD: Display > Custom Resolutions; Intel: Display > Custom) and try again." -f $Width, $Height)
    }
    # Always ask for the panel's top refresh rate: a stretched mode at 60 Hz on a high-refresh monitor
    # is worse than not doing it at all, and the driver times a custom mode from whatever we ask for.
    if ($Hz -le 0) { $Hz = Get-UTMaxRefresh }
    $r = [UT.NativeV1.NvApi]::AddMode($Width, $Height, $Hz)
    if ($r -ne 'ok') {
        throw ("The NVIDIA driver refused to create {0}x{1}@{2}: {3}. Create it once by hand in NVIDIA Control Panel > Change resolution > Customize > Create Custom Resolution, then this tool can use it." -f $Width, $Height, $Hz, $r)
    }
    Write-UTLog ("custom mode {0}x{1}@{2} created through NVIDIA's driver API" -f $Width, $Height, $Hz) -Level Ok
    return $true
}

function Set-UTDisplayScaling {
    param([Parameter(Mandatory = $true)][int]$Scaling)
    $rc = [UT.NativeV1.Display]::SetScaling([uint32]$Scaling)
    if ($rc -ne 0) { throw ("SetDisplayConfig refused scaling {0} (error {1})" -f $Scaling, $rc) }
}

function Set-UTDisplayMode {
    param([Parameter(Mandatory = $true)][int]$Width, [Parameter(Mandatory = $true)][int]$Height, [int]$Hz = 0)
    $rc = [UT.NativeV1.Display]::SetMode($Width, $Height, $Hz, $true)
    if ($rc -ne 0) { throw ("Windows refused the mode {0}x{1}@{2} (DISP_CHANGE {3})" -f $Width, $Height, $Hz, $rc) }
    Write-UTLog ("desktop switched to {0}x{1}@{2}" -f $Width, $Height, $Hz)
}

function Test-UTStretchedFill {
    <#
    .SYNOPSIS
        After the mode is live, says whether the picture will fill the panel or show black bars.
    .DESCRIPTION
        Reading the scaling immediately after SetDisplayConfig is unreliable (it answers identity even
        while the panel stretches), so this waits for the mode to settle and only speaks up for the two
        values that unambiguously mean bars: centred (2) and aspect-ratio-centred (4). Those come from
        the machine default for a mode nothing has saved a preference for, which is exactly the case for
        a resolution created seconds ago. The rest of the chain - the driver's own scaling mode and the
        monitor's OSD - is outside any API's reach, so the message names both.
    #>
    Start-Sleep -Milliseconds 700
    $s = 0
    try { $s = [int][UT.NativeV1.Display]::GetScaling() } catch { return }
    if ($s -ne 2 -and $s -ne 4) { return }
    Write-UTLog 'This mode is set to keep its aspect ratio, so you will see black bars.' -Level Warn
    Write-UTLog '  Fix it once in NVIDIA Control Panel > Display > Adjust desktop size and position: Scaling mode = Full-screen, Perform scaling on = GPU, and tick "Override the scaling mode set by games and programs". Some monitors also have their own aspect setting in the OSD that overrides the GPU.' -Level Warn
}

function Write-UTStretchedGameConfig {
    param([string]$Game, [int]$Width, [int]$Height)
    $w = [string]$Width; $h = [string]$Height
    switch ($Game) {
        'Fortnite' {
            $fn = Get-UTFortnite
            if ($fn.GameRunning) { throw 'Fortnite is running; close it first' }
            if (-not $fn.GameIniExists) { throw 'Fortnite GameUserSettings.ini not found; start the game once' }
            Backup-UTFile -Path $fn.GameIni
            $keys = @{ ResolutionSizeX = $w; ResolutionSizeY = $h; LastUserConfirmedResolutionSizeX = $w; LastUserConfirmedResolutionSizeY = $h
                       DesiredScreenWidth = $w; DesiredScreenHeight = $h; LastUserConfirmedDesiredScreenWidth = $w; LastUserConfirmedDesiredScreenHeight = $h
                       FullscreenMode = '0'; LastConfirmedFullscreenMode = '0'; PreferredFullscreenMode = '0' }
            [void](Set-UTIniValues -Path $fn.GameIni -Settings @{ $sync.configs.fortnite.MainSection = $keys })
        }
        'Valorant' {
            $v = Get-UTValorant
            if ($v.GameRunning) { throw 'VALORANT is running; close it first' }
            if (-not $v.GameIniExists) { throw 'VALORANT GameUserSettings.ini not found; start the game once' }
            Backup-UTFile -Path $v.GameIni
            $keys = @{ ResolutionSizeX = $w; ResolutionSizeY = $h; LastUserConfirmedResolutionSizeX = $w; LastUserConfirmedResolutionSizeY = $h
                       DesiredScreenWidth = $w; DesiredScreenHeight = $h; LastUserConfirmedDesiredScreenWidth = $w; LastUserConfirmedDesiredScreenHeight = $h
                       bShouldLetterbox = 'False'; bLastConfirmedShouldLetterbox = 'False'; LastConfirmedFullscreenMode = '0'; PreferredFullscreenMode = '0' }
            [void](Set-UTIniValues -Path $v.GameIni -Settings @{ $sync.configs.valorant.GameSection = $keys })
        }
    }
}

function Start-UTStretched {
    <#
    .SYNOPSIS
        The whole stretched session: record what to put back, make sure the mode exists, set GPU scaling to
        stretched, write the game's resolution, disable the monitor device for VALORANT, switch the desktop,
        launch, wait for the game to close, put everything back.
    .DESCRIPTION
        The state file is written before the first change and deleted after the last restore, so a crash
        anywhere in between is repaired at the tool's next start. VALORANT reads the monitor's native aspect
        ratio from its EDID and locks fullscreen to it, which is why its monitor device is disabled for the
        duration; Windows keeps driving the display through the generic monitor driver meanwhile.
    #>
    param([Parameter(Mandatory = $true)][int]$Width, [Parameter(Mandatory = $true)][int]$Height, [string]$Game = 'None')
    if (Test-UTStretchedState) { throw 'A stretched session is already active. Press Restore desktop first.' }
    if (-not ('UT.NativeV1.Display' -as [type])) { throw 'The native display helper is not available on this PC' }
    if ($Game -eq 'Valorant' -and -not [UT.NativeV1.NvApi]::IsAvailable()) {
        throw 'The VALORANT route is NVIDIA only: it needs the driver API to create the mode, and hiding the monitor from the game is only safe when the NVIDIA driver is the one still driving the panel.'
    }
    $cur = [UT.NativeV1.Display]::GetCurrent()
    $state = [ordered]@{ Width = $cur.Width; Height = $cur.Height; Hz = $cur.Hz; Scaling = [int][UT.NativeV1.Display]::GetScaling(); Monitors = @(); Game = $Game; Started = (Get-Date).ToString('s') }
    $statePath = Get-UTStretchedStatePath
    ([pscustomobject]$state) | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statePath -Encoding ASCII
    try {
        [void](Add-UTCustomMode -Width $Width -Height $Height -Hz (Get-UTMaxRefresh))
        $hz = Get-UTBestRefresh -Width $Width -Height $Height
        Write-UTStretchedGameConfig -Game $Game -Width $Width -Height $Height
        if ($Game -eq 'Valorant') {
            foreach ($m in (Get-UTMonitorDevices | Where-Object { $_.Status -eq 'OK' })) {
                Set-UTMonitorDevice -InstanceId $m.InstanceId -Enable $false
                $state.Monitors += $m.InstanceId
                ([pscustomobject]$state) | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statePath -Encoding ASCII
            }
        }
        Set-UTDisplayMode -Width $Width -Height $Height -Hz $hz
        # Scaling is stored per mode, so a mode that has just been created carries the machine default,
        # which on most desktops is aspect-ratio-centred: that is where the black bars come from.
        try { Set-UTDisplayScaling -Scaling 3 } catch { Write-UTLog ('GPU scaling could not be set to stretched: ' + $_.Exception.Message) -Level Warn }
        Test-UTStretchedFill
        $proc = ''
        switch ($Game) {
            'Fortnite' { Start-Process $sync.configs.fortnite.LaunchUri | Out-Null; $proc = $sync.configs.fortnite.GameProcess; Write-UTLog 'Fortnite launch requested through Epic' }
            'Valorant' { Start-UTValorant; $proc = $sync.configs.valorant.GameProcess }
            default    { Write-UTLog ("desktop is {0}x{1} stretched; press Restore desktop when you are done" -f $Width, $Height) -Level Ok; return }
        }
        $deadline = (Get-Date).AddMinutes(3)
        while ((Get-Date) -lt $deadline -and -not (Get-Process -Name $proc -ErrorAction SilentlyContinue)) { Start-Sleep -Seconds 2 }
        if (-not (Get-Process -Name $proc -ErrorAction SilentlyContinue)) { throw ("{0} did not start within three minutes" -f $proc) }
        Write-UTLog ("{0} is running at {1}x{2} stretched; the desktop goes back when it closes" -f $proc, $Width, $Height) -Level Ok
        while (Get-Process -Name $proc -ErrorAction SilentlyContinue) { Start-Sleep -Seconds 3 }
        Write-UTLog ("{0} closed" -f $proc)
    } catch {
        Write-UTLog ('stretched: ' + $_.Exception.Message) -Level Error
    }
    Restore-UTStretched
}

function Restore-UTStretched {
    $statePath = Get-UTStretchedStatePath
    if (-not (Test-Path -LiteralPath $statePath)) { Write-UTLog 'No stretched session to restore'; return }
    $st = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $failed = @()
    foreach ($id in @($st.Monitors)) { try { Set-UTMonitorDevice -InstanceId $id -Enable $true } catch { $failed += $_.Exception.Message } }
    try { if ('UT.NativeV1.Display' -as [type]) { Set-UTDisplayMode -Width $st.Width -Height $st.Height -Hz $st.Hz } } catch { $failed += $_.Exception.Message }
    try { if (('UT.NativeV1.Display' -as [type]) -and $st.Scaling -gt 1) { Set-UTDisplayScaling -Scaling ([int]$st.Scaling) } } catch { $failed += $_.Exception.Message }
    if ($failed.Count -gt 0) { throw ("desktop partly restored; the state file is kept so you can retry: " + ($failed -join '; ')) }
    Remove-Item -LiteralPath $statePath -Force
    Write-UTLog ("desktop restored to {0}x{1}@{2}, scaling {3}" -f $st.Width, $st.Height, $st.Hz, $st.Scaling) -Level Ok
}

#endregion

#region Set-UTValorantSettings.ps1
function Set-UTValorantSettings {
    <#
    .SYNOPSIS
        Applies a profile from config/valorant.json to the active player's GameUserSettings.ini and
        RiotUserSettings.ini as a key-level merge, with a backup of each file first.
    .DESCRIPTION
        Resolution, VSync, frame limit and letterboxing are Unreal settings and live in
        GameUserSettings.ini; the quality groups the Video menu shows are Riot's own keys in
        RiotUserSettings.ini. Both are per-player user settings written by the game itself on exit,
        so this refuses while the game runs; the Riot client in the tray does not touch them.
    #>
    param([Parameter(Mandatory = $true)][string]$ProfileName)
    $v = Get-UTValorant
    $cfg = $sync.configs.valorant
    $p = $cfg.Profiles.$ProfileName
    if (-not $p) { throw "Unknown profile $ProfileName" }
    if (-not $v.PlayerId) { throw 'No VALORANT player settings were found on this PC. Start the game once so it creates them.' }
    if ($v.GameRunning) { throw 'VALORANT is running. Close it first; the game rewrites these files on exit.' }
    $changed = 0
    if ($v.GameIniExists -and $p.Game) {
        $settings = @{ $cfg.GameSection = @{} }
        foreach ($kv in $p.Game.PSObject.Properties) { $settings[$cfg.GameSection][$kv.Name] = [string]$kv.Value }
        Backup-UTFile -Path $v.GameIni
        $changed += Set-UTIniValues -Path $v.GameIni -Settings $settings
    }
    if ($v.RiotIniExists -and $p.Riot) {
        $settings = @{ $cfg.RiotSection = @{} }
        foreach ($kv in $p.Riot.PSObject.Properties) { $settings[$cfg.RiotSection][$kv.Name] = [string]$kv.Value }
        Backup-UTFile -Path $v.RiotIni
        $changed += Set-UTIniValues -Path $v.RiotIni -Settings $settings
    }
    Write-UTLog ("VALORANT settings written for player {0}: {1} ({2} key(s) changed)" -f $v.PlayerId.Substring(0, 8), $p.Content, $changed) -Level Ok
}

function Restore-UTValorantSettings {
    $v = Get-UTValorant
    if ($v.GameRunning) { throw 'Close VALORANT first' }
    $n = 0
    foreach ($f in @($v.GameIni, $v.RiotIni)) {
        $orig = $f + '.unknowntweaks.original'
        if (-not (Test-Path -LiteralPath $orig)) { continue }
        Copy-Item -LiteralPath $orig -Destination $f -Force
        $n++
    }
    if ($n -eq 0) { throw 'No backup found: nothing was written by this tool yet' }
    Write-UTLog ("{0} VALORANT settings file(s) restored from the first backup" -f $n) -Level Ok
}

#endregion

#region Start-UTMonitor.ps1
function Start-UTMonitor {
    <#
    .SYNOPSIS
        Starts the 1 Hz sampler in a background runspace. It publishes an immutable snapshot to $sync.metrics.Snapshot
        and never touches the UI. PDH (English counter paths) is used for disk and GPU, Win32 APIs for CPU and RAM,
        .NET for network and ping; WMI is the fallback when the native helpers are unavailable.
    #>
    $script = @'
$ErrorActionPreference = 'Continue'
function Log([string]$m) { Write-UTLog "monitor: $m" }

$osBuild = [System.Environment]::OSVersion.Version.Build
$preferUtility = ($osBuild -lt 26100)     # Task Manager on 24H2+ (2025) shows time-based CPU; older shows Processor Utility
$haveNative = [bool]('UT.NativeV1.PdhQuery' -as [type])
$q = $null; $backend = 'wmi'
if ($haveNative) {
    try {
        $q = New-Object UT.NativeV1.PdhQuery
        $ok = $true
        foreach ($c in @(
            @('cpuUtil', '\Processor Information(_Total)\% Processor Utility'),
            @('cpuTime', '\Processor Information(_Total)\% Processor Time'),
            @('dskIdle', '\PhysicalDisk(_Total)\% Idle Time'),
            @('dskRead', '\PhysicalDisk(_Total)\Disk Read Bytes/sec'),
            @('dskWrite', '\PhysicalDisk(_Total)\Disk Write Bytes/sec'))) {
            if (-not $q.AddEnglish($c[0], $c[1])) { $ok = $false; Log ('PDH cannot add ' + $c[1]) }
        }
        $null = $q.AddEnglish('gpuEng', '\GPU Engine(*)\Utilization Percentage')
        $null = $q.AddEnglish('gpuMem', '\GPU Adapter Memory(*)\Dedicated Usage')
        if ($ok) { $backend = 'pdh'; $null = $q.Collect() } else { $q.Dispose(); $q = $null }
    } catch { Log "PDH init failed: $($_.Exception.Message)"; if ($q) { $q.Dispose() }; $q = $null }
}
Log "backend=$backend build=$osBuild"

$prevCpu = $null
$prevNet = @{}; $prevNetTime = [DateTime]::UtcNow
$pingInet = $null; $pingGw = $null
try {
    if ($haveNative) { $prevCpu = [UT.NativeV1.Sys]::GetCpuTimes() }
    foreach ($n in (Get-UTNetInterfaceBytes)) { $prevNet[$n.Id] = $n }
    $pingInet = New-Object System.Net.NetworkInformation.Ping
    $pingGw = New-Object System.Net.NetworkInformation.Ping
} catch {
    Log "startup failed: $($_.Exception.Message)"
}
$inetTask = $null; $gwTask = $null
$inetMs = $null; $inetStatus = 'n/a'; $gwMs = $null; $gwStatus = 'n/a'
$link = $null; $linkAt = -100000
$lastGpuSamples = @(); $lastGpuMemSamples = @()
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$tick = 0; $nextDue = 0

try {
  while (-not $sync.closing) {
    $tick++; $tickStart = $sw.ElapsedMilliseconds
    try {
      $now = [DateTime]::UtcNow

      # ---- CPU
      $cpuTimePct = $null; $cpuUtilPct = $null
      if ($haveNative) {
        $cpuTimes = [UT.NativeV1.Sys]::GetCpuTimes()
        if ($cpuTimes.Ok -and $prevCpu -and $prevCpu.Ok) {
          $dIdle = [double]($cpuTimes.Idle - $prevCpu.Idle)
          $dTotal = [double](($cpuTimes.Kernel + $cpuTimes.User) - ($prevCpu.Kernel + $prevCpu.User))
          if ($dTotal -gt 0) { $cpuTimePct = [math]::Round(100.0 * (1.0 - $dIdle / $dTotal), 1) }
        }
        $prevCpu = $cpuTimes
      }

      $diskActive = $null; $diskRead = $null; $diskWrite = $null; $gpuSamples = @(); $gpuMemSamples = @()
      if ($backend -eq 'pdh') {
        $null = $q.Collect()
        $v = $q.GetValue('cpuUtil', $true);  if (-not [double]::IsNaN($v)) { $cpuUtilPct = [math]::Round($v, 1) }
        $v = $q.GetValue('cpuTime', $false); if ($null -eq $cpuTimePct -and -not [double]::IsNaN($v)) { $cpuTimePct = [math]::Round($v, 1) }
        $v = $q.GetValue('dskIdle', $false); if (-not [double]::IsNaN($v)) { $diskActive = [math]::Round([math]::Max(0.0, [math]::Min(100.0, 100.0 - $v)), 1) }
        $v = $q.GetValue('dskRead', $false); if (-not [double]::IsNaN($v)) { $diskRead = $v }
        $v = $q.GetValue('dskWrite', $false); if (-not [double]::IsNaN($v)) { $diskWrite = $v }
        $gpuSamples = $q.GetArray('gpuEng', $false)
        $gpuMemSamples = $q.GetArray('gpuMem', $false)
      } else {
        try {
          $ci = Get-CimInstance -ClassName Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'" -ErrorAction Stop
          $cpuUtilPct = [double]$ci.PercentProcessorUtility
          if ($null -eq $cpuTimePct) { $cpuTimePct = [double]$ci.PercentProcessorTime }
        } catch { }
        try {
          $di = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'" -ErrorAction Stop
          $diskActive = [math]::Max(0.0, [math]::Min(100.0, 100.0 - [double]$di.PercentIdleTime)); $diskRead = [double]$di.DiskReadBytesPersec; $diskWrite = [double]$di.DiskWriteBytesPersec
        } catch { }
        # The GPU classes are the expensive ones, so they are read every other tick; the previous
        # samples are reused in between so the GPU graph still advances once per second like the others.
        if (($tick % 2) -eq 0) {
          try { $gpuSamples = @(Get-CimInstance -ClassName Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction Stop | ForEach-Object { [pscustomobject]@{ Instance = $_.Name; Value = [double]$_.UtilizationPercentage } }) } catch { }
          try { $gpuMemSamples = @(Get-CimInstance -ClassName Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory -ErrorAction Stop | ForEach-Object { [pscustomobject]@{ Instance = $_.Name; Value = [double]$_.DedicatedUsage } }) } catch { }
          $lastGpuSamples = $gpuSamples; $lastGpuMemSamples = $gpuMemSamples
        } else {
          $gpuSamples = $lastGpuSamples; $gpuMemSamples = $lastGpuMemSamples
        }
      }

      # ---- foreground (needed for per-game GPU share)
      $fg = Get-UTForegroundState

      # ---- GPU: Task Manager headline = busiest engine of the adapter (sum over processes per engine, max over engines)
      $engines = @{}; $gamePid3D = 0.0
      foreach ($s in $gpuSamples) {
        if ($null -eq $s -or [double]::IsNaN($s.Value) -or $s.Value -le 0) { continue }
        if ($s.Instance -match '^pid_(\d+)_luid_(0x[0-9A-Fa-f]+_0x[0-9A-Fa-f]+)_phys_(\d+)_eng_(\d+)_engtype_(.+)$') {
          $k = '{0}|{1}|{2}' -f $Matches[2], $Matches[4], $Matches[5]
          $engines[$k] = [double]$engines[$k] + $s.Value
          if ($fg.Pid -gt 0 -and [int]$Matches[1] -eq $fg.Pid -and $Matches[5] -match '^3D') { $gamePid3D += $s.Value }
        }
      }
      $adapters = @{}
      foreach ($k in @($engines.Keys)) {
        $parts = $k.Split('|'); $luid = $parts[0]; $val = [math]::Min(100.0, $engines[$k])
        if (-not $adapters.ContainsKey($luid)) { $adapters[$luid] = @{ Max = 0.0; Engine = ''; ThreeD = 0.0 } }
        if ($val -gt $adapters[$luid].Max) { $adapters[$luid].Max = $val; $adapters[$luid].Engine = $parts[2] }
        if ($parts[2] -match '^3D') { $adapters[$luid].ThreeD = [math]::Min(100.0, $adapters[$luid].ThreeD + $val) }
      }
      $gpuLuid = $null
      if ($adapters.Count -gt 0) { $gpuLuid = (@($adapters.GetEnumerator() | Sort-Object { $_.Value.Max } -Descending)[0]).Key }
      $gpuPct = $null; $gpu3D = $null; $gpuEngine = ''
      if ($gpuLuid) { $gpuPct = [math]::Round($adapters[$gpuLuid].Max, 1); $gpu3D = [math]::Round($adapters[$gpuLuid].ThreeD, 1); $gpuEngine = $adapters[$gpuLuid].Engine }
      $gpuDedicated = $null
      foreach ($m in $gpuMemSamples) {
        if ($null -eq $m -or [double]::IsNaN($m.Value)) { continue }
        if ($m.Instance -match '^luid_(0x[0-9A-Fa-f]+_0x[0-9A-Fa-f]+)_phys_\d+$' -and $Matches[1] -eq $gpuLuid) { $gpuDedicated = [int64]$m.Value }
      }

      # ---- RAM
      $memUsedPct = $null; $memTotal = 0; $memAvail = 0
      if ($haveNative) {
        $mem = [UT.NativeV1.Sys]::GetMem()
        if ($mem.Ok -and $mem.TotalPhys -gt 0) { $memTotal = [int64]$mem.TotalPhys; $memAvail = [int64]$mem.AvailPhys; $memUsedPct = [math]::Round(100.0 * ($memTotal - $memAvail) / $memTotal, 1) }
      } else {
        try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop; $memTotal = [int64]$os.TotalVisibleMemorySize * 1KB; $memAvail = [int64]$os.FreePhysicalMemory * 1KB; if ($memTotal -gt 0) { $memUsedPct = [math]::Round(100.0 * ($memTotal - $memAvail) / $memTotal, 1) } } catch { }
      }

      # ---- Network (delta of NDIS byte counters)
      $dt = ($now - $prevNetTime).TotalSeconds
      $netRx = 0.0; $netTx = 0.0; $linkBps = 0
      foreach ($n in (Get-UTNetInterfaceBytes)) {
        if ($prevNet.ContainsKey($n.Id) -and $dt -gt 0) {
          $netRx += [math]::Max(0.0, ($n.Rx - $prevNet[$n.Id].Rx) / $dt)
          $netTx += [math]::Max(0.0, ($n.Tx - $prevNet[$n.Id].Tx) / $dt)
        }
        if ($n.SpeedBps -gt $linkBps) { $linkBps = $n.SpeedBps }
        $prevNet[$n.Id] = $n
      }
      $prevNetTime = $now

      # ---- link info every 10 s (Get-NetAdapter is slow)
      if (($sw.ElapsedMilliseconds - $linkAt) -ge 10000) { try { $link = Get-UTNetworkLink } catch { }; $linkAt = $sw.ElapsedMilliseconds }

      # ---- pings (async so a timeout never stalls the tick)
      if ($inetTask -and $inetTask.IsCompleted) {
        try { if ($inetTask.IsFaulted) { $inetStatus = 'error'; $inetMs = $null } else { $r = $inetTask.Result; $inetStatus = [string]$r.Status; if ($r.Status -eq 'Success') { $inetMs = [int]$r.RoundtripTime } else { $inetMs = $null } } } catch { $inetStatus = 'error'; $inetMs = $null }
        $inetTask = $null
      }
      if (-not $inetTask -and $pingInet) { try { $inetTask = $pingInet.SendPingAsync('1.1.1.1', 1000) } catch { $inetTask = $null } }
      if ($gwTask -and $gwTask.IsCompleted) {
        try { if ($gwTask.IsFaulted) { $gwStatus = 'error'; $gwMs = $null } else { $r = $gwTask.Result; $gwStatus = [string]$r.Status; if ($r.Status -eq 'Success') { $gwMs = [int]$r.RoundtripTime } else { $gwMs = $null } } } catch { $gwStatus = 'error'; $gwMs = $null }
        $gwTask = $null
      }
      if (-not $gwTask -and $pingGw -and $link -and $link.Gateway -and $link.Gateway -ne '0.0.0.0') { try { $gwTask = $pingGw.SendPingAsync($link.Gateway, 1000) } catch { $gwTask = $null } }

      $cpuPct = $cpuTimePct
      if ($preferUtility -and $null -ne $cpuUtilPct) { $cpuPct = [math]::Min(100.0, $cpuUtilPct) }

      $snap = [pscustomobject]@{
        Tick = $tick; Time = [DateTime]::Now; Backend = $backend
        CpuPercent = $cpuPct; CpuUtilityPercent = $cpuUtilPct; CpuTimePercent = $cpuTimePct
        MemUsedPercent = $memUsedPct; MemTotalBytes = $memTotal; MemAvailBytes = $memAvail
        DiskActivePercent = $diskActive; DiskReadBps = $diskRead; DiskWriteBps = $diskWrite
        GpuPercent = $gpuPct; Gpu3DPercent = $gpu3D; GpuBusiestEngine = $gpuEngine; GpuDedicatedBytes = $gpuDedicated; GameGpu3D = [math]::Round([math]::Min(100.0, $gamePid3D), 1)
        NetRxBps = $netRx; NetTxBps = $netTx; LinkBps = $linkBps; Link = $link
        InetMs = $inetMs; InetStatus = $inetStatus; GatewayMs = $gwMs; GatewayStatus = $gwStatus
        Foreground = $fg
        SampleMs = ($sw.ElapsedMilliseconds - $tickStart)
      }
      if ($tick -gt 1) { $sync.metrics.Snapshot = $snap }
    } catch { Log "tick $tick error: $($_.Exception.Message)" }

    $nextDue += 1000
    $sleep = $nextDue - $sw.ElapsedMilliseconds
    if ($sleep -gt 0) { Start-Sleep -Milliseconds $sleep } else { $nextDue = $sw.ElapsedMilliseconds }
  }
} finally {
  if ($q) { $q.Dispose() }
  if ($pingInet) { $pingInet.Dispose() }
  if ($pingGw) { $pingGw.Dispose() }
  Log 'stopped'
}
'@
    $rs = [runspacefactory]::CreateRunspace((New-UTSessionState))
    $rs.ApartmentState = 'MTA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($script)
    $handle = $ps.BeginInvoke()
    $sync.monitor = @{ PowerShell = $ps; Runspace = $rs; Handle = $handle }
}

function Stop-UTMonitor {
    $sync.closing = $true
    if (-not $sync.monitor) { return }
    try {
        # A slow tick (WMI fallback enumerating GPU counters) can take several seconds, so give it room
        # to notice $sync.closing and exit on its own before forcing it.
        if (-not $sync.monitor.Handle.AsyncWaitHandle.WaitOne(6000)) { $sync.monitor.PowerShell.Stop() }
        try { $null = $sync.monitor.PowerShell.EndInvoke($sync.monitor.Handle) } catch { }
        $sync.monitor.PowerShell.Dispose(); $sync.monitor.Runspace.Close(); $sync.monitor.Runspace.Dispose()
    } catch { }
}

#endregion

#region Test-UTBetaGate.ps1
function Test-UTBetaGate {
    <#
    .SYNOPSIS
        Asks the private-beta gate whether this key and build may run. Returns @{ Ok; Reason }.
    .DESCRIPTION
        Fails closed. Anything other than a plain "ok" - a revoked key, a closed beta, an unknown
        key, a typo in the URL, no network - means the build does not start. That is the point of
        a kill switch, and it is also why public builds pass no StatusUrl and are never gated.
        This is the only request a beta build makes that a public build does not; it carries the
        tester's key and the build version and nothing else.
        -Fetch lets the tests supply the answer without a server.
    #>
    param(
        [string]$StatusUrl,
        [string]$Version = '',
        [int]$TimeoutSec = 8,
        [scriptblock]$Fetch
    )
    if ([string]::IsNullOrWhiteSpace($StatusUrl)) { return @{ Ok = $true; Reason = 'not gated' } }
    $sep = '?'
    if ($StatusUrl.Contains('?')) { $sep = '&' }
    $uri = $StatusUrl + $sep + 'v=' + [uri]::EscapeDataString([string]$Version)
    try {
        if ($Fetch) { $raw = & $Fetch $uri }
        else { $raw = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec $TimeoutSec -UseBasicParsing -ErrorAction Stop }
        $answer = ([string]$raw).Trim().ToLowerInvariant()
        if ($answer -eq 'ok') { return @{ Ok = $true; Reason = 'ok' } }
        if (-not $answer) { $answer = 'empty answer from the gate' }
        return @{ Ok = $false; Reason = $answer }
    } catch {
        return @{ Ok = $false; Reason = ('gate unreachable: ' + $_.Exception.Message) }
    }
}

#endregion

#region Test-UTDnsLatency.ps1
function Test-UTDnsLatency {
    <#
    .SYNOPSIS
        Raw UDP DNS A-query with a hard timeout (Resolve-DnsName has none). Random label prefix bypasses caches so the
        number is the resolver's real recursion time. Returns one object per sample.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Server,
        [string]$Name = 'www.epicgames.com',
        [int]$TimeoutMs = 1500,
        [int]$Samples = 5
    )
    $addr = $null
    if (-not [System.Net.IPAddress]::TryParse($Server, [ref]$addr)) { return @() }
    $out = @()
    for ($i = 0; $i -lt $Samples; $i++) {
        $qname = 'p{0}.{1}' -f (Get-Random -Minimum 1000 -Maximum 999999), $Name
        $id = Get-Random -Minimum 1 -Maximum 65535
        $buf = New-Object System.Collections.Generic.List[byte]
        $buf.AddRange([byte[]]@((($id -shr 8) -band 0xFF), ($id -band 0xFF), 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00))
        foreach ($label in $qname.TrimEnd('.').Split('.')) {
            $lb = [System.Text.Encoding]::ASCII.GetBytes($label)
            $buf.Add([byte]$lb.Length); $buf.AddRange($lb)
        }
        $buf.AddRange([byte[]]@(0x00, 0x00, 0x01, 0x00, 0x01))
        $pkt = $buf.ToArray()
        $udp = New-Object System.Net.Sockets.UdpClient($addr.AddressFamily)
        $udp.Client.ReceiveTimeout = $TimeoutMs
        $ep = New-Object System.Net.IPEndPoint($addr, 53)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            [void]$udp.Send($pkt, $pkt.Length, $ep)
            $from = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
            if ($addr.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) { $from = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::IPv6Any, 0) }
            $resp = $udp.Receive([ref]$from)
            $sw.Stop()
            $idOk = ($resp.Length -ge 2) -and ($resp[0] -eq $pkt[0]) -and ($resp[1] -eq $pkt[1])
            $out += [pscustomobject]@{ Server = $Server; Sample = ($i + 1); Ms = [math]::Round($sw.Elapsed.TotalMilliseconds, 1); Ok = $idOk }
        } catch {
            $sw.Stop()
            $out += [pscustomobject]@{ Server = $Server; Sample = ($i + 1); Ms = $null; Ok = $false }
        } finally { $udp.Close() }
    }
    return $out
}

function Invoke-UTDnsBenchmark {
    <#
    .SYNOPSIS
        Benchmarks every provider in config/dns.json plus the resolver you use now; stores rows in $sync.dnsResults.
    #>
    $rows = @()
    $current = @()
    try {
        $link = Get-UTNetworkLink
        if ($link.InterfaceIndex) {
            $current = @((Get-DnsClientServerAddress -InterfaceIndex $link.InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop).ServerAddresses)
        }
    } catch { }
    $targets = @()
    if ($current.Count -gt 0) { $targets += [pscustomobject]@{ Name = 'Current (' + $current[0] + ')'; Server = $current[0] } }
    foreach ($p in $sync.configs.dns.PSObject.Properties) { $targets += [pscustomobject]@{ Name = $p.Name; Server = $p.Value.Primary } }
    foreach ($t in $targets) {
        $sync.status = 'DNS benchmark: ' + $t.Name
        $s = @(Test-UTDnsLatency -Server $t.Server -Samples 5 -TimeoutMs 1500 | Where-Object { $_.Ok })
        $median = $null; $best = $null
        if ($s.Count -gt 0) {
            $vals = @($s | ForEach-Object { $_.Ms } | Sort-Object)
            $median = $vals[[int][math]::Floor($vals.Count / 2)]
            $best = $vals[0]
        }
        $rows += [pscustomobject]@{ Name = $t.Name; Server = $t.Server; MedianMs = $median; BestMs = $best; Ok = $s.Count; Sent = 5 }
    }
    $sync.dnsResults = @($rows | Sort-Object @{ Expression = { if ($null -eq $_.MedianMs) { 99999 } else { $_.MedianMs } } })
    return $sync.dnsResults
}

function Format-UTDnsTable {
    param($Rows)
    $rows = @($Rows | Where-Object { $null -ne $_ })
    # Sized from the data for the same reason as the region table: a provider name or an IPv6
    # literal wider than the pad would shift the rest of that row out of the columns.
    $wName = 'RESOLVER'.Length; $wAddr = 'ADDRESS'.Length
    foreach ($r in $rows) {
        if (([string]$r.Name).Length -gt $wName) { $wName = ([string]$r.Name).Length }
        if (([string]$r.Server).Length -gt $wAddr) { $wAddr = ([string]$r.Server).Length }
    }
    $fmt = '{0,-' + $wName + '}  {1,-' + $wAddr + '} {2,8} {3,8} {4,6}'
    $lines = @()
    $lines += $fmt -f 'RESOLVER', 'ADDRESS', 'MEDIAN', 'BEST', 'OK'
    foreach ($r in $rows) {
        $med = 'timeout'; $best = '-'
        if ($null -ne $r.MedianMs) { $med = ('{0} ms' -f $r.MedianMs); $best = ('{0} ms' -f $r.BestMs) }
        # One pre-joined string, so the OK column right-aligns under its own header instead of the
        # replies count hanging off the end of a 3-wide field.
        $lines += $fmt -f $r.Name, $r.Server, $med, $best, ('{0}/{1}' -f $r.Ok, $r.Sent)
    }
    $lines += ''
    $lines += 'DNS only affects name lookups (launcher, login, matchmaking API, patch CDN). It cannot change in-match ping.'
    return ($lines -join "`r`n")
}

function Set-UTDns {
    <#
    .SYNOPSIS
        Sets (or resets to DHCP) the resolvers on the adapter that carries the default route. Remembers a static
        configuration so Undo can put it back.
    #>
    param([string]$Provider, [switch]$Reset)
    $link = Get-UTNetworkLink
    if (-not $link.InterfaceIndex) { throw 'No adapter with a default route was found' }
    $idx = $link.InterfaceIndex
    if ($Reset) {
        if (-not (Test-UTBackupExists -Id UTDns)) {
            # Resetting a configuration this tool never changed would silently throw away someone's own
            # static DNS, so it only resets what it set.
            Write-UTLog "unknowntweaks has not changed DNS on this PC, so nothing was reset. To clear DNS yourself: Set-DnsClientServerAddress -InterfaceIndex $idx -ResetServerAddresses" -Level Warn
            return
        }
        $prev = Get-UTScriptState -Id UTDns -Key Static
        if ($prev) {
            Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses (@($prev -split '\|')) -ErrorAction Stop
            Write-UTLog "DNS on $($link.Adapter) restored to the static servers you had before: $prev"
        } else {
            Set-DnsClientServerAddress -InterfaceIndex $idx -ResetServerAddresses -ErrorAction Stop
            Write-UTLog "DNS on $($link.Adapter) reset to automatic (DHCP)"
        }
        Remove-UTBackup -Id UTDns
    } else {
        $p = $sync.configs.dns.$Provider
        if (-not $p) { throw "Unknown DNS provider $Provider" }
        if (-not (Test-UTBackupExists -Id UTDns)) {
            # Read the live configuration rather than the IPv4-only NameServer registry value, which is
            # comma OR space separated depending on how it was written and omits IPv6 entirely.
            $static = ''
            try {
                $current = @(Get-DnsClientServerAddress -InterfaceIndex $idx -ErrorAction Stop |
                             Where-Object { $_.ServerAddresses } | ForEach-Object { $_.ServerAddresses })
                # A DHCP-supplied list must not be recorded as "static", or Reset would pin it forever.
                $guid = (Get-NetAdapter -InterfaceIndex $idx -ErrorAction SilentlyContinue).InterfaceGuid
                $isStatic = $false
                if ($guid) {
                    $ns = [string](Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid" -Name NameServer -ErrorAction SilentlyContinue).NameServer
                    $isStatic = -not [string]::IsNullOrWhiteSpace($ns)
                }
                if ($isStatic -and $current.Count -gt 0) { $static = ($current -join '|') }
            } catch { }
            Save-UTScriptState -Id UTDns -Key Static -Value $static
            @{ Id = 'UTDns'; Date = (Get-Date -Format 's') } | ConvertTo-Json | Set-Content -LiteralPath (Get-UTBackupPath -Id UTDns) -Encoding UTF8
        }
        $servers = @($p.Primary, $p.Secondary)
        if ($p.Primary6) { $servers += $p.Primary6 }
        if ($p.Secondary6) { $servers += $p.Secondary6 }
        Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses $servers -ErrorAction Stop
        Write-UTLog "DNS on $($link.Adapter) set to $Provider ($($servers -join ', '))" -Level Ok
    }
    Clear-DnsClientCache -ErrorAction SilentlyContinue
}

#endregion

#region Test-UTTweakApplied.ps1
function Update-UTTweakStates {
    <#
    .SYNOPSIS
        Recomputes the applied/set state of every tweak into $sync.tweakStates.
    .NOTES
        This is dozens of registry reads and file checks, so it runs in a worker runspace; the UI only
        reads the finished hashtable.
    #>
    $states = @{}
    foreach ($p in $sync.configs.tweaks.PSObject.Properties) {
        try { $states[$p.Name] = Test-UTTweakApplied -Id $p.Name -Tweak $p.Value } catch { $states[$p.Name] = '' }
    }
    $sync.tweakStates = $states
}

function Test-UTTweakApplied {
    <#
    .SYNOPSIS
        'applied' when unknowntweaks applied it (snapshot exists), 'set' when the registry already holds the tweak
        values (set manually or by another tool), '' otherwise. Script-only tweaks report only 'applied'.
    #>
    param([Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)]$Tweak)
    if (Test-UTBackupExists -Id $Id) { return 'applied' }
    $entries = @($Tweak.registry | Where-Object { $_ })
    if ($entries.Count -eq 0) { return '' }
    foreach ($r in $entries) {
        $cur = Get-UTRegistryValue -Path $r.Path -Name $r.Name
        if ([string]$r.Value -eq '<RemoveEntry>') { if ($cur.Exists) { return '' }; continue }
        if (-not $cur.Exists) { return '' }
        # A DWord 0 and a REG_SZ "0" both serialise to "0" but are not the same setting, so the kind
        # has to match too before claiming the tweak is already in place.
        $wantKind = [string]$r.Type
        if ($wantKind -and $cur.Kind -and $cur.Kind -ne $wantKind) { return '' }
        $want = [string]$r.Value
        if ($r.Type -eq 'Binary') { $want = (($want -split ',' | ForEach-Object { '{0:X2}' -f [Convert]::ToByte($_.Trim(), 16) }) -join ',') }
        if ($cur.Value -ne $want) { return '' }
    }
    return 'set'
}

#endregion

#region Write-UTLog.ps1
function Invoke-UTNative {
    <#
    .SYNOPSIS
        Runs a console executable and returns its combined output and exit code.
    .DESCRIPTION
        Worker runspaces run with $ErrorActionPreference = 'Stop'. In Windows PowerShell 5.1 a native
        command's stderr redirected with 2>&1 arrives as ErrorRecords, which that preference turns into
        terminating errors, so a tool that merely prints a warning to stderr would abort the whole job.
        This runs the command with the preference relaxed and reports the exit code instead.
    .OUTPUTS
        A hashtable with Output (string), Lines (string[]) and ExitCode.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @()
    )
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& $FilePath @Arguments 2>&1 | ForEach-Object { [string]$_ })
        $code = $LASTEXITCODE
        return @{ Output = ($lines -join [Environment]::NewLine); Lines = $lines; ExitCode = $code }
    } catch {
        return @{ Output = $_.Exception.Message; Lines = @([string]$_.Exception.Message); ExitCode = -1 }
    } finally {
        $ErrorActionPreference = $previous
    }
}

function Write-UTLog {
    <#
    .SYNOPSIS
        Logs a line to the UI console (through a thread-safe queue), the log file, and the host.
    .NOTES
        Safe to call from any runspace: it never touches WPF objects. The UI timer drains $sync.log.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Info', 'Ok', 'Warn', 'Error')][string]$Level = 'Info'
    )
    $tag = switch ($Level) { 'Ok' { ' OK ' } 'Warn' { 'WARN' } 'Error' { 'ERR ' } default { 'INFO' } }
    $line = '[{0:HH:mm:ss}] [{1}] {2}' -f (Get-Date), $tag, $Message
    try { if ($sync.log) { $sync.log.Enqueue($line) } } catch { }
    try { if ($sync.logPath) { Add-Content -LiteralPath $sync.logPath -Value $line -ErrorAction SilentlyContinue } } catch { }
    if (-not $sync.form) {
        $color = switch ($Level) { 'Ok' { 'Green' } 'Warn' { 'Yellow' } 'Error' { 'Red' } default { 'Gray' } }
        Write-Host $line -ForegroundColor $color
    }
}

#endregion


# ==============================================================================================
# Embedded configuration from the backend: tweaks, Fortnite, networking, Game Ready, etc.
# ==============================================================================================
$sync.configs.applications = @'
{
  "Discord": {
    "Winget": "Discord.Discord",
    "Category": "Gaming"
  },
  "Steam": {
    "Winget": "Valve.Steam",
    "Category": "Gaming"
  },
  "Epic Games Launcher": {
    "Winget": "EpicGames.EpicGamesLauncher",
    "Category": "Gaming"
  },
  "Battle.net": {
    "Winget": "Blizzard.BattleNet",
    "Category": "Gaming"
  },
  "EA app": {
    "Winget": "ElectronicArts.EADesktop",
    "Category": "Gaming"
  },
  "Ubisoft Connect": {
    "Winget": "Ubisoft.Connect",
    "Category": "Gaming"
  },
  "VALORANT (NA)": {
    "Winget": "RiotGames.Valorant.NA",
    "Category": "Gaming"
  },
  "VALORANT (EU)": {
    "Winget": "RiotGames.Valorant.EU",
    "Category": "Gaming"
  },
  "Medal": {
    "Winget": "MedalB.V.Medal",
    "Category": "Gaming"
  },
  "Parsec": {
    "Winget": "Parsec.Parsec",
    "Category": "Gaming"
  },
  "MSI Afterburner": {
    "Winget": "Guru3D.Afterburner",
    "Category": "Monitoring",
    "Note": "winget ships 4.6.6. Riot Vanguard blocks older RTCore64 driver builds; if it still gets blocked, untick \"Enable low-level IO driver\" in Afterburner settings"
  },
  "RivaTuner Statistics Server": {
    "Winget": "Guru3D.RTSS",
    "Category": "Monitoring"
  },
  "HWiNFO": {
    "Winget": "REALiX.HWiNFO",
    "Category": "Monitoring"
  },
  "CrystalDiskInfo": {
    "Winget": "CrystalDewWorld.CrystalDiskInfo",
    "Category": "Monitoring"
  },
  "CrystalDiskMark": {
    "Winget": "CrystalDewWorld.CrystalDiskMark",
    "Category": "Monitoring"
  },
  "Visual C++ 2015-2022 x64": {
    "Winget": "Microsoft.VCRedist.2015+.x64",
    "Category": "Runtimes",
    "Note": "Fixes most missing DLL crashes"
  },
  "Visual C++ 2015-2022 x86": {
    "Winget": "Microsoft.VCRedist.2015+.x86",
    "Category": "Runtimes"
  },
  "DirectX End-User Runtime": {
    "Winget": "Microsoft.DirectX",
    "Category": "Runtimes"
  },
  ".NET Desktop Runtime 8": {
    "Winget": "Microsoft.DotNet.DesktopRuntime.8",
    "Category": "Runtimes"
  },
  ".NET Desktop Runtime 6": {
    "Winget": "Microsoft.DotNet.DesktopRuntime.6",
    "Category": "Runtimes",
    "Note": "Out of support since November 2024; only install it if a specific old game or tool asks for it"
  },
  "Cloudflare WARP": {
    "Winget": "Cloudflare.Warp",
    "Category": "Network",
    "Note": "Free tunnel; can lower or raise game ping, measure with the region pinger before and after"
  },
  "OBS Studio": {
    "Winget": "OBSProject.OBSStudio",
    "Category": "Streaming"
  },
  "ShareX": {
    "Winget": "ShareX.ShareX",
    "Category": "Streaming"
  },
  "7-Zip": {
    "Winget": "7zip.7zip",
    "Category": "Utilities"
  },
  "PowerToys": {
    "Winget": "Microsoft.PowerToys",
    "Category": "Utilities"
  },
  "Everything (search)": {
    "Winget": "voidtools.Everything",
    "Category": "Utilities"
  },
  "Notepad++": {
    "Winget": "Notepad++.Notepad++",
    "Category": "Utilities"
  },
  "Windows Terminal": {
    "Winget": "Microsoft.WindowsTerminal",
    "Category": "Utilities"
  },
  "Revo Uninstaller": {
    "Winget": "RevoUninstaller.RevoUninstaller",
    "Category": "Utilities"
  },
  "Process Lasso": {
    "Winget": "BitSum.ProcessLasso",
    "Category": "Utilities"
  },
  "Bitwarden": {
    "Winget": "Bitwarden.Bitwarden",
    "Category": "Utilities"
  },
  "qBittorrent": {
    "Winget": "qBittorrent.qBittorrent",
    "Category": "Utilities"
  },
  "Malwarebytes": {
    "Winget": "Malwarebytes.Malwarebytes",
    "Category": "Utilities"
  },
  "Google Chrome": {
    "Winget": "Google.Chrome",
    "Category": "Browsers"
  },
  "Firefox": {
    "Winget": "Mozilla.Firefox",
    "Category": "Browsers"
  },
  "Brave": {
    "Winget": "Brave.Brave",
    "Category": "Browsers"
  },
  "VLC": {
    "Winget": "VideoLAN.VLC",
    "Category": "Media"
  },
  "Spotify": {
    "Winget": "Spotify.Spotify",
    "Category": "Media",
    "Note": "Its installer refuses to run elevated, so this one fails from unknowntweaks; install it from a normal PowerShell window"
  },
  "Visual Studio Code": {
    "Winget": "Microsoft.VisualStudioCode",
    "Category": "Development"
  },
  "Git": {
    "Winget": "Git.Git",
    "Category": "Development"
  },
  "VALORANT (AP)": {
    "Winget": "RiotGames.Valorant.AP",
    "Category": "Gaming"
  },
  "VALORANT (BR)": {
    "Winget": "RiotGames.Valorant.BR",
    "Category": "Gaming"
  },
  "VALORANT (KR)": {
    "Winget": "RiotGames.Valorant.KR",
    "Category": "Gaming"
  },
  "VALORANT (LATAM)": {
    "Winget": "RiotGames.Valorant.LATAM",
    "Category": "Gaming"
  },
  ".NET Desktop Runtime 10": {
    "Winget": "Microsoft.DotNet.DesktopRuntime.10",
    "Category": "Runtimes",
    "Note": "Current long-term-support runtime"
  }
}
'@ | ConvertFrom-Json

$sync.configs.debloat = @'
{
  "Microsoft.549981C3F5F10": {
    "Content": "Cortana",
    "Category": "Ads and assistants",
    "Recommended": true,
    "Note": "The voice assistant. Retired as an app by Microsoft; Start menu search does not need it."
  },
  "Microsoft.Copilot": {
    "Content": "Copilot",
    "Category": "Ads and assistants",
    "Recommended": true,
    "Note": "The Copilot app. Reinstallable from the Store if you want it back."
  },
  "Microsoft.BingNews": {
    "Content": "Bing News",
    "Category": "Ads and assistants",
    "Recommended": true,
    "Note": "News feed app. Pairs with the news and interests tweak in TWEAKS."
  },
  "Microsoft.BingWeather": {
    "Content": "Weather",
    "Category": "Ads and assistants",
    "Recommended": true,
    "Note": "Also the source of the taskbar weather widget's data."
  },
  "MicrosoftWindows.Client.WebExperience": {
    "Content": "Windows Web Experience Pack (Widgets board)",
    "Category": "Ads and assistants",
    "Recommended": false,
    "Note": "Windows 11 only, and it hosts the Widgets board and its background process. Not recommended here because the Widgets tweak in TWEAKS already stops it running and can be undone; this removes it. Reinstallable from the Store as Windows Web Experience Pack."
  },
  "Microsoft.BingSearch": {
    "Content": "Web search in Start",
    "Category": "Ads and assistants",
    "Recommended": true,
    "Note": "The web results component of Start search. Local file and app search is unaffected."
  },
  "Microsoft.MicrosoftOfficeHub": {
    "Content": "Office / Microsoft 365 hub",
    "Category": "Ads and assistants",
    "Recommended": true,
    "Note": "The 'Get Office' promotion tile. Not Office itself: a real Office install is untouched."
  },
  "Microsoft.MicrosoftSolitaireCollection": {
    "Content": "Solitaire Collection",
    "Category": "Ads and assistants",
    "Recommended": true,
    "Note": "Ad-supported card games."
  },
  "Microsoft.GetHelp": {
    "Content": "Get Help",
    "Category": "Ads and assistants",
    "Recommended": true,
    "Note": "Support chat app. Some Settings troubleshooter links stop working."
  },
  "Microsoft.Getstarted": {
    "Content": "Tips",
    "Category": "Ads and assistants",
    "Recommended": true,
    "Note": "The 'Get started' / Tips tour."
  },
  "Microsoft.WindowsFeedbackHub": {
    "Content": "Feedback Hub",
    "Category": "Ads and assistants",
    "Recommended": true,
    "Note": "Only needed if you file Windows Insider feedback."
  },
  "Microsoft.Windows.DevHome": {
    "Content": "Dev Home",
    "Category": "Ads and assistants",
    "Recommended": true,
    "Note": "Developer dashboard shipped with Windows 11. Nothing depends on it."
  },
  "Microsoft.MixedReality.Portal": {
    "Content": "Mixed Reality Portal",
    "Category": "Ads and assistants",
    "Recommended": true,
    "Note": "Windows Mixed Reality was discontinued in 2024. Dead weight unless you own a WMR headset."
  },
  "Microsoft.Microsoft3DViewer": {
    "Content": "3D Viewer",
    "Category": "Ads and assistants",
    "Recommended": true,
    "Note": "3D model viewer. Removed from new Windows installs anyway."
  },
  "Microsoft.Print3D": {
    "Content": "Print 3D",
    "Category": "Ads and assistants",
    "Recommended": true,
    "Note": "3D printing app. Removed from new Windows installs anyway."
  },
  "Microsoft.SkypeApp": {
    "Content": "Skype",
    "Category": "Communication",
    "Recommended": true,
    "Note": "Consumer Skype was retired in May 2025."
  },
  "Microsoft.YourPhone": {
    "Content": "Phone Link",
    "Category": "Communication",
    "Recommended": false,
    "Note": "Links an Android or iPhone to the PC. Remove only if you do not use it: it runs a background service."
  },
  "MicrosoftWindows.CrossDevice": {
    "Content": "Cross Device (Phone Link companion)",
    "Category": "Communication",
    "Recommended": false,
    "Note": "The newer half of Phone Link, including phone-as-webcam. Remove together with Phone Link or not at all."
  },
  "Microsoft.People": {
    "Content": "People",
    "Category": "Communication",
    "Recommended": true,
    "Note": "Contacts app used by the retired Mail client."
  },
  "microsoft.windowscommunicationsapps": {
    "Content": "Mail and Calendar",
    "Category": "Communication",
    "Recommended": false,
    "Note": "The classic Mail and Calendar apps, retired at the end of 2024 in favour of the new Outlook. Remove only if you do not read mail here."
  },
  "Microsoft.OutlookForWindows": {
    "Content": "Outlook (new)",
    "Category": "Communication",
    "Recommended": false,
    "Note": "The web-based Outlook that replaced Mail. Remove only if you do not read mail here."
  },
  "Microsoft.ZuneMusic": {
    "Content": "Media Player / Groove Music",
    "Category": "Media",
    "Recommended": false,
    "Note": "The default music and media player. Removing it leaves audio files with no default app until you set one."
  },
  "Microsoft.ZuneVideo": {
    "Content": "Films and TV",
    "Category": "Media",
    "Recommended": false,
    "Note": "The default video player and the Microsoft video store."
  },
  "Microsoft.WindowsMaps": {
    "Content": "Maps",
    "Category": "Media",
    "Recommended": true,
    "Note": "Offline maps app. Its updater task is one of the ones the Telemetry tweak disables."
  },
  "Microsoft.WindowsSoundRecorder": {
    "Content": "Sound Recorder",
    "Category": "Media",
    "Recommended": false,
    "Note": "Voice recorder."
  },
  "Microsoft.WindowsAlarms": {
    "Content": "Clock (alarms and timers)",
    "Category": "Media",
    "Recommended": false,
    "Note": "Alarms, timers and focus sessions."
  },
  "Microsoft.MicrosoftStickyNotes": {
    "Content": "Sticky Notes",
    "Category": "Media",
    "Recommended": false,
    "Note": "Desktop notes."
  },
  "Microsoft.XboxApp": {
    "Content": "Xbox Console Companion (old)",
    "Category": "Xbox - read the warning",
    "Recommended": true,
    "Note": "The deprecated Windows 10 Xbox app, replaced by the Xbox / Game Pass app. Safe: nothing signs in through it any more."
  },
  "Microsoft.XboxGamingOverlay": {
    "Content": "Xbox Game Bar",
    "Category": "Xbox - read the warning",
    "Recommended": false,
    "Note": "Win+G overlay, the built-in FPS counter and Win+Alt+R capture. Removing it also removes the per-game Game Mode toggle UI. Keep it if you use any of that."
  },
  "Microsoft.XboxGameOverlay": {
    "Content": "Xbox Game Bar overlay component",
    "Category": "Xbox - read the warning",
    "Recommended": false,
    "Note": "The companion package to Game Bar. Remove together with Game Bar or not at all."
  },
  "Microsoft.XboxSpeechToTextOverlay": {
    "Content": "Xbox game chat transcription",
    "Category": "Xbox - read the warning",
    "Recommended": false,
    "Note": "Speech-to-text for Xbox party chat."
  },
  "Microsoft.Xbox.TCUI": {
    "Content": "Xbox in-game UI (TCUI)",
    "Category": "Xbox - read the warning",
    "Recommended": false,
    "Note": "Draws the Xbox account, friends and achievement panels inside games. Some Game Pass and Microsoft-published titles fail to open those panels without it. Leave it unless you are sure."
  }
}
'@ | ConvertFrom-Json

$sync.configs.dns = @'
{
  "Cloudflare": { "Primary": "1.1.1.1", "Secondary": "1.0.0.1", "Primary6": "2606:4700:4700::1111", "Secondary6": "2606:4700:4700::1001", "DohTemplate": "https://cloudflare-dns.com/dns-query", "Note": "Fastest for most people; no filtering" },
  "Google": { "Primary": "8.8.8.8", "Secondary": "8.8.4.4", "Primary6": "2001:4860:4860::8888", "Secondary6": "2001:4860:4860::8844", "DohTemplate": "https://dns.google/dns-query", "Note": "Large anycast network; no filtering" },
  "Quad9": { "Primary": "9.9.9.9", "Secondary": "149.112.112.112", "Primary6": "2620:fe::fe", "Secondary6": "2620:fe::9", "DohTemplate": "https://dns.quad9.net/dns-query", "Note": "Blocks known malware domains" },
  "Quad9 ECS": { "Primary": "9.9.9.11", "Secondary": "149.112.112.11", "Primary6": "2620:fe::11", "Secondary6": "2620:fe::fe:11", "DohTemplate": "https://dns11.quad9.net/dns-query", "Note": "Quad9 with client subnet, steers CDNs to a closer edge (faster patch downloads)" },
  "OpenDNS": { "Primary": "208.67.222.222", "Secondary": "208.67.220.220", "Primary6": "2620:119:35::35", "Secondary6": "2620:119:53::53", "DohTemplate": "https://doh.opendns.com/dns-query", "Note": "Cisco; optional content filtering" },
  "AdGuard": { "Primary": "94.140.14.14", "Secondary": "94.140.15.15", "Primary6": "2a10:50c0::ad1:ff", "Secondary6": "2a10:50c0::ad2:ff", "DohTemplate": "https://dns.adguard-dns.com/dns-query", "Note": "Blocks ads and trackers" },
  "Control D": { "Primary": "76.76.2.0", "Secondary": "76.76.10.0", "Primary6": "2606:1a40::", "Secondary6": "2606:1a40:1::", "DohTemplate": "https://freedns.controld.com/p0", "Note": "Unfiltered free tier" }
}
'@ | ConvertFrom-Json

$sync.configs.fortnite = @'
{
  "GameProcess": "FortniteClient-Win64-Shipping",
  "BlockingProcesses": [ "FortniteClient-Win64-Shipping", "FortniteLauncher", "FortniteClient-Win64-Shipping_EAC_EOS", "FortniteClient-Win64-Shipping_EAC", "FortniteClient-Win64-Shipping_BE" ],
  "LauncherProcesses": [ "EpicGamesLauncher", "EpicWebHelper", "EpicOnlineServicesUserHelper" ],
  "LaunchUri": "com.epicgames.launcher://apps/fn%3A4fe75bbc5a674f4f9b356b5c90567da5%3AFortnite?action=launch&silent=true",
  "MainSection": "/Script/FortniteGame.FortGameUserSettings",
  "Profiles": {
    "MaxFPS": {
      "Content": "Max FPS (Performance Mode, everything low)",
      "Description": "What most competitive players run: Performance Mode renderer, every quality group at the lowest in-game level, Nanite, Lumen and ray tracing off, anti-aliasing off, Reflex On+Boost, VSync and motion blur off, uncapped FPS. Every key here is one the in-game Video menu exposes.",
      "Settings": {
        "/Script/FortniteGame.FortGameUserSettings": {
          "FullscreenMode": "0",
          "LastConfirmedFullscreenMode": "0",
          "PreferredFullscreenMode": "0",
          "FrameRateLimit": "0.000000",
          "bUseVSync": "False",
          "bUseDynamicResolution": "False",
          "bMotionBlur": "False",
          "LatencyTweak2": "2",
          "bLatencyTweak1": "False",
          "bLatencyFlash": "False",
          "FortAntiAliasingMethod": "Disabled",
          "DLSSQuality": "0",
          "XeSSQuality": "0",
          "bEnableDLSSFrameGeneration": "False",
          "bUseNanite": "False",
          "DesiredGlobalIlluminationQuality": "0",
          "DesiredReflectionQuality": "0",
          "PreNaniteGlobalIlluminationQuality": "0",
          "PreNaniteReflectionQuality": "0",
          "bRayTracing": "False",
          "bUseGPUCrashDebugging": "False",
          "CosmeticStreamingEnabled": "CodeSet_Disabled",
          "bUseHDRDisplayOutput": "False"
        },
        "ScalabilityGroups": {
          "sg.ResolutionQuality": "100",
          "sg.ViewDistanceQuality": "0",
          "sg.AntiAliasingQuality": "0",
          "sg.ShadowQuality": "0",
          "sg.GlobalIlluminationQuality": "0",
          "sg.ReflectionQuality": "0",
          "sg.PostProcessQuality": "0",
          "sg.TextureQuality": "0",
          "sg.EffectsQuality": "0",
          "sg.FoliageQuality": "0",
          "sg.ShadingQuality": "0",
          "sg.LandscapeQuality": "0"
        },
        "D3DRHIPreference": {
          "PreferredRHI": "dx12",
          "PreferredFeatureLevel": "es31"
        },
        "PerformanceMode": {
          "MeshQuality": "0"
        },
        "RayTracing": {
          "r.RayTracing.EnableInGame": "False"
        }
      }
    },
    "Balanced": {
      "Content": "Balanced (DirectX 12, low shadows and effects, textures medium)",
      "Description": "DirectX 12 renderer with view distance at Epic so distant builds stay visible, textures at Medium, and shadows, post processing, effects, foliage, Lumen and Nanite off. For mid-range and high-end GPUs that want the full renderer without the expensive parts.",
      "Settings": {
        "/Script/FortniteGame.FortGameUserSettings": {
          "FullscreenMode": "0",
          "LastConfirmedFullscreenMode": "0",
          "PreferredFullscreenMode": "0",
          "FrameRateLimit": "0.000000",
          "bUseVSync": "False",
          "bUseDynamicResolution": "False",
          "bMotionBlur": "False",
          "LatencyTweak2": "2",
          "bLatencyTweak1": "False",
          "bLatencyFlash": "False",
          "FortAntiAliasingMethod": "Disabled",
          "bEnableDLSSFrameGeneration": "False",
          "bUseNanite": "False",
          "DesiredGlobalIlluminationQuality": "0",
          "DesiredReflectionQuality": "0",
          "PreNaniteGlobalIlluminationQuality": "0",
          "PreNaniteReflectionQuality": "0",
          "bRayTracing": "False",
          "bUseGPUCrashDebugging": "False",
          "CosmeticStreamingEnabled": "CodeSet_Disabled"
        },
        "ScalabilityGroups": {
          "sg.ResolutionQuality": "100",
          "sg.ViewDistanceQuality": "3",
          "sg.AntiAliasingQuality": "0",
          "sg.ShadowQuality": "0",
          "sg.GlobalIlluminationQuality": "0",
          "sg.ReflectionQuality": "0",
          "sg.PostProcessQuality": "0",
          "sg.TextureQuality": "2",
          "sg.EffectsQuality": "0",
          "sg.FoliageQuality": "0",
          "sg.ShadingQuality": "0",
          "sg.LandscapeQuality": "0"
        },
        "D3DRHIPreference": {
          "PreferredRHI": "dx12",
          "PreferredFeatureLevel": "sm6"
        },
        "RayTracing": {
          "r.RayTracing.EnableInGame": "False"
        }
      }
    },
    "LatencyOnly": {
      "Content": "Latency only (keep my visuals)",
      "Description": "Changes nothing about image quality. Sets NVIDIA Reflex to On+Boost, VSync off, motion blur off, dynamic resolution off, DLSS Frame Generation off (it adds latency) and exclusive fullscreen.",
      "Settings": {
        "/Script/FortniteGame.FortGameUserSettings": {
          "FullscreenMode": "0",
          "LastConfirmedFullscreenMode": "0",
          "PreferredFullscreenMode": "0",
          "bUseVSync": "False",
          "bUseDynamicResolution": "False",
          "bMotionBlur": "False",
          "LatencyTweak2": "2",
          "bLatencyTweak1": "False",
          "bLatencyFlash": "False",
          "bEnableDLSSFrameGeneration": "False"
        }
      }
    },
    "Potato": {
      "Content": "Potato (experimental: DirectX 12 at 50 percent render resolution, everything off)",
      "Description": "For fun, and for GPUs whose DirectX 12 path outruns their Performance Mode path: the full DX12 renderer with 3D resolution at 50 percent (the game's own TSR upscales it back), every quality group at its lowest, Nanite, Lumen, ray tracing and anti-aliasing off, Reflex On+Boost, VSync off. It looks like a potato. Measure it against Max FPS yourself; on most cards Performance Mode is still faster.",
      "Settings": {
        "/Script/FortniteGame.FortGameUserSettings": {
          "FullscreenMode": "0",
          "LastConfirmedFullscreenMode": "0",
          "PreferredFullscreenMode": "0",
          "FrameRateLimit": "0.000000",
          "bUseVSync": "False",
          "bUseDynamicResolution": "False",
          "bMotionBlur": "False",
          "LatencyTweak2": "2",
          "bLatencyTweak1": "False",
          "bLatencyFlash": "False",
          "FortAntiAliasingMethod": "Disabled",
          "DLSSQuality": "0",
          "XeSSQuality": "0",
          "bEnableDLSSFrameGeneration": "False",
          "bUseNanite": "False",
          "DesiredGlobalIlluminationQuality": "0",
          "DesiredReflectionQuality": "0",
          "PreNaniteGlobalIlluminationQuality": "0",
          "PreNaniteReflectionQuality": "0",
          "bRayTracing": "False",
          "bUseGPUCrashDebugging": "False",
          "CosmeticStreamingEnabled": "CodeSet_Disabled",
          "bUseHDRDisplayOutput": "False"
        },
        "ScalabilityGroups": {
          "sg.ResolutionQuality": "50",
          "sg.ViewDistanceQuality": "0",
          "sg.AntiAliasingQuality": "0",
          "sg.ShadowQuality": "0",
          "sg.GlobalIlluminationQuality": "0",
          "sg.ReflectionQuality": "0",
          "sg.PostProcessQuality": "0",
          "sg.TextureQuality": "0",
          "sg.EffectsQuality": "0",
          "sg.FoliageQuality": "0",
          "sg.ShadingQuality": "0",
          "sg.LandscapeQuality": "0"
        },
        "D3DRHIPreference": {
          "PreferredRHI": "dx12",
          "PreferredFeatureLevel": "sm6"
        },
        "RayTracing": {
          "r.RayTracing.EnableInGame": "False"
        }
      }
    }
  },
  "HiddenKeys": {
    "UTFNGrassOff": {
      "Content": "Hidden key: bShowGrass=False",
      "Description": "Not in the Video menu on PC. Present as False in most performance configs; reports disagree on whether it does anything in Performance Mode. Low risk, not a cvar edit.",
      "Section": "/Script/FortniteGame.FortGameUserSettings",
      "Key": "bShowGrass",
      "Value": "False"
    },
    "UTFNLobbyCap": {
      "Content": "Hidden key: lobby FPS cap 120",
      "Description": "FrontendFrameRateLimit=120 caps the lobby and menus so the GPU does not run flat out while you sit in the lobby. Not exposed in the PC menu.",
      "Section": "/Script/FortniteGame.FortGameUserSettings",
      "Key": "FrontendFrameRateLimit",
      "Value": "120"
    }
  },
  "LaunchArgs": {
    "Options": [
      { "Arg": "-NOSPLASH", "Content": "Skip the splash screen", "Description": "Parsed by the engine (WindowsPlatformSplash.cpp). Cosmetic, saves a second at launch.", "Default": true },
      { "Arg": "-FeatureLevelES31", "Content": "Force Performance Mode renderer", "Description": "Forces the ES3.1 feature level, which is what Performance Mode uses. Redundant if the profile already sets it, but guarantees it even if the game rewrites the config.", "Default": false },
      { "Arg": "-d3d12 -sm6", "Content": "Force DirectX 12 (Shader Model 6)", "Description": "Forces the D3D12 RHI and SM6. Use instead of the Performance Mode flag, never both.", "Default": false, "Excludes": "-FeatureLevelES31" },
      { "Arg": "-high -d3d11", "Content": "Legacy DirectX 11 Performance Mode (older NVIDIA cards)", "Description": "Brings back the DX11 renderer Epic removed from the Rendering Mode menu. The D3D11 RHI still ships and -d3d11 still forces it (verified on client 42.10: 'Using Forced RHI: D3D11'); the engine then caps at the ES3.1 feature level, so this is the old DX11 Performance Mode, not full DX11. It is also the only renderer on which the NVIDIA driver's LOD bias applies, so the Potato driver profile below needs this. Best bet on GTX 10/16-series and other older NVIDIA cards, or if DX12 Performance Mode stutters; on RTX cards with current drivers Epic's DX12 Performance Mode is usually better. -high is the pairing the community guides use: Unreal does not parse it and Windows ignores an unknown switch, so the DX11 half is what actually changes anything. Cannot be combined with the DirectX 12 flag.", "Default": false, "Excludes": "-d3d12 -sm6" },
      { "Arg": "-nosound", "Content": "No audio device", "Description": "Only for testing FPS without sound; you will not hear footsteps.", "Default": false }
    ],
    "Placebo": [
      { "Arg": "-USEALLAVAILABLECORES", "Reason": "In the engine source it only affects compressed archive worker threads. No FPS effect." },
      { "Arg": "-lanplay", "Reason": "Server-only code path (UWorld::Listen). Does nothing on a client." },
      { "Arg": "-limitclientticks", "Reason": "Server-only throttle of client connections. Does nothing on a client, and the =120 form never even matches." },
      { "Arg": "-PREFERREDPROCESSOR", "Reason": "Does not exist in the engine source at all; it only lives in old documentation." },
      { "Arg": "-high (on its own)", "Reason": "A Source engine switch Unreal never parses, so it sets no priority. Harmless, and it ships attached to the DX11 option because that is the pairing every guide uses; the DX11 half is what does the work." },
      { "Arg": "-malloc=system", "Reason": "Allocator switches are compiled out of Shipping builds." },
      { "Arg": "-NOVERIFYGC", "Reason": "Already off in Shipping builds." },
      { "Arg": "-NOTEXTURESTREAMING", "Reason": "Works and is harmful: loads every texture at full size and exhausts VRAM. Epic has a support article about removing it." },
      { "Arg": "-onethread", "Reason": "Disables the render thread. Massive FPS loss." }
    ]
  }
}
'@ | ConvertFrom-Json

$sync.configs.gameready = @'
{
  "Keep": {
    "Discord": "voice chat",
    "obs64": "recording or streaming",
    "obs32": "recording or streaming",
    "Streamlabs OBS": "streaming",
    "XSplit.Core": "streaming",
    "Medal": "clip recording",
    "Spotify": "music",
    "lghub": "Logitech G HUB: mouse and keyboard profiles",
    "lghub_agent": "Logitech G HUB",
    "RazerCentralService": "Razer device profiles",
    "Razer Synapse 3": "Razer device profiles",
    "Razer Synapse Service": "Razer device profiles",
    "iCUE": "Corsair device profiles",
    "SteelSeriesGG": "SteelSeries device profiles",
    "SteelSeriesEngine": "SteelSeries device profiles",
    "wallpaper32": "Wallpaper Engine pauses itself in games",
    "wallpaper64": "Wallpaper Engine pauses itself in games",
    "VoiceMeeter": "audio routing",
    "voicemeeter8x64": "audio routing",
    "voicemeeterpro": "audio routing"
  },
  "Background": {
    "OneDrive": "OneDrive sync",
    "Dropbox": "Dropbox sync",
    "GoogleDriveFS": "Google Drive sync",
    "iCloudDrive": "iCloud sync",
    "ms-teams": "Microsoft Teams",
    "Teams": "Microsoft Teams",
    "Slack": "Slack",
    "Zoom": "Zoom",
    "Skype": "Skype",
    "WhatsApp": "WhatsApp",
    "Telegram": "Telegram",
    "msedge": "Microsoft Edge",
    "chrome": "Google Chrome",
    "firefox": "Firefox",
    "brave": "Brave",
    "opera": "Opera",
    "vivaldi": "Vivaldi",
    "Adobe Desktop Service": "Adobe Creative Cloud",
    "Creative Cloud": "Adobe Creative Cloud",
    "CCXProcess": "Adobe Creative Cloud",
    "AdobeIPCBroker": "Adobe Creative Cloud",
    "Photoshop": "Photoshop",
    "Premiere Pro": "Premiere Pro",
    "Code": "VS Code",
    "Cursor": "Cursor",
    "devenv": "Visual Studio",
    "WINWORD": "Word",
    "EXCEL": "Excel",
    "POWERPNT": "PowerPoint",
    "OUTLOOK": "Outlook",
    "steam": "Steam",
    "steamwebhelper": "Steam browser",
    "EpicGamesLauncher": "Epic Games Launcher",
    "EpicWebHelper": "Epic Games Launcher browser",
    "Battle.net": "Battle.net",
    "EADesktop": "EA app",
    "EABackgroundService": "EA app",
    "UbisoftConnect": "Ubisoft Connect",
    "upc": "Ubisoft Connect",
    "GalaxyClient": "GOG Galaxy",
    "RiotClientUx": "Riot client",
    "RiotClientServices": "Riot client",
    "Riot Client": "Riot client",
    "NVIDIA app": "NVIDIA app",
    "NVIDIA Overlay": "NVIDIA overlay",
    "NVIDIA Share": "NVIDIA overlay",
    "nvsphelper64": "NVIDIA overlay",
    "RadeonSoftware": "AMD Software",
    "Overwolf": "Overwolf",
    "OverwolfHelper": "Overwolf",
    "MSIAfterburner": "MSI Afterburner",
    "RTSS": "RivaTuner",
    "HWiNFO64": "HWiNFO",
    "WallpaperEngine": "Wallpaper Engine",
    "Rainmeter": "Rainmeter",
    "SearchIndexer": "Windows Search indexer",
    "YourPhone": "Phone Link",
    "PhoneExperienceHost": "Phone Link",
    "Widgets": "Widgets",
    "WidgetService": "Widgets",
    "msteams": "Microsoft Teams",
    "javaw": "Java"
  }
}
'@ | ConvertFrom-Json

$sync.configs.games = @'
{
  "KnownGames": {
    "FortniteClient-Win64-Shipping": "Fortnite",
    "VALORANT-Win64-Shipping": "VALORANT",
    "cs2": "Counter-Strike 2",
    "csgo": "CS:GO",
    "r5apex": "Apex Legends",
    "r5apex_dx12": "Apex Legends",
    "Marvel-Win64-Shipping": "Marvel Rivals",
    "Overwatch": "Overwatch 2",
    "RobloxPlayerBeta": "Roblox",
    "GTA5": "GTA V",
    "GTA5_Enhanced": "GTA V Enhanced",
    "RainbowSix": "Rainbow Six Siege",
    "RainbowSix_Vulkan": "Rainbow Six Siege",
    "RainbowSix_DX11": "Rainbow Six Siege",
    "RocketLeague": "Rocket League",
    "cod": "Call of Duty",
    "ModernWarfare": "Call of Duty MW",
    "BlackOpsColdWar": "CoD Cold War",
    "bf6": "Battlefield 6",
    "BF2042": "Battlefield 2042",
    "Discovery": "The Finals",
    "EscapeFromTarkov": "Escape from Tarkov",
    "project8": "Deadlock",
    "PioneerGame": "ARC Raiders",
    "DeltaForceClient-Win64-Shipping": "Delta Force",
    "HaloInfinite": "Halo Infinite",
    "destiny2": "Destiny 2",
    "javaw": "Minecraft (Java)",
    "Minecraft.Windows": "Minecraft Bedrock",
    "League of Legends": "League of Legends",
    "TslGame": "PUBG",
    "DeadByDaylight-Win64-Shipping": "Dead by Daylight",
    "dota2": "Dota 2",
    "Warframe.x64": "Warframe",
    "eldenring": "Elden Ring",
    "Cyberpunk2077": "Cyberpunk 2077",
    "helldivers2": "Helldivers 2",
    "RustClient": "Rust",
    "HuntGame": "Hunt: Showdown",
    "SquadGame": "Squad",
    "aces": "War Thunder",
    "Palworld-Win64-Shipping": "Palworld",
    "NarakaBladepoint": "Naraka: Bladepoint",
    "GenshinImpact": "Genshin Impact",
    "bg3": "Baldur's Gate 3",
    "bg3_dx11": "Baldur's Gate 3",
    "Starfield": "Starfield"
  },
  "LibraryFolders": [
    "/steamapps/common/",
    "/Epic Games/",
    "/Riot Games/",
    "/Battle.net/",
    "/Blizzard/",
    "/EA Games/",
    "/Origin Games/",
    "/Ubisoft Game Launchers/games/",
    "/XboxGames/",
    "/GOG Galaxy/Games/",
    "/GOG Games/"
  ],
  "LauncherProcesses": [
    "steam", "steamwebhelper", "steamservice", "EpicGamesLauncher", "EpicWebHelper", "EpicOnlineServicesUserHelper",
    "RiotClientServices", "RiotClientUx", "RiotClientUxRender", "RiotClientCrashHandler", "Battle.net", "Agent",
    "EADesktop", "EABackgroundService", "EALocalHostSvc", "upc", "UbisoftConnect", "UplayWebCore", "GalaxyClient",
    "GalaxyClientService", "XboxPcApp", "gamelaunchhelper", "start_protected_game", "EasyAntiCheat_EOS_Setup",
    "CrashReportClient", "UnrealCEFSubProcess", "FortniteLauncher", "VALORANT", "LeagueClient", "LeagueClientUx"
  ],
  "ShellBlacklist": [
    "explorer", "ApplicationFrameHost", "LockApp", "SearchHost", "SearchApp", "SearchUI", "StartMenuExperienceHost",
    "ShellExperienceHost", "dwm", "TextInputHost", "Widgets", "LogonUI", "csrss", "winlogon", "Taskmgr", "SystemSettings",
    "sihost", "powershell", "powershell_ise", "pwsh", "WindowsTerminal", "conhost", "msedge", "chrome", "firefox", "brave",
    "Discord", "steam", "steamwebhelper", "EpicGamesLauncher", "EpicWebHelper", "RiotClientUx", "RiotClientServices", "Code", "devenv"
  ]
}
'@ | ConvertFrom-Json

$sync.configs.gameservers = @'
{
  "Fortnite": {
    "Note": "Epic's own datacenter ping hosts, the same ones the in-game region selector and Epic support use. All resolve to AWS. ping-me may not answer ICMP from every ISP; no reply does not mean the region is down.",
    "Regions": [
      { "Region": "NA-East", "Host": "ping-nae.ds.on.epicgames.com", "Location": "Ohio / Virginia" },
      { "Region": "NA-Central", "Host": "ping-nac.ds.on.epicgames.com", "Location": "Dallas" },
      { "Region": "NA-West", "Host": "ping-naw.ds.on.epicgames.com", "Location": "Oregon / N. California" },
      { "Region": "Europe", "Host": "ping-eu.ds.on.epicgames.com", "Location": "Paris / Frankfurt / London" },
      { "Region": "Oceania", "Host": "ping-oce.ds.on.epicgames.com", "Location": "Sydney" },
      { "Region": "Brazil", "Host": "ping-br.ds.on.epicgames.com", "Location": "Sao Paulo" },
      { "Region": "Asia", "Host": "ping-asia.ds.on.epicgames.com", "Location": "Tokyo" },
      { "Region": "Middle East", "Host": "ping-me.ds.on.epicgames.com", "Location": "Bahrain" }
    ]
  },
  "Baseline": [
    { "Region": "Internet (Cloudflare)", "Host": "1.1.1.1", "Location": "nearest anycast edge" }
  ]
}
'@ | ConvertFrom-Json

$sync.configs.nvprofile = @'
{
  "Application": "FortniteClient-Win64-Shipping.exe",
  "ProfileName": "Fortnite",
  "Presets": {
    "Performance": {
      "Content": "Performance (no visual change)",
      "Description": "The driver-side settings that cost nothing to look at: the GPU stays at its performance clocks instead of drifting down, texture filtering optimisations on, VSync forced off, and one pre-rendered frame. Nothing here blurs anything. These apply on DirectX 11 and 12 except the pre-rendered frame limit, which DirectX 12 leaves to the game.",
      "Settings": [
        { "Name": "Power management mode", "Id": "0x1057EB71", "Value": "0x00000001", "Means": "prefer maximum performance" },
        { "Name": "Texture filtering - Quality", "Id": "0x00CE2691", "Value": "0x00000014", "Means": "high performance" },
        { "Name": "Texture filtering - Anisotropic sample optimization", "Id": "0x00E73211", "Value": "0x00000001", "Means": "on" },
        { "Name": "Texture filtering - Anisotropic filter optimization", "Id": "0x0084CD70", "Value": "0x00000001", "Means": "on" },
        { "Name": "Texture filtering - Trilinear optimization", "Id": "0x002ECAF2", "Value": "0x00000001", "Means": "on" },
        { "Name": "Vertical Sync", "Id": "0x00A879CF", "Value": "0x08416747", "Means": "force off" },
        { "Name": "Maximum pre-rendered frames", "Id": "0x007BA09E", "Value": "0x00000001", "Means": "1" }
      ]
    },
    "Potato": {
      "Content": "Potato (blurry textures, DirectX 11 only)",
      "Description": "EXPERIMENTAL. Everything in Performance, plus anisotropic filtering forced to its lowest and a positive texture LOD bias of +3.0, which is what makes textures look like a potato. The driver only applies LOD bias on DirectX 11 and older: on DirectX 12 the game owns sampler state and this does nothing at all, so pair it with the -high -d3d11 launch argument or you will see no difference. The bias is deliberately positive (blurrier). A negative bias sharpens distant textures and is the version that gets argued about in competitive rules, so it is not offered.",
      "Settings": [
        { "Name": "Power management mode", "Id": "0x1057EB71", "Value": "0x00000001", "Means": "prefer maximum performance" },
        { "Name": "Texture filtering - Quality", "Id": "0x00CE2691", "Value": "0x00000014", "Means": "high performance" },
        { "Name": "Texture filtering - Anisotropic sample optimization", "Id": "0x00E73211", "Value": "0x00000001", "Means": "on" },
        { "Name": "Texture filtering - Anisotropic filter optimization", "Id": "0x0084CD70", "Value": "0x00000001", "Means": "on" },
        { "Name": "Texture filtering - Trilinear optimization", "Id": "0x002ECAF2", "Value": "0x00000001", "Means": "on" },
        { "Name": "Vertical Sync", "Id": "0x00A879CF", "Value": "0x08416747", "Means": "force off" },
        { "Name": "Maximum pre-rendered frames", "Id": "0x007BA09E", "Value": "0x00000001", "Means": "1" },
        { "Name": "Anisotropic filtering mode", "Id": "0x10D2BB16", "Value": "0x00000001", "Means": "user defined" },
        { "Name": "Anisotropic filtering setting", "Id": "0x101E61A9", "Value": "0x00000000", "Means": "1x (off)" },
        { "Name": "Texture filtering - Driver Controlled LOD Bias", "Id": "0x00638E8F", "Value": "0x00000000", "Means": "off, so the manual bias below is used" },
        { "Name": "Texture filtering - LOD Bias", "Id": "0x00738E8F", "Value": "0x00000018", "Means": "+3.0 (blurrier)" }
      ]
    }
  }
}
'@ | ConvertFrom-Json

$sync.configs.simple = @'
{
  "Games": {
    "Fortnite": {
      "Content": "FORTNITE",
      "Order": 1,
      "Steps": [
        { "Kind": "restorepoint", "When": "always", "Text": "Create a restore point", "Detail": "so all of this can be rolled back in one step" },
        { "Kind": "tweaks", "When": "always", "Text": "Apply the safe tweak preset", "Detail": "documented Windows settings with no meaningful downside; each one is snapshotted first" },
        { "Kind": "fortnite-profile", "Value": "MaxFPS", "When": "always", "Text": "Set Fortnite to Performance Mode, everything low", "Detail": "only keys the in-game Video menu writes, merged into your config with a backup" },
        { "Kind": "fortnite-args", "Value": "-NOSPLASH -high -d3d11", "When": "legacy-gpu", "Text": "Write the -high -d3d11 launch arguments", "Detail": "the legacy DX11 renderer, which suits this GPU better than DX12 Performance Mode" },
        { "Kind": "fortnite-args", "Value": "-NOSPLASH", "When": "modern-gpu", "Text": "Write the -NOSPLASH launch argument", "Detail": "this GPU is happier on Epic's DX12 Performance Mode, so the DX11 switch is left off" },
        { "Kind": "nvprofile", "Value": "Performance", "When": "nvidia", "Text": "Set the NVIDIA driver profile to Performance", "Detail": "power management, filtering and VSync; nothing that changes how the game looks" }
      ]
    },
    "Valorant": {
      "Content": "VALORANT",
      "Order": 2,
      "Steps": [
        { "Kind": "restorepoint", "When": "always", "Text": "Create a restore point", "Detail": "so all of this can be rolled back in one step" },
        { "Kind": "tweaks", "When": "always", "Text": "Apply the safe tweak preset", "Detail": "documented Windows settings with no meaningful downside; each one is snapshotted first" },
        { "Kind": "valorant-profile", "Value": "MaxFPS", "When": "always", "Text": "Set VALORANT graphics to their lowest", "Detail": "every quality group down, Reflex On+Boost, VSync off, frame cap off; both settings files backed up first" }
      ]
    },
    "Other": {
      "Content": "ANY OTHER GAME",
      "Order": 3,
      "Steps": [
        { "Kind": "restorepoint", "When": "always", "Text": "Create a restore point", "Detail": "so all of this can be rolled back in one step" },
        { "Kind": "tweaks", "When": "always", "Text": "Apply the safe tweak preset", "Detail": "the Windows-side work, which is what helps every game; no per-game settings are touched" }
      ]
    }
  }
}
'@ | ConvertFrom-Json

$sync.configs.stretched = @'
{
  "Ratios": [
    { "Name": "4:3",   "Ratio": 1.333333, "ValorantRatio": true,  "Label": "widest player models, the most popular competitive pick", "Common": "Fortnite, VALORANT, CS2" },
    { "Name": "5:4",   "Ratio": 1.250000, "ValorantRatio": true,  "Label": "wider still than 4:3, the old 1280x1024 shape",           "Common": "VALORANT, CS2" },
    { "Name": "40:27", "Ratio": 1.481481, "ValorantRatio": false, "Label": "the mid-range stretch most Fortnite pros land on",        "Common": "Fortnite" },
    { "Name": "14:9",  "Ratio": 1.555556, "ValorantRatio": false, "Label": "mild stretch that keeps detail; widely used in VALORANT despite not being one of Riot's documented ratios", "Common": "VALORANT, Fortnite" },
    { "Name": "43:27", "Ratio": 1.592593, "ValorantRatio": false, "Label": "subtle stretch, sharper than 4:3",                        "Common": "Fortnite" },
    { "Name": "16:10", "Ratio": 1.600000, "ValorantRatio": true,  "Label": "the gentlest stretch, closest to native",                 "Common": "Fortnite, VALORANT" }
  ],
  "Games": {
    "None":     { "Content": "Desktop only (I will start the game myself)" },
    "Fortnite": { "Content": "Fortnite: write the resolution into GameUserSettings.ini and launch through Epic" },
    "Valorant": { "Content": "VALORANT: disable the monitor so the game accepts the resolution, then launch through Riot" }
  }
}
'@ | ConvertFrom-Json

$sync.configs.tweaks = @'
{
  "UTGameDVR": {
    "Content": "Game DVR / background recording off",
    "Description": "Stops Windows from recording gameplay in the background (Game Bar capture). Removes a capture and encode pipeline that runs while you play. Microsoft ships a policy for exactly this.",
    "Evidence": "Game DVR is a real capture-and-encode pipeline that runs while you play. AllowGameDVR is the Group Policy Microsoft ships for exactly this (Microsoft Learn, GameDVR policy). Confidence: high.",
    "Category": "Gaming",
    "Tier": "safe",
    "Recommended": true,
    "Order": 10,
    "registry": [
      {
        "Path": "HKCU:\\System\\GameConfigStore",
        "Name": "GameDVR_Enabled",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\GameDVR",
        "Name": "AppCaptureEnabled",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\GameDVR",
        "Name": "AllowGameDVR",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "<RemoveEntry>"
      }
    ]
  },
  "UTMouseAccel": {
    "Content": "Mouse acceleration off (Enhance pointer precision)",
    "Description": "Sets MouseSpeed and both thresholds to 0 so pointer distance no longer depends on how fast you move. Most games use raw input already; this fixes the desktop, menus and games that do not. Takes effect after sign-out.",
    "Evidence": "MouseSpeed, MouseThreshold1 and MouseThreshold2 are the values behind Enhance pointer precision, and 0/0/0 is what unticking it writes. They are REG_SZ; tools that write them as DWORD are wrong. Confidence: high.",
    "Category": "Input",
    "Tier": "safe",
    "Recommended": true,
    "Order": 20,
    "SignOut": true,
    "registry": [
      {
        "Path": "HKCU:\\Control Panel\\Mouse",
        "Name": "MouseSpeed",
        "Type": "String",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKCU:\\Control Panel\\Mouse",
        "Name": "MouseThreshold1",
        "Type": "String",
        "Value": "0",
        "OriginalValue": "6"
      },
      {
        "Path": "HKCU:\\Control Panel\\Mouse",
        "Name": "MouseThreshold2",
        "Type": "String",
        "Value": "0",
        "OriginalValue": "10"
      }
    ]
  },
  "UTAccessibilityKeys": {
    "Content": "Sticky / Toggle / Filter Keys shortcuts off",
    "Description": "Stops the Shift x5, Num Lock 8s and Right Shift 8s pop-ups that steal focus mid-game. Accessibility features stay available from Settings.",
    "Evidence": "Flags 510 to 506, 62 to 58 and 126 to 122 each clear one bit, the HOTKEYACTIVE flag, so only the keyboard shortcut goes and the features stay available in Settings. Verified arithmetically against the documented flag bits. Confidence: high.",
    "Category": "Input",
    "Tier": "safe",
    "Recommended": true,
    "Order": 21,
    "registry": [
      {
        "Path": "HKCU:\\Control Panel\\Accessibility\\StickyKeys",
        "Name": "Flags",
        "Type": "String",
        "Value": "506",
        "OriginalValue": "510"
      },
      {
        "Path": "HKCU:\\Control Panel\\Accessibility\\ToggleKeys",
        "Name": "Flags",
        "Type": "String",
        "Value": "58",
        "OriginalValue": "62"
      },
      {
        "Path": "HKCU:\\Control Panel\\Accessibility\\Keyboard Response",
        "Name": "Flags",
        "Type": "String",
        "Value": "122",
        "OriginalValue": "126"
      }
    ]
  },
  "UTEdgeBackground": {
    "Content": "Edge startup boost and background mode off",
    "Description": "Stops Microsoft Edge from pre-launching at sign-in and lingering in the background after you close it. Documented Edge policies.",
    "Evidence": "StartupBoostEnabled and BackgroundModeEnabled are documented Microsoft Edge policies (Microsoft Edge policy reference). 0 stops Edge pre-launching at sign-in and lingering after the last window closes. Confidence: high.",
    "Category": "Background load",
    "Tier": "safe",
    "Recommended": true,
    "Order": 30,
    "registry": [
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge",
        "Name": "StartupBoostEnabled",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "<RemoveEntry>"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge",
        "Name": "BackgroundModeEnabled",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "<RemoveEntry>"
      }
    ]
  },
  "UTWidgets": {
    "Content": "Widgets / news feed off",
    "Description": "Disables the Widgets board and its WebExperience background process (Windows 11) and the news and interests feed (Windows 10).",
    "Evidence": "AllowNewsAndInterests (Windows 11 Widgets) and EnableFeeds (Windows 10 news and interests) are the Group Policy values; EnableFeeds was read out of C:\\Windows\\PolicyDefinitions\\Feeds.admx on a live Windows 10 build. Widgets keeps a WebExperience process alive while enabled. Confidence: high.",
    "Category": "Background load",
    "Tier": "safe",
    "Recommended": true,
    "Order": 31,
    "registry": [
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Dsh",
        "Name": "AllowNewsAndInterests",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "<RemoveEntry>"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Windows Feeds",
        "Name": "EnableFeeds",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "<RemoveEntry>"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
        "Name": "TaskbarDa",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "<RemoveEntry>"
      }
    ],
    "SignOut": true
  },
  "UTSearchCopilotRecall": {
    "Content": "Web search in Start, Copilot data analysis and Recall off",
    "Description": "Keeps Start menu search local (no Bing results), and sets the Windows 11 24H2 policies that disable Recall and AI data analysis. Uses the current keys; the old TurnOffWindowsCopilot policy is deprecated.",
    "Evidence": "DisableSearchBoxSuggestions and BingSearchEnabled are the documented keys for local-only Start search; DisableAIDataAnalysis is the Windows 11 24H2 policy that disables Recall (Microsoft Learn, WindowsAI policies). The older TurnOffWindowsCopilot policy is deprecated. Confidence: high.",
    "Category": "Privacy",
    "Tier": "safe",
    "Recommended": true,
    "Order": 40,
    "registry": [
      {
        "Path": "HKCU:\\Software\\Policies\\Microsoft\\Windows\\Explorer",
        "Name": "DisableSearchBoxSuggestions",
        "Type": "DWord",
        "Value": "1",
        "OriginalValue": "<RemoveEntry>"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Search",
        "Name": "BingSearchEnabled",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "<RemoveEntry>"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsAI",
        "Name": "DisableAIDataAnalysis",
        "Type": "DWord",
        "Value": "1",
        "OriginalValue": "<RemoveEntry>"
      },
      {
        "Path": "HKCU:\\Software\\Policies\\Microsoft\\Windows\\WindowsAI",
        "Name": "DisableAIDataAnalysis",
        "Type": "DWord",
        "Value": "1",
        "OriginalValue": "<RemoveEntry>"
      }
    ],
    "SignOut": true
  },
  "UTTelemetry": {
    "Content": "Telemetry, feedback prompts, error reporting and appraiser tasks off",
    "Description": "Sets diagnostic data to the minimum Home/Pro honours, disables the DiagTrack service, the Compatibility Appraiser and CEIP scheduled tasks (the appraiser is the one that scans your drive at high load), feedback prompts and Windows Error Reporting uploads.",
    "Evidence": "AllowTelemetry=1 is the lowest level Home and Pro honour; 0 only applies to Enterprise (Microsoft Learn). DiagTrack is the Connected User Experiences and Telemetry service. The Compatibility Appraiser is the task that scans the drive at high load, and the CEIP tasks' own Task Scheduler descriptions say they collect and upload usage data (read on a live Windows 10 machine). Confidence: high for the keys, medium for any FPS effect.",
    "Category": "Privacy",
    "Tier": "safe",
    "Recommended": true,
    "Order": 41,
    "registry": [
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\DataCollection",
        "Name": "AllowTelemetry",
        "Type": "DWord",
        "Value": "1",
        "OriginalValue": "<RemoveEntry>"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\AdvertisingInfo",
        "Name": "Enabled",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Privacy",
        "Name": "TailoredExperiencesWithDiagnosticDataEnabled",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Siuf\\Rules",
        "Name": "NumberOfSIUFInPeriod",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "<RemoveEntry>"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Windows Error Reporting",
        "Name": "Disabled",
        "Type": "DWord",
        "Value": "1",
        "OriginalValue": "<RemoveEntry>"
      }
    ],
    "service": [
      {
        "Name": "DiagTrack",
        "StartupType": "Disabled",
        "OriginalType": "Automatic"
      }
    ],
    "ScheduledTask": [
      {
        "Name": "\\Microsoft\\Windows\\Application Experience\\Microsoft Compatibility Appraiser",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "\\Microsoft\\Windows\\Application Experience\\ProgramDataUpdater",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "\\Microsoft\\Windows\\Customer Experience Improvement Program\\Consolidator",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "\\Microsoft\\Windows\\Customer Experience Improvement Program\\UsbCeip",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "\\Microsoft\\Windows\\DiskDiagnostic\\Microsoft-Windows-DiskDiagnosticDataCollector",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "\\Microsoft\\Windows\\Windows Error Reporting\\QueueReporting",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "\\Microsoft\\Windows\\Feedback\\Siuf\\DmClient",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "\\Microsoft\\Windows\\Feedback\\Siuf\\DmClientOnScenarioDownload",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "\\Microsoft\\Windows\\Maps\\MapsUpdateTask",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "\\Microsoft\\Windows\\Autochk\\Proxy",
        "State": "Disabled",
        "OriginalState": "Enabled"
      }
    ],
    "Reboot": true
  },
  "UTSuggestions": {
    "Content": "Start / lock screen / Settings suggestions and silent app installs off",
    "Description": "Turns off promoted apps, tips and suggestions delivered by the Content Delivery Manager, and the consumer features policy that silently installs sponsored apps.",
    "Evidence": "The SubscribedContent values are the switches behind the Settings suggestion toggles, and DisableWindowsConsumerFeatures is the policy that stops sponsored apps being installed silently (Microsoft Learn, CloudContent policy). Confidence: medium.",
    "Category": "Privacy",
    "Tier": "safe",
    "Recommended": true,
    "Order": 42,
    "registry": [
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
        "Name": "SubscribedContent-338388Enabled",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
        "Name": "SubscribedContent-338389Enabled",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
        "Name": "SubscribedContent-353698Enabled",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
        "Name": "SilentInstalledAppsEnabled",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
        "Name": "SystemPaneSuggestionsEnabled",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\CloudContent",
        "Name": "DisableWindowsConsumerFeatures",
        "Type": "DWord",
        "Value": "1",
        "OriginalValue": "<RemoveEntry>"
      }
    ],
    "SignOut": true
  },
  "UTActivityHistory": {
    "Content": "Activity history publishing and upload off",
    "Description": "Stops Windows from collecting and uploading your activity timeline. Clipboard history is not affected.",
    "Evidence": "EnableActivityFeed, PublishUserActivities and UploadUserActivities are the three documented Activity History policies (Microsoft Learn). 0 is the correct value for all three; some tools write EnableActivityFeed=1 by mistake. Confidence: high.",
    "Category": "Privacy",
    "Tier": "safe",
    "Recommended": true,
    "Order": 43,
    "registry": [
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System",
        "Name": "EnableActivityFeed",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "<RemoveEntry>"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System",
        "Name": "PublishUserActivities",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "<RemoveEntry>"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System",
        "Name": "UploadUserActivities",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "<RemoveEntry>"
      }
    ]
  },
  "UTDeliveryOptimization": {
    "Content": "Delivery Optimization peer uploads off",
    "Description": "Stops Windows Update from uploading updates to other PCs on the internet. Peer uploads are the one background feature that can raise your ping and packet loss during a match on a slow upload line. Downloads keep working over HTTP.",
    "Evidence": "DODownloadMode=0 is the documented HTTP-only mode: Windows Update downloads normally and never uploads to other PCs (Microsoft Learn, Delivery Optimization reference). Mode 100 (bypass) is deprecated and not used. Confidence: high.",
    "Category": "Network",
    "Tier": "safe",
    "Recommended": true,
    "Order": 50,
    "registry": [
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\DeliveryOptimization",
        "Name": "DODownloadMode",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "<RemoveEntry>"
      }
    ]
  },
  "UTWUDrivers": {
    "Content": "Windows Update no longer replaces your GPU driver",
    "Description": "Excludes drivers from quality updates and stops device installation from searching Windows Update. A common cause of sudden FPS drops is Windows swapping a fresh GeForce or Adrenalin driver for an older WHQL one after a reboot.",
    "Evidence": "ExcludeWUDriversInQualityUpdate is the Windows Update policy that stops Windows swapping your GPU or chipset driver for an older WHQL one, and SearchOrderConfig=0 is the Device Installation setting under it (Microsoft Learn). Confidence: high.",
    "Category": "Stability",
    "Tier": "safe",
    "Recommended": true,
    "Order": 60,
    "registry": [
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate",
        "Name": "ExcludeWUDriversInQualityUpdate",
        "Type": "DWord",
        "Value": "1",
        "OriginalValue": "<RemoveEntry>"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\DriverSearching",
        "Name": "SearchOrderConfig",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      }
    ]
  },
  "UTFastStartupOff": {
    "Content": "Fast startup off (true cold boot on shutdown)",
    "Description": "With fast startup, Shut down only hibernates the kernel, so GPU driver state and overlay hooks survive for weeks. A real cold boot fixes the class of stutter that a restart magically cures. Hibernation itself stays available.",
    "Evidence": "HiberbootEnabled=0 turns off Fast Startup (hybrid shutdown), so a shutdown is a real cold boot and drivers reinitialise instead of resuming from a hibernation image (Microsoft Learn, Fast startup). Hibernation itself is untouched. Confidence: medium.",
    "Category": "Stability",
    "Tier": "safe",
    "Recommended": true,
    "Order": 61,
    "registry": [
      {
        "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Power",
        "Name": "HiberbootEnabled",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      }
    ],
    "Reboot": true
  },
  "UTExplorerQoL": {
    "Content": "Show file extensions and End task on the taskbar",
    "Description": "Shows real file extensions and adds End task to the taskbar right-click menu (Windows 11 23H2+), handy for a hung game.",
    "Evidence": "HideFileExt is the value behind Explorer's File name extensions switch and TaskbarEndTask is the Settings > For developers End task switch. Quality of life only. Confidence: medium.",
    "Category": "Quality of life",
    "Tier": "safe",
    "Recommended": true,
    "Order": 70,
    "registry": [
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
        "Name": "HideFileExt",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced\\TaskbarDeveloperSettings",
        "Name": "TaskbarEndTask",
        "Type": "DWord",
        "Value": "1",
        "OriginalValue": "<RemoveEntry>"
      }
    ],
    "SignOut": true
  },
  "UTStartupDelay": {
    "Content": "Startup app delay removed",
    "Description": "Removes the delay Windows adds before launching startup apps after sign-in. Only affects boot, not gameplay.",
    "Evidence": "StartupDelayInMSec is the Explorer serialization delay that holds Run and Startup-folder entries back for around ten seconds after sign-in; 0 removes the hold. Widely documented, not an official Microsoft setting. Confidence: medium.",
    "Category": "Quality of life",
    "Tier": "safe",
    "Recommended": false,
    "Order": 71,
    "registry": [
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Serialize",
        "Name": "StartupDelayInMSec",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "<RemoveEntry>"
      }
    ]
  },
  "UTWindowedGamesOpt": {
    "Content": "Optimizations for windowed games on (Windows 11)",
    "Description": "Moves DirectX 10/11 games running windowed or borderless to the flip presentation model, which Microsoft says reduces frame latency and enables VRR and Auto HDR. Merged into the existing setting string; nothing else in it is touched.",
    "Evidence": "SwapEffectUpgradeEnable=1 in DirectXUserGlobalSettings is what the Settings > Graphics Optimizations for windowed games switch writes. It upgrades legacy blt-model presentation to flip model, which Microsoft says lowers latency (Microsoft DirectX blog). Windows 11 22H2 or newer. Confidence: high for the mechanism, medium for the key.",
    "Category": "Gaming",
    "Tier": "safe",
    "Recommended": true,
    "Order": 11,
    "MinBuild": 22621,
    "InvokeScript": [
      "$p = 'HKCU:\\Software\\Microsoft\\DirectX\\UserGpuPreferences'; if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }; $v = (Get-ItemProperty $p -Name DirectXUserGlobalSettings -ErrorAction SilentlyContinue).DirectXUserGlobalSettings; Save-UTScriptState -Id UTWindowedGamesOpt -Key Previous -Value ([string]$v); $tokens = @(); if ($v) { $tokens = @($v -split ';' | Where-Object { $_ -and $_ -notmatch '^SwapEffectUpgradeEnable=' }) }; $tokens += 'SwapEffectUpgradeEnable=1'; Set-ItemProperty $p -Name DirectXUserGlobalSettings -Type String -Value (($tokens -join ';') + ';')"
    ],
    "UndoScript": [
      "$p = 'HKCU:\\Software\\Microsoft\\DirectX\\UserGpuPreferences'; $prev = Get-UTScriptState -Id UTWindowedGamesOpt -Key Previous; if ([string]::IsNullOrEmpty($prev)) { Remove-ItemProperty $p -Name DirectXUserGlobalSettings -ErrorAction SilentlyContinue } else { Set-ItemProperty $p -Name DirectXUserGlobalSettings -Type String -Value $prev }"
    ]
  },
  "UTUsbPcieNoSleep": {
    "Content": "USB selective suspend and PCIe link power saving off (plugged in)",
    "Description": "Stops USB devices (mouse, keyboard, headset DAC) and the PCIe link from entering low-power states while plugged in. Prevents the wake-up hitch and the rare device drop-out. Battery settings are not changed.",
    "Evidence": "USB selective suspend (48e6b7a6) and PCI Express Link State Power Management (ee12f906) are documented power setting GUIDs (Microsoft Learn); index 0 is off. Only the plugged-in value is changed. Confidence: high.",
    "Category": "Power",
    "Tier": "safe",
    "Recommended": true,
    "Order": 80,
    "InvokeScript": [
      "$usb = Get-UTPowerCfgIndex -SubGroup '2a737441-1930-4402-8d77-b2bebba308a3' -Setting '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'; $pci = Get-UTPowerCfgIndex -SubGroup '501a4d13-42af-4429-9fd1-a8218c268e20' -Setting 'ee12f906-d277-404b-b6da-e5fa1a576df5'; Save-UTScriptState -Id UTUsbPcieNoSleep -Key Usb -Value $usb; Save-UTScriptState -Id UTUsbPcieNoSleep -Key Pci -Value $pci; Set-UTPowerCfgIndex -SubGroup '2a737441-1930-4402-8d77-b2bebba308a3' -Setting '48e6b7a6-50f5-4782-a5d4-53bb8f07e226' -Index 0 -What 'USB selective suspend'; Set-UTPowerCfgIndex -SubGroup '501a4d13-42af-4429-9fd1-a8218c268e20' -Setting 'ee12f906-d277-404b-b6da-e5fa1a576df5' -Index 0 -What 'PCIe link state power management'"
    ],
    "UndoScript": [
      "$usb = Get-UTScriptState -Id UTUsbPcieNoSleep -Key Usb; if ($null -eq $usb) { $usb = 1 }; $pci = Get-UTScriptState -Id UTUsbPcieNoSleep -Key Pci; if ($null -eq $pci) { $pci = 1 }; Set-UTPowerCfgIndex -SubGroup '2a737441-1930-4402-8d77-b2bebba308a3' -Setting '48e6b7a6-50f5-4782-a5d4-53bb8f07e226' -Index ([uint32]$usb) -What 'USB selective suspend'; Set-UTPowerCfgIndex -SubGroup '501a4d13-42af-4429-9fd1-a8218c268e20' -Setting 'ee12f906-d277-404b-b6da-e5fa1a576df5' -Index ([uint32]$pci) -What 'PCIe link state power management'"
    ]
  },
  "UTTempFiles": {
    "Content": "Clear temporary files",
    "Description": "Deletes the contents of your user TEMP folder and C:\\Windows\\Temp. Files in use are skipped. Nothing to undo.",
    "Evidence": "Deletes the contents of %TEMP% and C:\\Windows\\Temp; anything in use is skipped. Disk space only, no performance claim. Confidence: high.",
    "Category": "Cleanup",
    "Tier": "safe",
    "Recommended": true,
    "Order": 90,
    "InvokeScript": [
      "Remove-Item -Path \"$env:TEMP\\*\" -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item -Path \"$env:SystemRoot\\Temp\\*\" -Recurse -Force -ErrorAction SilentlyContinue; Write-UTLog 'Temporary files cleared (files in use were skipped)'"
    ]
  },
  "UTHAGS": {
    "Content": "Hardware-accelerated GPU scheduling on",
    "Description": "Lets the GPU manage its own scheduling. Required for DLSS Frame Generation and the Windows 11 24H2 hardware flip queue. Recommended on GTX 10 / RX 5000 or newer with a recent driver; older GPUs should skip it. Reboot required.",
    "Evidence": "HwSchMode=2 is the registry value behind Settings > Graphics Hardware-accelerated GPU scheduling. Gamers Nexus and BabelTechReviews both measured roughly zero average FPS change; the real reasons to enable it are DLSS Frame Generation, which requires it, and the Windows 11 24H2 flip queue. Confidence: high.",
    "Category": "Gaming",
    "Tier": "optional",
    "Recommended": false,
    "Order": 100,
    "Reboot": true,
    "registry": [
      {
        "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\GraphicsDrivers",
        "Name": "HwSchMode",
        "Type": "DWord",
        "Value": "2",
        "OriginalValue": "<RemoveEntry>"
      }
    ]
  },
  "UTGameModeOff": {
    "Content": "Windows Game Mode off",
    "Description": "Game Mode stops driver installs and update restarts while you play and gives the game scheduling priority. Most people should leave it on; try turning it off only if you get periodic stutter with it enabled.",
    "Evidence": "AutoGameModeEnabled=0 is the Settings > Gaming Game Mode switch. Community results are split: Microsoft's default is on, and some systems stutter less with it off. A troubleshooting step, not a boost. Confidence: medium.",
    "Category": "Gaming",
    "Tier": "optional",
    "Recommended": false,
    "Order": 101,
    "registry": [
      {
        "Path": "HKCU:\\Software\\Microsoft\\GameBar",
        "Name": "AutoGameModeEnabled",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "<RemoveEntry>"
      }
    ]
  },
  "UTGameBarPopups": {
    "Content": "Game Bar pop-ups and controller button off",
    "Description": "Stops the Game Bar overlay from opening on the Xbox button and the startup panel from appearing. No FPS effect, pure quality of life.",
    "Evidence": "ShowStartupPanel and UseNexusForGameBarEnabled are the Game Bar settings behind the Open Game Bar prompt and the Xbox button. Quality of life only. Confidence: medium.",
    "Category": "Gaming",
    "Tier": "optional",
    "Recommended": false,
    "Order": 102,
    "registry": [
      {
        "Path": "HKCU:\\Software\\Microsoft\\GameBar",
        "Name": "ShowStartupPanel",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "<RemoveEntry>"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\GameBar",
        "Name": "UseNexusForGameBarEnabled",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "<RemoveEntry>"
      }
    ]
  },
  "UTFSOGlobalOff": {
    "Content": "Fullscreen optimizations off for all games",
    "Description": "Global equivalent of the per-exe Disable fullscreen optimizations checkbox. Microsoft says the optimizations perform as well or better, and Windows ignores the setting entirely for DirectX 12 titles - so a Fortnite running DX12 or DX12 Performance Mode gains nothing and only loses the Auto HDR and VRR paths. It does apply if you launch Fortnite with the -d3d11 argument from the FORTNITE tab, and to specific old DirectX 9/11 games that misbehave.",
    "Evidence": "GameDVR_FSEBehaviorMode and the related GameConfigStore values are what the per-exe Disable fullscreen optimizations checkbox writes, applied globally. Windows ignores them entirely for DirectX 12 titles (Microsoft Q&A), so they only matter for DirectX 9/11 games, including Fortnite launched with -d3d11. Confidence: medium.",
    "Category": "Gaming",
    "Tier": "optional",
    "Recommended": false,
    "Order": 103,
    "registry": [
      {
        "Path": "HKCU:\\System\\GameConfigStore",
        "Name": "GameDVR_FSEBehaviorMode",
        "Type": "DWord",
        "Value": "2",
        "OriginalValue": "<RemoveEntry>"
      },
      {
        "Path": "HKCU:\\System\\GameConfigStore",
        "Name": "GameDVR_HonorUserFSEBehaviorMode",
        "Type": "DWord",
        "Value": "1",
        "OriginalValue": "<RemoveEntry>"
      },
      {
        "Path": "HKCU:\\System\\GameConfigStore",
        "Name": "GameDVR_DXGIHonorFSEWindowsCompatible",
        "Type": "DWord",
        "Value": "1",
        "OriginalValue": "<RemoveEntry>"
      },
      {
        "Path": "HKCU:\\System\\GameConfigStore",
        "Name": "GameDVR_EFSEFeatureFlags",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "<RemoveEntry>"
      }
    ]
  },
  "UTPowerThrottlingOff": {
    "Content": "Power throttling of background apps off (laptops on AC)",
    "Description": "Windows never throttles the focused game, only background apps, so this helps laptops that run Discord, browsers or overlays alongside the game while plugged in. No effect on desktops.",
    "Evidence": "PowerThrottlingOff=1 disables Power Throttling, the Windows 10 1709+ feature that lowers background CPU frequency on laptops (Microsoft Learn, Power throttling). No effect on desktops. Confidence: high.",
    "Category": "Power",
    "Tier": "optional",
    "Recommended": false,
    "Order": 110,
    "registry": [
      {
        "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Power\\PowerThrottling",
        "Name": "PowerThrottlingOff",
        "Type": "DWord",
        "Value": "1",
        "OriginalValue": "<RemoveEntry>"
      }
    ],
    "Reboot": true
  },
  "UTUltimatePerf": {
    "Content": "Ultimate Performance power plan (desktop)",
    "Description": "Creates and activates the hidden Ultimate Performance plan. On modern CPUs with hardware P-states the FPS difference is negligible; it does keep clocks from dipping between scenes. Costs heat and idle power. Not for laptops on battery.",
    "Evidence": "e9a42b02-d5df-448d-aa00-03f14749eb61 is Microsoft's Ultimate Performance scheme (Microsoft Learn). The measured difference to High Performance is inside noise on CPUs with hardware P-states, and at least one test found worse 1 percent lows. Confidence: high for the mechanism, low for any gain.",
    "Category": "Power",
    "Tier": "optional",
    "Recommended": false,
    "Order": 111,
    "LaptopWarning": "This keeps the CPU at full clocks and will drain a laptop battery quickly.",
    "InvokeScript": [
      "$rx = '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})'; $active = (powercfg /getactivescheme | Out-String); if ($active -match $rx) { Save-UTScriptState -Id UTUltimatePerf -Key PreviousScheme -Value $Matches[1] }; $out = (powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 | Out-String); if ($out -match $rx) { $g = $Matches[1]; Save-UTScriptState -Id UTUltimatePerf -Key CreatedScheme -Value $g; powercfg /setactive $g | Out-Null; if ($LASTEXITCODE -ne 0) { throw \"powercfg could not activate $g\" }; Write-UTLog \"Ultimate Performance plan $g is now active\" } else { throw \"powercfg could not create the Ultimate Performance plan: $out\" }"
    ],
    "UndoScript": [
      "$prev = Get-UTScriptState -Id UTUltimatePerf -Key PreviousScheme; if (-not $prev) { $prev = 'SCHEME_BALANCED' }; powercfg /setactive $prev | Out-Null; if ($LASTEXITCODE -ne 0) { throw \"powercfg could not activate the previous plan $prev\" }; $now = (powercfg /getactivescheme | Out-String); $g = Get-UTScriptState -Id UTUltimatePerf -Key CreatedScheme; if ($g -and $now -notmatch [regex]::Escape($g)) { powercfg /delete $g | Out-Null }; Write-UTLog \"Power plan restored to $prev\""
    ]
  },
  "UTHibernateOff": {
    "Content": "Hibernation off (desktop)",
    "Description": "Deletes hiberfil.sys (roughly the size of your RAM) and disables hibernate and fast startup entirely. Fine on a desktop, bad on a laptop where hibernate protects unsaved work on low battery.",
    "Evidence": "powercfg /hibernate off removes hiberfil.sys; the flag Windows reads is HibernateEnabled under HKLM\\SYSTEM\\CurrentControlSet\\Control\\Power, which powercfg writes itself (Microsoft Learn). Disk space only, no FPS effect. Confidence: high.",
    "Category": "Power",
    "Tier": "optional",
    "Recommended": false,
    "Order": 112,
    "LaptopWarning": "Laptops should keep hibernation; use the Fast startup off tweak instead.",
    "InvokeScript": [
      "powercfg.exe /hibernate off"
    ],
    "UndoScript": [
      "powercfg.exe /hibernate on"
    ]
  },
  "UTVisualEffects": {
    "Content": "Visual effects set for performance",
    "Description": "Turns off window animations, transparency, Aero Peek, list view shadows and menu fade. Makes the desktop snappier and removes a little compositor work; it does not change FPS inside a fullscreen game. Sign out to apply everything.",
    "Evidence": "The same values the Performance Options dialog writes for Adjust for best performance (VisualFXSetting, UserPreferencesMask, MinAnimate, TaskbarAnimations, transparency). Desktop responsiveness only; games are unaffected. Confidence: medium.",
    "Category": "Quality of life",
    "Tier": "optional",
    "Recommended": false,
    "Order": 120,
    "SignOut": true,
    "registry": [
      {
        "Path": "HKCU:\\Control Panel\\Desktop",
        "Name": "DragFullWindows",
        "Type": "String",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKCU:\\Control Panel\\Desktop",
        "Name": "MenuShowDelay",
        "Type": "String",
        "Value": "200",
        "OriginalValue": "400"
      },
      {
        "Path": "HKCU:\\Control Panel\\Desktop\\WindowMetrics",
        "Name": "MinAnimate",
        "Type": "String",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
        "Name": "ListviewAlphaSelect",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
        "Name": "ListviewShadow",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
        "Name": "TaskbarAnimations",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\VisualEffects",
        "Name": "VisualFXSetting",
        "Type": "DWord",
        "Value": "3",
        "OriginalValue": "1"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\DWM",
        "Name": "EnableAeroPeek",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
        "Name": "EnableTransparency",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKCU:\\Control Panel\\Desktop",
        "Name": "UserPreferencesMask",
        "Type": "Binary",
        "Value": "90,12,03,80,10,00,00,00",
        "OriginalValue": "9E,3E,07,80,12,00,00,00"
      }
    ]
  },
  "UTWUDefer": {
    "Content": "Defer feature updates for a year",
    "Description": "Keeps you on your current Windows version for up to 365 days while still receiving security updates. Avoids a new feature update landing mid-season with fresh driver and anti-cheat regressions.",
    "Evidence": "DeferFeatureUpdates, DeferFeatureUpdatesPeriodInDays and BranchReadinessLevel are the Windows Update for Business policies (Microsoft Learn). Feature updates are delayed; security updates still install. Confidence: high.",
    "Category": "Stability",
    "Tier": "optional",
    "Recommended": false,
    "Order": 130,
    "registry": [
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate",
        "Name": "DeferFeatureUpdates",
        "Type": "DWord",
        "Value": "1",
        "OriginalValue": "<RemoveEntry>"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate",
        "Name": "DeferFeatureUpdatesPeriodInDays",
        "Type": "DWord",
        "Value": "365",
        "OriginalValue": "<RemoveEntry>"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate",
        "Name": "BranchReadinessLevel",
        "Type": "DWord",
        "Value": "16",
        "OriginalValue": "<RemoveEntry>"
      }
    ]
  },
  "UTNicPowerSaving": {
    "Content": "Network adapter power saving and Energy Efficient Ethernet off",
    "Description": "Stops Windows from putting the active network adapter to sleep and disables 802.3az power saving where the driver exposes it. Fixes latency spikes and drop-outs on laptops, USB adapters and some Wi-Fi drivers. Does not change average ping. The adapter resets as this is applied, so expect the connection to drop for a second.",
    "Evidence": "Disable-NetAdapterPowerManagement is the PowerShell form of unticking Allow the computer to turn off this device on the NIC, and *EEE=0 disables Energy-Efficient Ethernet (Microsoft Learn, NetAdapter cmdlets). Matters on laptops and USB NICs where link power states add latency. Confidence: high.",
    "Category": "Network",
    "Tier": "optional",
    "Recommended": false,
    "Order": 141,
    "InvokeScript": [
      "$names = @(); Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | ForEach-Object { $n = $_.Name; $names += $n; try { Disable-NetAdapterPowerManagement -Name $n -ErrorAction Stop; Write-UTLog \"Power management disabled on $n\" } catch { Write-UTLog \"Could not change power management on $n : $($_.Exception.Message)\" -Level Warn }; try { $null = Get-NetAdapterAdvancedProperty -Name $n -RegistryKeyword '*EEE' -ErrorAction Stop; Set-NetAdapterAdvancedProperty -Name $n -RegistryKeyword '*EEE' -RegistryValue 0 -ErrorAction Stop; Write-UTLog \"Energy Efficient Ethernet disabled on $n\" } catch { } }; Save-UTScriptState -Id UTNicPowerSaving -Key Adapters -Value ($names -join '|')"
    ],
    "UndoScript": [
      "$saved = Get-UTScriptState -Id UTNicPowerSaving -Key Adapters; $names = @(); if ($saved) { $names = $saved -split '\\|' } else { $names = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) }; foreach ($n in $names) { if (-not $n) { continue }; try { Enable-NetAdapterPowerManagement -Name $n -ErrorAction Stop } catch { }; try { Reset-NetAdapterAdvancedProperty -Name $n -RegistryKeyword '*EEE' -ErrorAction Stop } catch { } }"
    ]
  },
  "UTBackgroundApps": {
    "Content": "Store apps running in the background off",
    "Description": "Sets the global switch that stops Microsoft Store apps from running in the background. Windows 11 mostly manages this per app, so the effect is small.",
    "Evidence": "GlobalUserDisabled=1 is the value behind the Windows 10 Let apps run in the background master switch. Windows 11 manages this per app, so the effect there is smaller. Confidence: medium.",
    "Category": "Background load",
    "Tier": "optional",
    "Recommended": false,
    "Order": 150,
    "registry": [
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\BackgroundAccessApplications",
        "Name": "GlobalUserDisabled",
        "Type": "DWord",
        "Value": "1",
        "OriginalValue": "0"
      }
    ],
    "SignOut": true
  },
  "UTLocationOff": {
    "Content": "Location service off",
    "Description": "Denies location access for the device and your account and disables the Geolocation service. Find My Device and map apps stop working.",
    "Evidence": "The ConsentStore location Value=Deny is what the Settings > Privacy Location switch writes, and lfsvc is the Geolocation Service. Breaks Find My Device and Maps location. Confidence: medium.",
    "Category": "Privacy",
    "Tier": "optional",
    "Recommended": false,
    "Order": 151,
    "registry": [
      {
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\ConsentStore\\location",
        "Name": "Value",
        "Type": "String",
        "Value": "Deny",
        "OriginalValue": "Allow"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\ConsentStore\\location",
        "Name": "Value",
        "Type": "String",
        "Value": "Deny",
        "OriginalValue": "Allow"
      }
    ],
    "service": [
      {
        "Name": "lfsvc",
        "StartupType": "Disabled",
        "OriginalType": "Manual"
      }
    ],
    "Reboot": true
  },
  "UTTeredoOff": {
    "Content": "Teredo tunnelling off",
    "Description": "Disables the IPv6-over-UDP transition adapter. Irrelevant to Fortnite or Valorant ping, but the Xbox app and Game Pass party chat need Teredo, so skip this if you use them.",
    "Evidence": "netsh interface teredo set state disabled turns off the IPv6-over-UDP tunnel (Microsoft Learn). Xbox app party chat and some Xbox networking rely on Teredo, which is why this is opt-in. Confidence: medium.",
    "Category": "Network",
    "Tier": "optional",
    "Recommended": false,
    "Order": 142,
    "InvokeScript": [
      "netsh interface teredo set state disabled | Out-Null"
    ],
    "UndoScript": [
      "netsh interface teredo set state type=default | Out-Null"
    ]
  },
  "UTSearchIndexOff": {
    "Content": "Windows Search indexing off (hard drives)",
    "Description": "Disables the Windows Search service. Only worth it on a mechanical hard drive where the indexer causes stutter; on an SSD it gains nothing and Start menu file search and Outlook search stop working.",
    "Evidence": "WSearch is the Windows Search indexer. On a hard drive its indexing causes I/O stutter; on an SSD it does not, and disabling it breaks Start menu file search and Outlook search. Confidence: medium.",
    "Category": "Background load",
    "Tier": "optional",
    "Recommended": false,
    "Order": 152,
    "service": [
      {
        "Name": "WSearch",
        "StartupType": "Disabled",
        "OriginalType": "AutomaticDelayedStart"
      }
    ],
    "Reboot": true
  },
  "UTVendorGpuTasks": {
    "Content": "GPU vendor telemetry and updater tasks off",
    "Description": "Disables the NVIDIA and AMD scheduled tasks that report telemetry and check for driver updates in the background (NVIDIA Telemetry Monitor and Reporter, the daily driver update check, GeForce Experience self-update, the AMD user experience and updater tasks). The driver, the control panel and the overlay are untouched, and nothing is deleted: the tasks are disabled the same way Task Scheduler disables them, and undo puts back exactly what was enabled before. Installing a new GPU driver re-creates and re-enables them, so expect to run this again after a driver update.",
    "Evidence": "NvTmMon is the NVIDIA Telemetry Monitor and NvTmRep the crash and telemetry reporter (gHacks, PC Perspective); the SelfUpdate and DriverUpdateCheck tasks poll for updates. Disabling them has no effect on the driver or the control panel. Task names were checked against a live machine on the current driver, which is why they are matched by pattern. Confidence: medium.",
    "Category": "Background load",
    "Tier": "optional",
    "Recommended": false,
    "Order": 153,
    "InvokeScript": [
      "$patterns = @('NvTmRep*', 'NvTmMon*', 'NvProfileUpdater*', 'NvNodeLauncher*', 'NvDriverUpdateCheckDaily*', 'NVIDIA GeForce Experience SelfUpdate*', 'NVIDIA App SelfUpdate*', 'AMD User Experience Program*', 'AMDRyzenMasterSDKTask*', 'AMDInstallLauncher*', 'AMDLinkUpdate*', 'AMDRadeonSoftware*'); $found = 0; foreach ($task in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -eq '\\' })) { $match = $false; foreach ($p in $patterns) { if ($task.TaskName -like $p) { $match = $true; break } }; if (-not $match) { continue }; $found++; Save-UTScriptState -Id UTVendorGpuTasks -Key $task.TaskName -Value ([string]$task.State); if ([string]$task.State -eq 'Disabled') { Write-UTLog \"$($task.TaskName): already disabled\"; continue }; try { $task | Disable-ScheduledTask -ErrorAction Stop | Out-Null; Write-UTLog \"$($task.TaskName) -> Disabled\" } catch { throw \"could not disable $($task.TaskName): $($_.Exception.Message)\" } }; if ($found -eq 0) { Write-UTLog 'No NVIDIA or AMD telemetry or updater tasks are present on this PC, nothing to change' }"
    ],
    "UndoScript": [
      "$state = Get-UTScriptState -Id UTVendorGpuTasks; if (-not $state) { Write-UTLog 'No recorded vendor task states, so nothing was re-enabled' -Level Warn } else { $failed = @(); foreach ($name in @($state.Keys)) { if ($state[$name] -eq 'Disabled') { Write-UTLog \"$name was already disabled before, left alone\"; continue }; $task = Get-ScheduledTask -TaskPath '\\' -TaskName $name -ErrorAction SilentlyContinue; if (-not $task) { Write-UTLog \"$name is no longer present, skipped\"; continue }; try { $task | Enable-ScheduledTask -ErrorAction Stop | Out-Null; Write-UTLog \"$name -> Enabled\" } catch { $failed += $name; Write-UTLog \"$name could not be re-enabled: $($_.Exception.Message)\" -Level Error } }; if ($failed.Count -gt 0) { throw (\"could not re-enable {0}; the snapshot is kept so undo can be retried\" -f ($failed -join ', ')) } }"
    ]
  },
  "UTHVCIOff": {
    "Content": "Memory integrity (core isolation) off",
    "Description": "RISKY. Memory integrity (HVCI) costs roughly 4 to 8 percent FPS on many systems (Tom's Hardware measured 4 to 6 percent average). Turning it off lowers Windows kernel protection against malicious drivers. As of the last check Riot Vanguard did not require it on Windows 10/11 x64 and Easy Anti-Cheat required it only on Arm and Insider builds, but anti-cheat requirements change without notice: if Valorant or another protected game stops launching, turn this back on first. Windows may prompt to re-enable it after feature updates. Reboot required.",
    "Evidence": "The Enabled value under DeviceGuard\\Scenarios\\HypervisorEnforcedCodeIntegrity is what the Windows Security Memory integrity switch writes (Microsoft Learn). Tom's Hardware measured HVCI/VBS costing 4 to 6 percent on average and up to 10 to 15 percent in CPU-bound titles. Confidence: high.",
    "Category": "Risky",
    "Tier": "risky",
    "Recommended": false,
    "Order": 200,
    "Reboot": true,
    "registry": [
      {
        "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\DeviceGuard\\Scenarios\\HypervisorEnforcedCodeIntegrity",
        "Name": "Enabled",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      }
    ],
    "GuardScript": [
      "if (Get-Service -Name vgk, vgc -ErrorAction SilentlyContinue) { Write-UTLog 'Riot Vanguard is installed on this PC. If Valorant stops launching after this change, undo it first before anything else.' -Level Warn }"
    ],
    "InvokeScript": [
      "try { $dg = Get-CimInstance -Namespace 'root\\Microsoft\\Windows\\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop; if (@($dg.SecurityServicesRunning) -contains 1) { Write-UTLog 'Credential Guard is running on this PC: the hypervisor stays on even with memory integrity off, so the FPS gain will be smaller' -Level Warn } } catch { }"
    ]
  },
  "UTVBSOff": {
    "Content": "Virtualization-based security off (the whole hypervisor)",
    "Description": "RISKY. Memory integrity is only one thing running inside VBS; the Windows hypervisor underneath it costs frames on its own. Tom's Hardware measured VBS on by default costing up to 10 percent, and about 5 percent geomean across four platforms, worst in CPU-bound competitive titles. This sets the Group Policy value that turns VBS off and stops the hypervisor from launching at boot. It breaks Hyper-V, WSL2, Windows Sandbox, Android subsystem and Docker's WSL backend, and it turns off Credential Guard. Riot's own VAN9005 article tells Windows 10 players to disable VBS, but anti-cheat requirements change without notice: if a protected game stops launching, undo this first. Windows 11 24H2 sometimes re-enables it after an update. If BitLocker or Device Encryption is on, protection is suspended for one reboot first so you do not get a recovery-key prompt. Reboot required.",
    "Evidence": "EnableVirtualizationBasedSecurity=0 is the disabled value of the Turn On Virtualization Based Security policy, read from C:\\Windows\\PolicyDefinitions\\DeviceGuard.admx, and hypervisorlaunchtype off stops the Windows hypervisor at boot (Microsoft Learn, BCDEdit). Tom's Hardware measured VBS costing up to 10 percent on an RTX 4090 system, about 5 percent geomean across four platforms. Confidence: high.",
    "Category": "Risky",
    "Tier": "risky",
    "Recommended": false,
    "Order": 201,
    "Reboot": true,
    "GuardScript": [
      "$vm = @(); if (Get-Service -Name vmcompute, vmms -ErrorAction SilentlyContinue) { $vm += 'Hyper-V' }; if (Get-Service -Name LxssManager -ErrorAction SilentlyContinue) { $vm += 'WSL' }; if ($vm.Count -gt 0) { Write-UTLog (\"This PC has {0} installed. Turning the hypervisor off stops it working until you undo this tweak.\" -f ($vm -join ' and ')) -Level Warn }"
    ],
    "registry": [
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\DeviceGuard",
        "Name": "EnableVirtualizationBasedSecurity",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "<RemoveEntry>"
      }
    ],
    "InvokeScript": [
      "try { $dg = Get-CimInstance -Namespace 'root\\Microsoft\\Windows\\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop; if ([int]$dg.VirtualizationBasedSecurityStatus -eq 0) { Write-UTLog 'VBS was already off on this PC, so there are no frames to win back; the policy value is still written so a Windows update cannot switch it back on' } elseif (@($dg.SecurityServicesRunning) -contains 1) { Write-UTLog 'Credential Guard is running. If it was enabled with UEFI lock, Windows keeps the hypervisor on and this change will not take effect until you clear the lock.' -Level Warn } } catch { }",
      "Invoke-UTBcdEdit -Arguments '/set hypervisorlaunchtype off'"
    ],
    "UndoScript": [
      "Invoke-UTBcdEdit -Arguments '/set hypervisorlaunchtype Auto'"
    ]
  },
  "UTDynamicTickOff": {
    "Content": "Dynamic timer tick off (bcdedit)",
    "Description": "RISKY. Keeps the clock interrupt at a fixed rate instead of tickless idle. Microsoft documents this as a debugging option; there is no reproducible FPS benchmark either way and it costs idle power. If BitLocker or Device Encryption is on, protection is suspended for one reboot first so you do not get a recovery-key prompt. Reboot required.",
    "Evidence": "disabledynamictick is a documented BCDEdit option that Microsoft lists for debugging (Microsoft Learn, BCDEdit /set). No reproducible FPS benchmark exists either way, and it costs idle power. Confidence: high that it does what it says, low for any gain.",
    "Category": "Risky",
    "Tier": "risky",
    "Recommended": false,
    "Order": 202,
    "Reboot": true,
    "InvokeScript": [
      "Invoke-UTBcdEdit -Arguments '/set disabledynamictick yes'"
    ],
    "UndoScript": [
      "Invoke-UTBcdEdit -Arguments '/deletevalue disabledynamictick'"
    ]
  },
  "UTTimerResGlobal": {
    "Content": "Global timer resolution requests (Windows 11)",
    "Description": "RISKY. Windows 11 / Server 2022 only key: it makes one process's high timer-resolution request apply system-wide again, the way Windows did before 10 v2004. It does nothing on its own - something still has to request the resolution - and this project ships no timer tool. Microsoft's own guidance, and valleyofdoom/TimerResolution, say it is for debugging. Costs idle power. Reboot required.",
    "Evidence": "GlobalTimerResolutionRequests is the Windows 11 / Server 2022 key that restores the pre-2004 behaviour where one process's timer-resolution request applies system-wide (valleyofdoom/TimerResolution, which documents it as debugging-only). Inert on Windows 10. Confidence: medium.",
    "Category": "Risky",
    "Tier": "risky",
    "Recommended": false,
    "Order": 203,
    "MinBuild": 22000,
    "Reboot": true,
    "registry": [
      {
        "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\kernel",
        "Name": "GlobalTimerResolutionRequests",
        "Type": "DWord",
        "Value": "1",
        "OriginalValue": "<RemoveEntry>"
      }
    ]
  },
  "UTMSIModeGPU": {
    "Content": "Message Signaled Interrupts on the GPU",
    "Description": "RISKY. Enables MSI mode on every display adapter that is still using line-based interrupts. Modern NVIDIA, AMD and Intel drivers already enable MSI, in which case nothing changes. On a device that does not support MSI the PC can hang at boot; recovery is Safe Mode. Per-device previous values are recorded for undo. Reboot required.",
    "Evidence": "MSISupported=1 under Interrupt Management\\MessageSignaledInterruptProperties switches the device to message-signaled interrupts (Microsoft Learn, Enabling MSI). Modern GPU drivers already enable it; a device that cannot support it can hang at boot. Confidence: high.",
    "Category": "Risky",
    "Tier": "risky",
    "Recommended": false,
    "Order": 204,
    "Reboot": true,
    "InvokeScript": [
      "Get-PnpDevice -Class Display -PresentOnly -ErrorAction SilentlyContinue | ForEach-Object { $inst = $_.InstanceId; if ($inst -notlike 'PCI\\*') { return }; $key = \"HKLM:\\SYSTEM\\CurrentControlSet\\Enum\\$inst\\Device Parameters\\Interrupt Management\\MessageSignaledInterruptProperties\"; $cur = $null; if (Test-Path $key) { $cur = (Get-ItemProperty $key -Name MSISupported -ErrorAction SilentlyContinue).MSISupported }; if ($null -eq $cur) { Save-UTScriptState -Id UTMSIModeGPU -Key $inst -Value 'missing' } else { Save-UTScriptState -Id UTMSIModeGPU -Key $inst -Value ([string]$cur) }; if ($cur -eq 1) { Write-UTLog \"$($_.FriendlyName): MSI already enabled, nothing to do\"; return }; if (-not (Test-Path $key)) { New-Item $key -Force | Out-Null }; Set-ItemProperty $key -Name MSISupported -Type DWord -Value 1 -Force; Write-UTLog \"$($_.FriendlyName): MSI enabled (previous value: $cur)\" }"
    ],
    "UndoScript": [
      "$state = Get-UTScriptState -Id UTMSIModeGPU; if ($state) { foreach ($k in @($state.Keys)) { $key = \"HKLM:\\SYSTEM\\CurrentControlSet\\Enum\\$k\\Device Parameters\\Interrupt Management\\MessageSignaledInterruptProperties\"; if (-not (Test-Path $key)) { continue }; if ($state[$k] -eq 'missing') { Remove-ItemProperty $key -Name MSISupported -ErrorAction SilentlyContinue } else { Set-ItemProperty $key -Name MSISupported -Type DWord -Value ([int]$state[$k]) -Force }; Write-UTLog \"MSI setting restored for $k\" } }"
    ]
  },
  "UTGamePriorityIFEO": {
    "Content": "Fortnite process priority Above Normal (registry, survives EAC)",
    "Description": "RISKY. Sets the Image File Execution Options PerfOptions CpuPriorityClass to Above Normal for FortniteClient-Win64-Shipping.exe. The kernel applies it at process start, so it works even though Easy Anti-Cheat blocks external priority changes. High and Realtime are deliberately not offered: they starve input and audio threads. No ban reports exist for priority changes; code injection is what gets people banned, and this injects nothing.",
    "Evidence": "PerfOptions\\CpuPriorityClass under Image File Execution Options is applied by the loader when the process starts (IFEO PerfOptions reference); 6 is Above Normal. Because the kernel sets it rather than an external tool, Easy Anti-Cheat cannot block it. No ban reports exist for priority changes. Confidence: medium.",
    "Category": "Risky",
    "Tier": "risky",
    "Recommended": false,
    "Order": 205,
    "registry": [
      {
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Image File Execution Options\\FortniteClient-Win64-Shipping.exe\\PerfOptions",
        "Name": "CpuPriorityClass",
        "Type": "DWord",
        "Value": "6",
        "OriginalValue": "<RemoveEntry>"
      }
    ]
  },
  "UTCoreParkingOff": {
    "Content": "Core parking off (plugged in)",
    "Description": "RISKY. Forces all cores to stay unparked. Gives little or nothing on desktop CPUs that do not park, and actively hurts AMD X3D dual-CCD and Intel hybrid CPUs where Windows parks cores on purpose. X3D CPUs are skipped automatically. The previous value is recorded for undo.",
    "Evidence": "CPMINCORES is the documented Processor performance core parking min cores power setting (Microsoft Learn); 100 keeps every core unparked. Since Skylake and Zen, parking control moved on-die, so the classic gain is mostly gone, and AMD X3D dual-CCD and Intel hybrid CPUs rely on parking to keep games on the right cores. Confidence: high.",
    "Category": "Risky",
    "Tier": "risky",
    "Recommended": false,
    "Order": 206,
    "GuardScript": [
      "$cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name; if ($cpu -match 'X3D') { throw \"refused on $cpu : this CPU relies on core parking to keep games on the V-Cache die\" }"
    ],
    "InvokeScript": [
      "$cur = Get-UTPowerCfgIndex -SubGroup 'SUB_PROCESSOR' -Setting 'CPMINCORES'; if ($null -eq $cur) { throw 'could not read the current core parking minimum, so it was not changed' }; Save-UTScriptState -Id UTCoreParkingOff -Key CPMINCORES -Value $cur; powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100 | Out-Null; powercfg /setactive SCHEME_CURRENT | Out-Null"
    ],
    "UndoScript": [
      "$cur = Get-UTScriptState -Id UTCoreParkingOff -Key CPMINCORES; if ($null -eq $cur -or $cur -eq '') { powercfg -restoredefaultschemes | Out-Null; Write-UTLog 'No recorded core parking value, so the power schemes were restored to Windows defaults' -Level Warn } else { powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES $cur | Out-Null; powercfg /setactive SCHEME_CURRENT | Out-Null }"
    ]
  },
  "UTSysMainOff": {
    "Content": "SysMain (Superfetch) off",
    "Description": "RISKY (low value). Disables the memory prefetching service. On an SSD there is no measurable FPS gain and app launches get slower; some people report fewer HDD stutters. Included only because it is requested so often.",
    "Evidence": "SysMain is the Superfetch/prefetch service. Windows already disables prefetch behaviour on SSDs, so there is no measurable FPS gain and app launches get slower. Kept only because it is requested so often. Confidence: medium.",
    "Category": "Risky",
    "Tier": "risky",
    "Recommended": false,
    "Order": 207,
    "service": [
      {
        "Name": "SysMain",
        "StartupType": "Disabled",
        "OriginalType": "Automatic"
      }
    ],
    "Reboot": true
  }
}
'@ | ConvertFrom-Json

$sync.configs.valorant = @'
{
  "GameProcess": "VALORANT-Win64-Shipping",
  "BlockingProcesses": ["VALORANT-Win64-Shipping", "VALORANT"],
  "ClientProcesses": ["RiotClientServices", "RiotClientUx", "RiotClientUxRender", "RiotClientCrashHandler", "Riot Client"],
  "LaunchArguments": "--launch-product=valorant --launch-patchline=live",
  "GameSection": "/Script/ShooterGame.ShooterGameUserSettings",
  "RiotSection": "Settings",
  "Profiles": {
    "MaxFPS": {
      "Content": "Max FPS (everything low, Reflex On+Boost, uncapped)",
      "Description": "Every graphics quality at its lowest, bloom, distortion and vignette off, anti-aliasing off, 1x anisotropic, VSync off, no frame cap, NVIDIA Reflex On+Boost. Fill aspect ratio so a stretched resolution is not letterboxed. Every key is one the in-game Video menu writes.",
      "Game": {
        "bUseVSync": "False",
        "bUseDynamicResolution": "False",
        "FrameRateLimit": "0.000000",
        "bShouldLetterbox": "False",
        "bLastConfirmedShouldLetterbox": "False",
        "LastConfirmedFullscreenMode": "0",
        "PreferredFullscreenMode": "0"
      },
      "Riot": {
        "EAresIntSettingName::TextureQuality": "0",
        "EAresIntSettingName::MaterialQuality": "0",
        "EAresIntSettingName::DetailQuality": "0",
        "EAresIntSettingName::UIQuality": "0",
        "EAresIntSettingName::BloomQuality": "0",
        "EAresIntSettingName::AnisotropicFiltering": "1",
        "EAresBoolSettingName::DisableDistortion": "True",
        "EAresIntSettingName::NvidiaReflexLowLatencySetting": "2",
        "EAresBoolSettingName::LimitFramerateAlways": "False"
      }
    },
    "Balanced": {
      "Content": "Balanced (low quality, capped at 240, Reflex On)",
      "Description": "Low quality groups with a 240 FPS cap so the GPU and CPU are not pinned in the menus, Reflex On without Boost. VSync off. Fill aspect ratio.",
      "Game": {
        "bUseVSync": "False",
        "bUseDynamicResolution": "False",
        "FrameRateLimit": "240.000000",
        "bShouldLetterbox": "False",
        "bLastConfirmedShouldLetterbox": "False"
      },
      "Riot": {
        "EAresIntSettingName::TextureQuality": "0",
        "EAresIntSettingName::MaterialQuality": "0",
        "EAresIntSettingName::DetailQuality": "0",
        "EAresIntSettingName::UIQuality": "0",
        "EAresIntSettingName::BloomQuality": "0",
        "EAresIntSettingName::AnisotropicFiltering": "1",
        "EAresBoolSettingName::DisableDistortion": "True",
        "EAresIntSettingName::NvidiaReflexLowLatencySetting": "1",
        "EAresBoolSettingName::LimitFramerateAlways": "True",
        "EAresFloatSettingName::MaxFramerateAlways": "240"
      }
    },
    "LatencyOnly": {
      "Content": "Keep my visuals (only Reflex, VSync and cap)",
      "Description": "Touches nothing about quality. Reflex On+Boost, VSync off, no frame cap, Fill aspect ratio.",
      "Game": {
        "bUseVSync": "False",
        "FrameRateLimit": "0.000000",
        "bShouldLetterbox": "False",
        "bLastConfirmedShouldLetterbox": "False"
      },
      "Riot": {
        "EAresIntSettingName::NvidiaReflexLowLatencySetting": "2",
        "EAresBoolSettingName::LimitFramerateAlways": "False"
      }
    }
  }
}
'@ | ConvertFrom-Json



# ==============================================================================================
# embofn7tweaks UI - WinForms shell
# The backend above is intentionally kept independent of the UI.  The four tabs below expose
# the same functional areas while using the embofn7 look and the embofn7 access gate.
# ==============================================================================================

$AppName = 'embofn7tweaks'
$sync.version = 'embofn7.1'
$sync.dir = Join-Path $env:ProgramData 'embofn7tweaks'
$sync.backupDir = Join-Path $sync.dir 'backup'
$sync.logDir = Join-Path $env:LOCALAPPDATA 'embofn7tweaks\logs'
foreach ($d in @($sync.dir, $sync.backupDir, $sync.logDir)) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
$sync.logPath = Join-Path $sync.logDir ('embofn7tweaks_{0:yyyy-MM-dd_HH-mm-ss}.log' -f (Get-Date))
$sync.log = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
$sync.jobDone = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
$sync.jobs = New-Object System.Collections.ArrayList
$sync.metrics = [hashtable]::Synchronized(@{ Snapshot = $null })
$sync.busy = $false
$sync.closing = $false
$sync.needReboot = $false
$sync.status = 'ready'
$sync.graphs = @{}
$sync.tweakBoxes = @{}
$sync.tweakStates = @{}
$sync.regions = $null
$sync.bestRegion = 'not measured yet'
$sync.dnsResults = $null
$sync.form = $null
$sync.fnProfile = 'MaxFPS'
$sync.fnHidden = @()
$sync.fnArgs = ''
$sync.selectedDns = ''
$sync.gameReadyRows = @()
$sync.startupRows = @()
$sync.debloatRows = @()

Write-UTLog ('{0} starting (PowerShell {1})' -f $AppName, $PSVersionTable.PSVersion)
Write-UTLog ('log file: ' + $sync.logPath)

# Native helpers from the friend's backend are used for accurate monitoring/low-level functions.
$UTNative = Initialize-UTNative
Write-UTLog 'native helpers initialized' -Level Ok

# ----------------------------------------------------------------------------------------------
# Small UI helpers
# ----------------------------------------------------------------------------------------------
function New-UiLabel {
    param([string]$Text, [int]$FontSize=9, [bool]$Bold=$false, [System.Drawing.Color]$Color=$ColorText)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.ForeColor = $Color
    $l.BackColor = [System.Drawing.Color]::Transparent
    $style = if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $l.Font = New-Object System.Drawing.Font('Segoe UI', $FontSize, $style)
    $l.AutoSize = $true
    return $l
}

function Style-Button {
    param([System.Windows.Forms.Button]$Button, [bool]$Danger=$false)
    $Button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $Button.FlatAppearance.BorderSize = 1
    $Button.FlatAppearance.BorderColor = $ColorRed
    $Button.BackColor = if ($Danger) { $ColorRedDark } else { $ColorRed }
    $Button.ForeColor = [System.Drawing.Color]::White
    $Button.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $Button.Height = 32
}

function New-UiButton {
    param([string]$Text, [bool]$Danger=$false)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Width = 125
    Style-Button -Button $b -Danger:$Danger
    return $b
}

function New-UiGroup {
    param([string]$Text)
    $g = New-Object System.Windows.Forms.GroupBox
    $g.Text = $Text
    $g.ForeColor = $ColorRed
    $g.BackColor = $ColorPanelBg
    $g.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    return $g
}

function Append-Console {
    param([string]$Line)
    if (-not $script:ConsoleBox -or $script:ConsoleBox.IsDisposed) { return }
    $script:ConsoleBox.AppendText($Line + [Environment]::NewLine)
    $script:ConsoleBox.SelectionStart = $script:ConsoleBox.TextLength
    $script:ConsoleBox.ScrollToCaret()
}

function Drain-UTLog {
    $line = $null
    while ($sync.log.TryDequeue([ref]$line)) { Append-Console $line }
}

function Confirm-Ui {
    param([string]$Title, [string]$Message, [bool]$Danger=$false)
    $icon = if ($Danger) { [System.Windows.Forms.MessageBoxIcon]::Warning } else { [System.Windows.Forms.MessageBoxIcon]::Question }
    return ([System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::YesNo, $icon) -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Refresh-TweakLabels {
    foreach ($id in $sync.tweakBoxes.Keys) {
        $item = $sync.tweakBoxes[$id]
        $t = $sync.configs.tweaks.$id
        if (-not $t) { continue }
        $state = ''
        if ($sync.tweakStates.ContainsKey($id)) { $state = [string]$sync.tweakStates[$id] }
        $suffix = switch ($state) {
            'applied' { '   [APPLIED]' }
            'set'     { '   [ALREADY SET]' }
            default   { '' }
        }
        $item.Control.Text = ([string]$t.Content + $suffix)
        if ($state -eq 'applied') { $item.Control.ForeColor = [System.Drawing.Color]::LightGreen }
        elseif ($state -eq 'set') { $item.Control.ForeColor = [System.Drawing.Color]::Khaki }
        elseif ($t.Tier -eq 'risky') { $item.Control.ForeColor = [System.Drawing.Color]::Orange }
        else { $item.Control.ForeColor = $ColorText }
    }
}

function New-TweakCheckBox {
    param([string]$Id, $Tweak, [System.Windows.Forms.Control]$Parent)
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.AutoSize = $false
    $cb.Width = 760
    $cb.Height = 28
    $cb.Text = [string]$Tweak.Content
    $cb.ForeColor = if ($Tweak.Tier -eq 'risky') { [System.Drawing.Color]::Orange } else { $ColorText }
    $cb.BackColor = [System.Drawing.Color]::Transparent
    $cb.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $cb.Tag = $Id
    $cb.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard
    $tip = New-Object System.Windows.Forms.ToolTip
    $tip.AutoPopDelay = 12000
    $tip.InitialDelay = 400
    $tip.ReshowDelay = 100
    $tip.SetToolTip($cb, (([string]$Tweak.Description) + "`r`n`r`nEvidence: " + [string]$Tweak.Evidence))
    $Parent.Controls.Add($cb)
    $sync.tweakBoxes[$Id] = [pscustomobject]@{ IsChecked = $false; Control = $cb; Content = [string]$Tweak.Content }
    $cb.Add_CheckedChanged({
        $id = [string]$this.Tag
        if ($sync.tweakBoxes.ContainsKey($id)) { $sync.tweakBoxes[$id].IsChecked = $this.Checked }
    })
    return $cb
}

function Get-CheckedTweakIds {
    return @($sync.tweakBoxes.Keys | Where-Object { $sync.tweakBoxes[$_].Control.Checked })
}

function Set-CheckedTweaks {
    param([string[]]$Ids)
    foreach ($id in $sync.tweakBoxes.Keys) { $sync.tweakBoxes[$id].Control.Checked = $false }
    foreach ($id in $Ids) { if ($sync.tweakBoxes.ContainsKey($id)) { $sync.tweakBoxes[$id].Control.Checked = $true } }
}

function Refresh-SystemInfoText {
    $s = $sync.sysinfo
    if (-not $s) { return }
    $script:SystemInfoBox.Text = @(
        ('CPU        : ' + $s.CPU),
        ('GPU        : ' + $s.GPU),
        ('RAM        : ' + $s.RamGB + ' GB'),
        ('System disk: ' + $s.DiskType),
        ('Windows    : ' + $s.OSName),
        ('Build      : ' + $s.Build),
        ('Laptop     : ' + $s.IsLaptop),
        ('VBS        : ' + $s.VBSStatus),
        ('HVCI       : ' + $s.HVCIRunning),
        '',
        ('Backups    : ' + $sync.backupDir),
        ('Log        : ' + $sync.logPath)
    ) -join "`r`n"
}

function Set-StatusText {
    if ($sync.needReboot) { $script:StatusLabel.Text = 'Status: reboot recommended' }
    elseif ($sync.busy) { $script:StatusLabel.Text = 'Status: ' + $sync.status }
    else { $script:StatusLabel.Text = 'Status: ready' }
}

# ----------------------------------------------------------------------------------------------
# Four-tab application
# ----------------------------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$sync.form = $form
$form.Text = $AppName
$form.Size = New-Object System.Drawing.Size(1220, 800)
$form.MinimumSize = New-Object System.Drawing.Size(1050, 700)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $ColorBg
$form.ForeColor = $ColorText
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false
$form.KeyPreview = $true

# Header
$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'; $header.Height = 62; $header.BackColor = $ColorBg
$form.Controls.Add($header)
$title = New-UiLabel 'embofn7tweaks - SAFE / OPTIONAL / RISKY' 16 $true $ColorRed
$title.Location = New-Object System.Drawing.Point(18, 12)
$header.Controls.Add($title)
$userLabel = New-UiLabel ('eingeloggt als: ' + $script:AuthorizedUser) 9 $false $ColorTextDim
$userLabel.Anchor = 'Top,Right'; $userLabel.Location = New-Object System.Drawing.Point(1010, 18)
$header.Controls.Add($userLabel)
$script:StatusLabel = New-UiLabel 'Status: ready' 8 $false $ColorTextDim
$script:StatusLabel.Location = New-Object System.Drawing.Point(20, 40)
$header.Controls.Add($script:StatusLabel)

# Main split
$main = New-Object System.Windows.Forms.SplitContainer
$main.Dock = 'Fill'; $main.SplitterDistance = 300; $main.IsSplitterFixed = $true
$main.BackColor = $ColorBg
$form.Controls.Add($main)
$form.Controls.SetChildIndex($main, 0)

# Left monitoring
$left = New-Object System.Windows.Forms.Panel
$left.Dock = 'Fill'; $left.AutoScroll = $true; $left.BackColor = $ColorBg
$main.Panel1.Controls.Add($left)

function New-MetricCard {
    param([string]$Name, [int]$Y)
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point(12,$Y); $p.Size = New-Object System.Drawing.Size(270, 105)
    $p.BackColor = $ColorPanelBg
    $p.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $name = New-UiLabel $Name 8 $true $ColorTextDim; $name.Location = New-Object System.Drawing.Point(10,8); $p.Controls.Add($name)
    $value = New-UiLabel '--' 12 $true $ColorRed; $value.Location = New-Object System.Drawing.Point(10,30); $p.Controls.Add($value)
    $graph = New-Object System.Windows.Forms.Panel
    $graph.Location = New-Object System.Drawing.Point(10,55); $graph.Size = New-Object System.Drawing.Size(250,38); $graph.BackColor = [System.Drawing.Color]::Black
    $graph.Tag = New-Object System.Collections.Queue
    $p.Controls.Add($graph)
    $graph.Add_Paint({
        $g = $_.Graphics; $q = $this.Tag; if (-not $q -or $q.Count -lt 2) { return }
        $vals = @($q); $max = [double](($vals | Measure-Object -Maximum).Maximum); if ($max -le 0) { $max = 1 }
        $pts = New-Object System.Drawing.Point[] $vals.Count
        for ($i=0; $i -lt $vals.Count; $i++) {
            $x = [int](($i / [math]::Max(1,$vals.Count-1)) * ($this.Width-2))
            $y = $this.Height - 2 - [int](($vals[$i] / $max) * ($this.Height-4))
            $pts[$i] = New-Object System.Drawing.Point($x,$y)
        }
        if ($pts.Count -gt 1) { $g.DrawLines((New-Object System.Drawing.Pen($ColorRed,1.5)), $pts) }
    })
    $left.Controls.Add($p)
    return [pscustomobject]@{ Panel=$p; Value=$value; Graph=$graph }
}

$sync.uiMetrics = @{}
$sync.uiMetrics.CPU = New-MetricCard 'CPU' 8
$sync.uiMetrics.RAM = New-MetricCard 'MEMORY' 120
$sync.uiMetrics.GPU = New-MetricCard 'GPU' 232
$sync.uiMetrics.DISK = New-MetricCard 'DISK ACTIVE' 344
$sync.uiMetrics.NET = New-MetricCard 'NETWORK' 456

# Right tabs
$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'; $tabs.BackColor = $ColorPanelBg; $tabs.ForeColor = $ColorText
$main.Panel2.Controls.Add($tabs)

function New-Tab {
    param([string]$Name)
    $page = New-Object System.Windows.Forms.TabPage
    $page.Text = $Name
    $page.BackColor = $ColorPanelBg
    $page.ForeColor = $ColorText
    $page.Padding = New-Object System.Windows.Forms.Padding(8)
    $tabs.TabPages.Add($page) | Out-Null
    return $page
}

# ==============================================================================================
# TAB 1 - TWEAKS
# ==============================================================================================
$tweaksTab = New-Tab 'TWEAKS'
$topT = New-Object System.Windows.Forms.Panel; $topT.Dock='Top'; $topT.Height=88; $tweaksTab.Controls.Add($topT)
$safePreset = New-Object System.Windows.Forms.CheckBox; $safePreset.Text='SAFE-Preset auswählen (empfohlen)'; $safePreset.ForeColor=$ColorText; $safePreset.Location=New-Object System.Drawing.Point(5,5); $safePreset.AutoSize=$true; $topT.Controls.Add($safePreset)
$restoreCb = New-Object System.Windows.Forms.CheckBox; $restoreCb.Text='Restore Point vor dem Anwenden'; $restoreCb.Checked=$true; $restoreCb.ForeColor=$ColorText; $restoreCb.Location=New-Object System.Drawing.Point(5,27); $restoreCb.AutoSize=$true; $topT.Controls.Add($restoreCb)
$recommended = New-UiButton 'Empfohlen'; $recommended.Location=New-Object System.Drawing.Point(5,48); $recommended.Width=105; $topT.Controls.Add($recommended)
$clearTweaks = New-UiButton 'Clear'; $clearTweaks.Location=New-Object System.Drawing.Point(115,48); $clearTweaks.Width=90; $topT.Controls.Add($clearTweaks)
$applyTweaks = New-UiButton 'Apply selected'; $applyTweaks.Location=New-Object System.Drawing.Point(210,48); $applyTweaks.Width=125; $topT.Controls.Add($applyTweaks)
$undoSelected = New-UiButton 'Undo selected' $true; $undoSelected.Location=New-Object System.Drawing.Point(340,48); $undoSelected.Width=115; $topT.Controls.Add($undoSelected)
$undoAll = New-UiButton 'Undo everything' $true; $undoAll.Location=New-Object System.Drawing.Point(460,48); $undoAll.Width=125; $topT.Controls.Add($undoAll)
$exportBtn = New-UiButton 'Export'; $exportBtn.Location=New-Object System.Drawing.Point(590,48); $exportBtn.Width=85; $topT.Controls.Add($exportBtn)
$importBtn = New-UiButton 'Import'; $importBtn.Location=New-Object System.Drawing.Point(680,48); $importBtn.Width=85; $topT.Controls.Add($importBtn)

$tweakScroll = New-Object System.Windows.Forms.Panel
$tweakScroll.Dock='Fill'; $tweakScroll.AutoScroll=$true; $tweakScroll.BackColor=$ColorBg
$tweaksTab.Controls.Add($tweakScroll); $tweaksTab.Controls.SetChildIndex($tweakScroll,0)
$y=8
foreach ($tier in @('safe','optional','risky')) {
    $tierName = switch($tier) { 'safe' {'SAFE (empfohlen)'} 'optional' {'OPTIONAL'} 'risky' {'RISKY'} }
    $tierColor = if ($tier -eq 'risky') { [System.Drawing.Color]::Orange } else { $ColorRed }
    $head = New-UiLabel $tierName 11 $true $tierColor; $head.Location=New-Object System.Drawing.Point(8,$y); $head.AutoSize=$true; $tweakScroll.Controls.Add($head); $y += 27
    $desc = switch($tier) {
        'safe' {'Dokumentierte Änderungen mit Snapshot vor dem ersten Apply.'}
        'optional' {'Für bestimmte PCs sinnvoll; Hinweise vor dem Anwenden lesen.'}
        'risky' {'Kann Sicherheit/Stabilität beeinflussen. Nie automatisch ausgewählt.'}
    }
    $dl=New-UiLabel $desc 8 $false $ColorTextDim; $dl.Location=New-Object System.Drawing.Point(8,$y); $tweakScroll.Controls.Add($dl); $y+=24
    $items = @($sync.configs.tweaks.PSObject.Properties | Where-Object { $_.Value.Tier -eq $tier } | Sort-Object { [int]$_.Value.Order })
    foreach($p in $items) { [void](New-TweakCheckBox -Id $p.Name -Tweak $p.Value -Parent $tweakScroll); $sync.tweakBoxes[$p.Name].Control.Location=New-Object System.Drawing.Point(12,$y); $y+=29 }
    $y+=12
}

$safePreset.Add_CheckedChanged({
    if ($this.Checked) { foreach($id in $sync.tweakBoxes.Keys){$t=$sync.configs.tweaks.$id;$sync.tweakBoxes[$id].Control.Checked=([bool]$t.Recommended -and $t.Tier -eq 'safe' -and (Test-UTTweakEligible -Tweak $t))}; Write-UTLog 'SAFE preset selected' -Level Ok }
})
$recommended.Add_Click({
    foreach($id in $sync.tweakBoxes.Keys) { $t=$sync.configs.tweaks.$id; $sync.tweakBoxes[$id].Control.Checked=([bool]$t.Recommended -and $t.Tier -eq 'safe' -and (Test-UTTweakEligible -Tweak $t)) }
    Write-UTLog 'recommended safe tweaks selected' -Level Ok
})
$clearTweaks.Add_Click({ Set-CheckedTweaks @(); Write-UTLog 'tweak selection cleared' })
$applyTweaks.Add_Click({
    if($sync.busy){ return }
    $ids=Get-CheckedTweakIds
    if($ids.Count -eq 0){ [System.Windows.Forms.MessageBox]::Show('Keine Tweaks ausgewählt.','embofn7tweaks') | Out-Null; return }
    $risky=@($ids | Where-Object {$sync.configs.tweaks.$_.Tier -eq 'risky'})
    if($risky.Count -gt 0 -and -not (Confirm-Ui 'RISKY Tweaks' ('Folgende Risky Tweaks werden angewendet:`r`n`r`n' + (($risky | ForEach-Object {$sync.configs.tweaks.$_.Content}) -join "`r`n") + '`r`n`r`nFortfahren?') $true)){return}
    if($restoreCb.Checked -and -not (Confirm-Ui 'Restore Point' 'Vor dem Anwenden wird ein Windows-Systemwiederherstellungspunkt erstellt. Fortfahren?')){return}
    $sync.busy=$true; $sync.status='applying tweaks'
    $args=@{Ids=[string[]]$ids; Restore=[bool]$restoreCb.Checked}
    Start-UTJob -Kind 'tweaks' -Arguments $args -Script 'if ($Arguments.Restore) { [void](New-UTRestorePoint) }; Invoke-UTTweaks -Ids ([string[]]$Arguments.Ids) | Out-Null' | Out-Null
})
$undoSelected.Add_Click({
    if($sync.busy){return}; $ids=Get-CheckedTweakIds; if($ids.Count -eq 0){return}
    if(-not (Confirm-Ui 'Undo selected' 'Die ausgewählten Tweaks werden anhand ihrer gespeicherten Snapshots zurückgesetzt. Fortfahren?' $true)){return}
    $sync.busy=$true; $sync.status='undoing tweaks'; Start-UTJob -Kind 'undo' -Arguments @{Ids=[string[]]$ids} -Script 'Invoke-UTTweaks -Ids ([string[]]$Arguments.Ids) -Undo | Out-Null' | Out-Null
})
$undoAll.Add_Click({
    if($sync.busy){return}; $ids=@(Get-UTAppliedTweaks); if($ids.Count -eq 0){[System.Windows.Forms.MessageBox]::Show('Keine angewendeten Snapshots gefunden.','embofn7tweaks')|Out-Null;return}
    if(-not (Confirm-Ui 'Undo everything' ('Es werden {0} gespeicherte Tweak-Snapshots zurückgesetzt.' -f $ids.Count) $true)){return}
    $sync.busy=$true; $sync.status='undoing everything'; Start-UTJob -Kind 'undoall' -Arguments @{Ids=[string[]]$ids} -Script 'Invoke-UTTweaks -Ids ([string[]]$Arguments.Ids) -Undo | Out-Null' | Out-Null
})
$exportBtn.Add_Click({
    $dlg=New-Object System.Windows.Forms.SaveFileDialog; $dlg.Filter='JSON|*.json'; $dlg.FileName='embofn7tweaks-selection.json'
    if($dlg.ShowDialog() -eq 'OK'){
        $obj=[ordered]@{Tool='embofn7tweaks';Version=$sync.version;Exported=(Get-Date).ToString('s');Tweaks=@(Get-CheckedTweakIds);FortniteProfile=$sync.fnProfile;LaunchArgs=$sync.fnArgs}
        $obj|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $dlg.FileName -Encoding UTF8; Write-UTLog ('selection exported to '+$dlg.FileName) -Level Ok
    }
})
$importBtn.Add_Click({
    $dlg=New-Object System.Windows.Forms.OpenFileDialog; $dlg.Filter='JSON|*.json'
    if($dlg.ShowDialog() -eq 'OK'){
        try{$o=Get-Content $dlg.FileName -Raw|ConvertFrom-Json; Set-CheckedTweaks ([string[]]$o.Tweaks); if($o.FortniteProfile){$sync.fnProfile=[string]$o.FortniteProfile}; if($null -ne $o.LaunchArgs){$sync.fnArgs=[string]$o.LaunchArgs}; Write-UTLog ('selection imported from '+$dlg.FileName) -Level Ok}catch{Write-UTLog ('import failed: '+$_.Exception.Message) -Level Error}
    }
})

# ==============================================================================================
# TAB 2 - NETWORK
# ==============================================================================================
$networkTab=New-Tab 'NETWORK'
$netTop=New-Object System.Windows.Forms.Panel; $netTop.Dock='Top'; $netTop.Height=75; $networkTab.Controls.Add($netTop)
$pingBtn=New-UiButton 'Ping regions'; $pingBtn.Location=New-Object System.Drawing.Point(5,5); $pingBtn.Width=120; $netTop.Controls.Add($pingBtn)
$tracertBtn=New-UiButton 'Traceroute'; $tracertBtn.Location=New-Object System.Drawing.Point(130,5); $tracertBtn.Width=105; $netTop.Controls.Add($tracertBtn)
$linkBtn=New-UiButton 'Link info'; $linkBtn.Location=New-Object System.Drawing.Point(240,5); $linkBtn.Width=100; $netTop.Controls.Add($linkBtn)
$flushBtn=New-UiButton 'Flush DNS'; $flushBtn.Location=New-Object System.Drawing.Point(345,5); $flushBtn.Width=105; $netTop.Controls.Add($flushBtn)
$resetNetBtn=New-UiButton 'Reset network' $true; $resetNetBtn.Location=New-Object System.Drawing.Point(455,5); $resetNetBtn.Width=125; $netTop.Controls.Add($resetNetBtn)
$dnsBenchBtn=New-UiButton 'DNS benchmark'; $dnsBenchBtn.Location=New-Object System.Drawing.Point(5,40); $dnsBenchBtn.Width=120; $netTop.Controls.Add($dnsBenchBtn)
$dnsUseBtn=New-UiButton 'Use DNS'; $dnsUseBtn.Location=New-Object System.Drawing.Point(130,40); $dnsUseBtn.Width=100; $netTop.Controls.Add($dnsUseBtn)
$dnsResetBtn=New-UiButton 'DNS automatic'; $dnsResetBtn.Location=New-Object System.Drawing.Point(235,40); $dnsResetBtn.Width=115; $netTop.Controls.Add($dnsResetBtn)
$regionBox=New-Object System.Windows.Forms.TextBox; $regionBox.Multiline=$true; $regionBox.ReadOnly=$true; $regionBox.BackColor=[System.Drawing.Color]::Black; $regionBox.ForeColor=$ColorText; $regionBox.Dock='Fill'; $regionBox.Font=New-Object System.Drawing.Font('Consolas',9); $regionBox.ScrollBars='Both'; $networkTab.Controls.Add($regionBox); $networkTab.Controls.SetChildIndex($regionBox,0)
$pingBtn.Add_Click({if($sync.busy){return};$sync.busy=$true;$sync.status='pinging Fortnite regions';Start-UTJob -Kind 'regions' -Script 'Measure-UTRegionPing | Out-Null'|Out-Null})
$tracertBtn.Add_Click({$r=@($sync.regions|Where-Object{$_.Host -like '*epicgames.com' -and $null -ne $_.AvgMs}|Select-Object -First 1);if(-not $r){[System.Windows.Forms.MessageBox]::Show('Erst Regionen pingen.','embofn7tweaks')|Out-Null;return};if($sync.busy){return};$sync.busy=$true;$sync.status='traceroute';Start-UTJob -Kind 'tracert' -Arguments @{Target=$r.Host} -Script 'Invoke-UTNetworkTool -Tool tracert -Target $Arguments.Target | Out-Null'|Out-Null})
$linkBtn.Add_Click({if($sync.busy){return};$sync.busy=$true;Start-UTJob -Kind 'linkinfo' -Script 'Invoke-UTNetworkTool -Tool linkinfo | Out-Null'|Out-Null})
$flushBtn.Add_Click({if($sync.busy){return};$sync.busy=$true;Start-UTJob -Kind 'flush' -Script 'Invoke-UTNetworkTool -Tool flush | Out-Null'|Out-Null})
$resetNetBtn.Add_Click({if($sync.busy){return};if(-not(Confirm-Ui 'Network reset' 'Winsock + TCP/IP werden zurückgesetzt. Statische IP/DNS-Konfigurationen können dabei verloren gehen. Neustart erforderlich. Fortfahren?' $true)){return};$sync.busy=$true;Start-UTJob -Kind 'netreset' -Script 'Invoke-UTNetworkTool -Tool reset | Out-Null'|Out-Null})
$dnsBenchBtn.Add_Click({if($sync.busy){return};$sync.busy=$true;$sync.status='DNS benchmark';Start-UTJob -Kind 'dns' -Script 'Invoke-UTDnsBenchmark | Out-Null'|Out-Null})
$dnsUseBtn.Add_Click({if(-not $sync.selectedDns){return};if($sync.busy){return};if(-not(Confirm-Ui 'DNS' ('Resolver '+$sync.selectedDns+' verwenden?'))){return};$sync.busy=$true;Start-UTJob -Kind 'dnsset' -Arguments @{Provider=$sync.selectedDns} -Script 'Set-UTDns -Provider $Arguments.Provider | Out-Null'|Out-Null})
$dnsResetBtn.Add_Click({if($sync.busy){return};$sync.busy=$true;Start-UTJob -Kind 'dnsreset' -Script 'Set-UTDns -Reset | Out-Null'|Out-Null})

# ==============================================================================================
# TAB 3 - GAME READY
# ==============================================================================================
$gameTab=New-Tab 'GAME READY'
$gameTop=New-Object System.Windows.Forms.Panel; $gameTop.Dock='Top'; $gameTop.Height=120; $gameTab.Controls.Add($gameTop)
$refreshGame=New-UiButton 'Refresh'; $refreshGame.Location=New-Object System.Drawing.Point(5,5); $refreshGame.Width=90; $gameTop.Controls.Add($refreshGame)
$closeGame=New-UiButton 'Close selected' $true; $closeGame.Location=New-Object System.Drawing.Point(100,5); $closeGame.Width=115; $gameTop.Controls.Add($closeGame)
$gameLabel=New-UiLabel 'Game:' 9 $true $ColorTextDim; $gameLabel.Location=New-Object System.Drawing.Point(225,12); $gameTop.Controls.Add($gameLabel)
$gameCombo=New-Object System.Windows.Forms.ComboBox; $gameCombo.DropDownStyle='DropDownList'; $gameCombo.Width=180; $gameCombo.Location=New-Object System.Drawing.Point(270,7); $gameCombo.BackColor=$ColorPanelBg; $gameCombo.ForeColor=$ColorText; [void]$gameCombo.Items.Add('Fortnite'); [void]$gameCombo.Items.Add('VALORANT'); [void]$gameCombo.Items.Add('other game'); $gameCombo.SelectedIndex=0; $gameTop.Controls.Add($gameCombo)
$fnProfileLabel=New-UiLabel 'Fortnite profile:' 9 $true $ColorTextDim; $fnProfileLabel.Location=New-Object System.Drawing.Point(5,48); $gameTop.Controls.Add($fnProfileLabel)
$fnProfileCombo=New-Object System.Windows.Forms.ComboBox; $fnProfileCombo.DropDownStyle='DropDownList'; $fnProfileCombo.Width=280; $fnProfileCombo.Location=New-Object System.Drawing.Point(110,43); $fnProfileCombo.BackColor=$ColorPanelBg; $fnProfileCombo.ForeColor=$ColorText; $gameTop.Controls.Add($fnProfileCombo)
foreach($p in $sync.configs.fortnite.Profiles.PSObject.Properties){[void]$fnProfileCombo.Items.Add($p.Name+' - '+$p.Value.Content)}
$fnProfileCombo.SelectedIndex=0
$fnApply=New-UiButton 'Apply Fortnite'; $fnApply.Location=New-Object System.Drawing.Point(395,43); $fnApply.Width=120; $gameTop.Controls.Add($fnApply)
$fnRestore=New-UiButton 'Restore Fortnite' $true; $fnRestore.Location=New-Object System.Drawing.Point(520,43); $fnRestore.Width=125; $gameTop.Controls.Add($fnRestore)
$shader=New-UiButton 'Clear shader cache'; $shader.Location=New-Object System.Drawing.Point(650,43); $shader.Width=135; $gameTop.Controls.Add($shader)
$launchLabel=New-UiLabel 'Launch args:' 9 $true $ColorTextDim; $launchLabel.Location=New-Object System.Drawing.Point(5,82); $gameTop.Controls.Add($launchLabel)
$launchBox=New-Object System.Windows.Forms.TextBox; $launchBox.Location=New-Object System.Drawing.Point(80,78); $launchBox.Width=430; $launchBox.BackColor=[System.Drawing.Color]::Black; $launchBox.ForeColor=$ColorText; $launchBox.Text='-NOSPLASH'; $gameTop.Controls.Add($launchBox)
$launchApply=New-UiButton 'Write args'; $launchApply.Location=New-Object System.Drawing.Point(515,77); $launchApply.Width=100; $gameTop.Controls.Add($launchApply)
$launchClear=New-UiButton 'Clear args'; $launchClear.Location=New-Object System.Drawing.Point(620,77); $launchClear.Width=100; $gameTop.Controls.Add($launchClear)
$gameList=New-Object System.Windows.Forms.CheckedListBox; $gameList.Dock='Fill'; $gameList.BackColor=[System.Drawing.Color]::Black; $gameList.ForeColor=$ColorText; $gameList.Font=New-Object System.Drawing.Font('Segoe UI',9); $gameTab.Controls.Add($gameList); $gameTab.Controls.SetChildIndex($gameList,0)

function Refresh-GameReadyUi {
    $gameList.Items.Clear(); $sync.gameReadyRows=@()
    $gp=switch($gameCombo.SelectedIndex){0{$sync.configs.fortnite.GameProcess};1{$sync.configs.valorant.GameProcess};default{''}}
    try{$rows=@(Get-UTGameReadyCandidates -GameProcess $gp);$sync.gameReadyRows=$rows;foreach($r in $rows){$idx=$gameList.Items.Add(('{0}  |  {1} MB  |  {2}' -f $r.Label,$r.MemoryMB,$r.Name));if(-not $r.Keep){$gameList.SetItemChecked($idx,$true)}};Write-UTLog ('Game Ready list refreshed: '+$rows.Count+' process groups')}catch{Write-UTLog ('Game Ready refresh failed: '+$_.Exception.Message) -Level Error}
}
$refreshGame.Add_Click({Refresh-GameReadyUi})
$gameCombo.Add_SelectedIndexChanged({Refresh-GameReadyUi})
$closeGame.Add_Click({$names=@();foreach($i in $gameList.CheckedIndices){$names+=[string]$sync.gameReadyRows[$i].Name};if($names.Count -eq 0){return};if(-not(Confirm-Ui 'Game Ready' ('Diese Prozesse werden beendet. Ungespeicherte Arbeit kann verloren gehen.`r`n`r`n'+($names -join ', ')) $true)){return};if($sync.busy){return};$sync.busy=$true;$sync.status='Game Ready';Start-UTJob -Kind 'gameready' -Arguments @{Names=[string[]]$names} -Script 'Stop-UTGameReadyProcesses -Names ([string[]]$Arguments.Names) | Out-Null'|Out-Null})
$fnApply.Add_Click({$p=[string]($fnProfileCombo.SelectedItem -split ' - ',2)[0];$sync.fnProfile=$p;if($sync.busy){return};$sync.busy=$true;Start-UTJob -Kind 'fortnite' -Arguments @{Profile=$p} -Script 'Set-UTFortniteSettings -ProfileName $Arguments.Profile | Out-Null'|Out-Null})
$fnRestore.Add_Click({if($sync.busy){return};if(-not(Confirm-Ui 'Fortnite restore' 'Die ursprüngliche GameUserSettings.ini wird aus dem Original-Backup wiederhergestellt.' $true)){return};$sync.busy=$true;Start-UTJob -Kind 'fortnite-restore' -Script 'Restore-UTFortniteSettings'|Out-Null})
$shader.Add_Click({if($sync.busy){return};if(-not(Confirm-Ui 'Shader cache' 'Shader-Caches werden gelöscht. Der nächste Start kann zunächst stottern, bis sie neu aufgebaut sind. Fortfahren?')){return};$sync.busy=$true;Start-UTJob -Kind 'shader' -Script 'Clear-UTShaderCache'|Out-Null})
$launchApply.Add_Click({if($sync.busy){return};$sync.fnArgs=$launchBox.Text.Trim();$sync.busy=$true;Start-UTJob -Kind 'launchargs' -Arguments @{Arguments=$sync.fnArgs} -Script 'Set-UTLaunchArgs -Arguments ([string]$Arguments.Arguments)'|Out-Null})
$launchClear.Add_Click({if($sync.busy){return};$sync.fnArgs='';$launchBox.Text='';$sync.busy=$true;Start-UTJob -Kind 'launchargs-clear' -Arguments @{Arguments=''} -Script 'Set-UTLaunchArgs -Arguments ([string]$Arguments.Arguments)'|Out-Null})

# ==============================================================================================
# TAB 4 - INFO
# ==============================================================================================
$infoTab=New-Tab 'INFO'
$infoTop=New-Object System.Windows.Forms.Panel; $infoTop.Dock='Top'; $infoTop.Height=70; $infoTab.Controls.Add($infoTop)
$benchBtn=New-UiButton 'Benchmark (10 s)'; $benchBtn.Location=New-Object System.Drawing.Point(5,5); $benchBtn.Width=130; $infoTop.Controls.Add($benchBtn)
$refreshInfo=New-UiButton 'Refresh info'; $refreshInfo.Location=New-Object System.Drawing.Point(140,5); $refreshInfo.Width=105; $infoTop.Controls.Add($refreshInfo)
$openLogs=New-UiButton 'Open logs'; $openLogs.Location=New-Object System.Drawing.Point(250,5); $openLogs.Width=95; $infoTop.Controls.Add($openLogs)
$openBackups=New-UiButton 'Open backups'; $openBackups.Location=New-Object System.Drawing.Point(350,5); $openBackups.Width=110; $infoTop.Controls.Add($openBackups)
$infoBox=New-Object System.Windows.Forms.TextBox; $infoBox.Dock='Fill'; $infoBox.Multiline=$true; $infoBox.ReadOnly=$true; $infoBox.BackColor=[System.Drawing.Color]::Black; $infoBox.ForeColor=$ColorText; $infoBox.Font=New-Object System.Drawing.Font('Consolas',9); $infoBox.ScrollBars='Both'; $infoTab.Controls.Add($infoBox); $infoTab.Controls.SetChildIndex($infoBox,0); $script:SystemInfoBox=$infoBox
$benchBox=New-Object System.Windows.Forms.TextBox; $benchBox.Multiline=$true; $benchBox.ReadOnly=$true; $benchBox.Height=120; $benchBox.Dock='Bottom'; $benchBox.BackColor=[System.Drawing.Color]::Black; $benchBox.ForeColor=$ColorText; $benchBox.Font=New-Object System.Drawing.Font('Consolas',9); $infoTab.Controls.Add($benchBox)
$benchBtn.Add_Click({if($sync.busy){return};$sync.busy=$true;$sync.status='benchmark';Start-UTJob -Kind 'benchmark' -Script 'Invoke-UTBenchmark | Out-Null'|Out-Null})
$refreshInfo.Add_Click({if($sync.busy){return};$sync.busy=$true;Start-UTJob -Kind 'refresh' -Script '$sync.sysinfo=Get-UTSystemInfo; Update-UTTweakStates'|Out-Null})
$openLogs.Add_Click({Start-Process explorer.exe -ArgumentList ('"'+$sync.logDir+'"')})
$openBackups.Add_Click({Start-Process explorer.exe -ArgumentList ('"'+$sync.backupDir+'"')})

# Footer / console
$footer=New-Object System.Windows.Forms.Panel; $footer.Dock='Bottom'; $footer.Height=135; $footer.BackColor=$ColorBg; $form.Controls.Add($footer)
$script:ConsoleBox=New-Object System.Windows.Forms.TextBox; $script:ConsoleBox.Multiline=$true; $script:ConsoleBox.ReadOnly=$true; $script:ConsoleBox.BackColor=[System.Drawing.Color]::Black; $script:ConsoleBox.ForeColor=$ColorRed; $script:ConsoleBox.Font=New-Object System.Drawing.Font('Consolas',8); $script:ConsoleBox.Dock='Fill'; $script:ConsoleBox.ScrollBars='Vertical'; $footer.Controls.Add($script:ConsoleBox)
$made=New-UiLabel 'made by embofn7' 8 $false $ColorTextDim; $made.Anchor='Bottom,Right'; $made.Location=New-Object System.Drawing.Point(1080,112); $footer.Controls.Add($made)

# ----------------------------------------------------------------------------------------------
# Startup state and timer
# ----------------------------------------------------------------------------------------------
try { $sync.sysinfo=Get-UTSystemInfo } catch { Write-UTLog ('system info failed: '+$_.Exception.Message) -Level Warn }
Refresh-SystemInfoText
Refresh-GameReadyUi

# Initial state scan uses the same backend snapshot logic as the friend's tool.
$sync.busy=$true
Start-UTJob -Kind 'initial-state' -Script '$sync.tweakStates=@{}; Update-UTTweakStates' | Out-Null
Start-UTJob -Kind 'regions-background' -Script 'Start-Sleep -Milliseconds 1200; Measure-UTRegionPing | Out-Null' | Out-Null
Start-UTMonitor

$timer=New-Object System.Windows.Forms.Timer
$timer.Interval=500
$timer.Add_Tick({
    try {
        Drain-UTLog
        Remove-UTFinishedJobs
        # Completion notices
        $done=$null
        while($sync.jobDone.TryDequeue([ref]$done)){
            switch([string]$done){
                'initial-state' { Refresh-TweakLabels; $sync.busy=$false }
                'refresh' { Refresh-SystemInfoText; Refresh-TweakLabels }
                'tweaks' { Refresh-TweakLabels; $sync.busy=$true; Start-UTJob -Kind 'state-refresh' -Script '$sync.tweakStates=@{}; Update-UTTweakStates'|Out-Null }
                'undo' { Refresh-TweakLabels; $sync.busy=$true; Start-UTJob -Kind 'state-refresh' -Script '$sync.tweakStates=@{}; Update-UTTweakStates'|Out-Null }
                'undoall' { Refresh-TweakLabels; $sync.busy=$true; Start-UTJob -Kind 'state-refresh' -Script '$sync.tweakStates=@{}; Update-UTTweakStates'|Out-Null }
                'state-refresh' { Refresh-TweakLabels }
                'regions' { if($sync.regions){$regionBox.Text=Format-UTRegionTable $sync.regions}; $sync.busy=$false }
                'regions-background' { if($sync.regions){$regionBox.Text=Format-UTRegionTable $sync.regions}; if($sync.busy -and $sync.status -like 'pinging*'){$sync.busy=$false} }
                'dns' { if($sync.dnsResults){$regionBox.Text=Format-UTDnsTable $sync.dnsResults}; $sync.busy=$false }
                'tracert' { $sync.busy=$false }
                'linkinfo' { $sync.busy=$false }
                'flush' { $sync.busy=$false }
                'netreset' { $sync.busy=$false }
                'dnsset' { $sync.busy=$false }
                'dnsreset' { $sync.busy=$false }
                'gameready' { $sync.busy=$false; Refresh-GameReadyUi }
                'fortnite' { $sync.busy=$false }
                'fortnite-restore' { $sync.busy=$false }
                'shader' { $sync.busy=$false }
                'launchargs' { $sync.busy=$false }
                'launchargs-clear' { $sync.busy=$false }
                'benchmark' { if($sync.benchmark){$benchBox.Text=($sync.benchmark|Format-List|Out-String)}; $sync.busy=$false }
            }
        }
        $snap=$sync.metrics.Snapshot
        if($snap){
            $cpu=[double]$snap.CpuPercent; $ram=[double]$snap.MemUsedPercent; $gpu=[double]$snap.GpuPercent; $disk=[double]$snap.DiskActivePercent; $net=([double]$snap.NetRxBps+[double]$snap.NetTxBps)/1KB
            $script:StatusLabel.Text= if($sync.needReboot){'Status: reboot recommended'}elseif($sync.busy){'Status: '+$sync.status}else{'Status: ready'}
            $sync.uiMetrics.CPU.Value.Text=('{0:N0}%' -f $cpu);$sync.uiMetrics.RAM.Value.Text=('{0:N0}%  {1:N1} / {2:N0} GB' -f $ram,(([double]$snap.MemTotalBytes-[double]$snap.MemAvailBytes)/1GB),([double]$snap.MemTotalBytes/1GB));$sync.uiMetrics.GPU.Value.Text=('{0:N0}%' -f $gpu);$sync.uiMetrics.DISK.Value.Text=('{0:N0}%' -f $disk);$sync.uiMetrics.NET.Value.Text=(Format-UTRate ($net*1KB))
            foreach($pair in @(@('CPU',$cpu),@('RAM',$ram),@('GPU',$gpu),@('DISK',$disk),@('NET',$net))){$q=$sync.uiMetrics[$pair[0]].Graph.Tag;$q.Enqueue([double]$pair[1]);while($q.Count -gt 70){$q.Dequeue()};$sync.uiMetrics[$pair[0]].Graph.Invalidate()}
        }
    } catch { }
})
$timer.Start(); $sync.timer=$timer

$form.Add_FormClosing({
    param($sender,$e)
    if($sync.busy){$r=[System.Windows.Forms.MessageBox]::Show('Eine Aufgabe läuft noch. Trotzdem schließen?','embofn7tweaks',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Warning);if($r -ne [System.Windows.Forms.DialogResult]::Yes){$e.Cancel=$true;return}}
    $sync.closing=$true;try{$timer.Stop()}catch{};try{Stop-UTMonitor}catch{};try{Stop-UTJobs}catch{}
    Write-UTLog 'closed'
})

Write-UTLog ('ready. {0} | {1} | {2} GB RAM' -f $sync.sysinfo.CPU,$sync.sysinfo.GPU,$sync.sysinfo.RamGB) -Level Ok
[void]$form.ShowDialog()
