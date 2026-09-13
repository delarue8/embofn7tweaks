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
    "cbb3984897d2d38da6b494fd105397fadde03b5e272c0cc50c9342d9f4176a74" = "Bruder"
    "b99281fb5342d5600fdc85b8770e78d1c27912dcc38b1a53f7de4b64ce4a97e2" = "Testperson"
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
        return Get-Content $BackupFile -Raw | ConvertFrom-Json -AsHashtable
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
    @{
        Id = "gamedvr"; Label = "Game DVR / Hintergrundaufnahme aus"
        Desc = "Windows nimmt im Hintergrund staendig Spiel-Clips auf (fuer 'Zuletzt aufgezeichnet'). Kostet CPU/GPU-Leistung waehrend des Spielens - schaltet das komplett ab."
        Apply = {
            Set-RegValueTracked "gamedvr1" "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0
            Set-RegValueTracked "gamedvr2" "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" 0
            Set-RegValueTracked "gamedvr3" "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" 0
        }
    },
    @{
        Id = "mouseaccel"; Label = "Mouse Acceleration aus"
        Desc = "Windows beschleunigt die Mauszeigerbewegung je nach Geschwindigkeit deiner Handbewegung. Fuer Shooter/Fortnite unerwuenscht, weil dieselbe Handbewegung nicht immer dieselbe Zielbewegung ergibt. Macht die Maus 1:1 (linear)."
        Apply = {
            Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -Value "0"
            Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold1" -Value "0"
            Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold2" -Value "0"
        }
    },
    @{
        Id = "stickykeys"; Label = "Sticky/Toggle/Filter Keys Shortcuts aus"
        Desc = "Verhindert, dass 5x Shift druecken oder Umschalt-Taste laenger halten waehrend hektischer Gefechte versehentlich ein Windows-Erleichterungs-Popup oeffnet und dich rauswirft."
        Apply = {
            Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility\StickyKeys" -Name "Flags" -Value "506"
            Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility\ToggleKeys" -Name "Flags" -Value "58"
            Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility\Keyboard Response" -Name "Flags" -Value "122"
        }
    },
    @{
        Id = "edgebg"; Label = "Edge Startup Boost / Hintergrundmodus aus"
        Desc = "Edge startet sonst schon beim Windows-Start unsichtbar im Hintergrund vor, damit er sich 'schneller' oeffnet. Kostet dauerhaft RAM/CPU im Hintergrund, auch wenn du Edge nie nutzt."
        Apply = {
            Set-RegValueTracked "edgebg1" "HKCU:\SOFTWARE\Policies\Microsoft\Edge" "StartupBoostEnabled" 0
            Set-RegValueTracked "edgebg2" "HKCU:\SOFTWARE\Policies\Microsoft\Edge" "BackgroundModeEnabled" 0
        }
    },
    @{
        Id = "widgets"; Label = "Widgets / News-Feed aus"
        Desc = "Deaktiviert das Widgets-Panel (Wetter/News in der Taskleiste), das staendig im Hintergrund Daten nachlaedt."
        Apply = {
            Set-RegValueTracked "widgets1" "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Feeds" "EnableFeeds" 0
            Set-RegValueTracked "widgets2" "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests" 0
        }
    },
    @{
        Id = "telemetry"; Label = "Telemetrie, Feedback-Prompts, Fehlerberichte aus"
        Desc = "Windows sammelt und sendet staendig Nutzungsdaten an Microsoft und fragt gelegentlich nach Feedback. Schaltet das Sammeln und die dazugehoerigen Hintergrund-Tasks ab - spart etwas CPU/Netzwerk."
        Apply = {
            Set-RegValueTracked "tel1" "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0
            Set-RegValueTracked "tel2" "HKCU:\SOFTWARE\Microsoft\Siuf\Rules" "NumberOfSIUFInPeriod" 0
            Get-ScheduledTask -TaskName "Microsoft Compatibility Appraiser" -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
            Get-ScheduledTask -TaskName "Consolidator" -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
        }
    },
    @{
        Id = "startsuggest"; Label = "Start-/Sperrbildschirm-Vorschlaege aus"
        Desc = "Windows zeigt im Startmenue und auf dem Sperrbildschirm App-Werbung/Vorschlaege an und installiert teils sogar automatisch Apps im Hintergrund. Schaltet das komplett ab."
        Apply = {
            $names = @("SubscribedContent-338388Enabled","SubscribedContent-338389Enabled","SubscribedContent-353694Enabled","SilentInstalledAppsEnabled","SystemPaneSuggestionsEnabled")
            foreach ($n in $names) {
                Set-RegValueTracked "cdm_$n" "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" $n 0
            }
        }
    },
    @{
        Id = "websearchcopilotrecall"; Label = "Websuche im Startmenue, Copilot-Datenanalyse und Recall aus"
        Desc = "Drei Datenschutz-relevante Windows-KI-Features in einem: Startmenue-Suche schickt sonst deine Eingaben ans Internet, Copilot darf Bildschirminhalte analysieren, und Windows Recall macht laufend Screenshots deiner Aktivitaet. Schaltet alle drei ab."
        Apply = {
            Set-RegValueTracked "wsc1" "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "ConnectedSearchUseWeb" 0
            Set-RegValueTracked "wsc2" "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCloudSearch" 0
            Set-RegValueTracked "wsc3" "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" 1
            Set-RegValueTracked "wsc4" "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1
            Set-RegValueTracked "wsc5" "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" 1
        }
    },
    @{
        Id = "activityhistory"; Label = "Aktivitaetsverlauf / Upload aus"
        Desc = "Windows speichert und laedt hoch, welche Apps/Dateien du wann geoeffnet hast (fuer die 'Timeline'-Funktion). Schaltet Aufzeichnung und Cloud-Upload davon ab."
        Apply = {
            Set-RegValueTracked "act1" "HKCU:\SOFTWARE\Policies\Microsoft\Windows\System" "EnableActivityFeed" 0
            Set-RegValueTracked "act2" "HKCU:\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities" 0
            Set-RegValueTracked "act3" "HKCU:\SOFTWARE\Policies\Microsoft\Windows\System" "UploadUserActivities" 0
        }
    },
    @{
        Id = "deliveryopt"; Label = "Delivery Optimization Peer-Uploads aus"
        Desc = "Windows-Updates werden standardmaessig auch an andere PCs in deinem Netzwerk/Internet verteilt (wie Torrent). Frisst Bandbreite im Hintergrund - schaltet das reine Upload-an-andere ab, Downloads funktionieren weiter normal."
        Apply = {
            Set-RegValueTracked "do1" "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" "DODownloadMode" 0
        }
    },
    @{
        Id = "wugpu"; Label = "Windows Update ersetzt GPU-Treiber nicht mehr"
        Desc = "Windows Update installiert sonst gelegentlich automatisch einen (oft aelteren) GPU-Treiber ueber deinen manuell installierten NVIDIA/AMD-Treiber drueber. Verhindert das, du behaltst die Kontrolle ueber deinen Treiber."
        Apply = {
            Set-RegValueTracked "wugpu1" "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" "DontPromptForWindowsUpdate" 1
            Set-RegValueTracked "wugpu2" "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" "DontSearchWindowsUpdate" 1
        }
    },
    @{
        Id = "faststartup"; Label = "Fast Startup aus (echter Kaltstart)"
        Desc = "Windows 'friert' beim Herunterfahren den Systemzustand ein statt komplett neu zu starten, fuer schnelleres Hochfahren. Kann aber manchmal Treiber/Netzwerk-Probleme verursachen, die erst ein echter Neustart behebt. Erzwingt einen richtigen Kaltstart."
        Apply = {
            Set-RegValueTracked "fs1" "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" 0
        }
    },
    @{
        Id = "explorerqol"; Label = "Dateiendungen anzeigen + Task beenden im Taskbar"
        Desc = "Zwei reine Komfort-Einstellungen: zeigt .exe/.txt usw. bei Dateinamen an, und fuegt einen 'Task beenden'-Rechtsklick direkt in der Taskleiste hinzu (schnellerer Zugriff als ueber den Task-Manager)."
        Apply = {
            Set-RegValueTracked "exp1" "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideFileExt" 0
            Set-RegValueTracked "exp2" "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarEndTask" 1
        }
    },
    @{
        Id = "startupdelay"; Label = "Startup App Delay entfernen"
        Desc = "Windows verzoegert Autostart-Programme kuenstlich um ca. 10 Sekunden, um den Desktop 'schneller wirken' zu lassen. Entfernt die Verzoegerung, Autostart-Programme starten sofort."
        Apply = {
            Set-RegValueTracked "sd1" "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize" "StartupDelayInMSec" 0
        }
    },
    @{
        Id = "usbpower"; Label = "USB Selective Suspend + PCIe Link Power aus (am Netzteil)"
        Desc = "Windows schaltet USB-Geraete und PCIe-Komponenten (z.B. GPU-Anbindung) zum Stromsparen zeitweise in einen Energiesparmodus, was bei Maus/Tastatur/GPU minimales Input-Lag verursachen kann. Nur relevant, wenn dein PC am Netzteil haengt (Desktop) - deaktiviert Energiesparen dort."
        Apply = {
            powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 | Out-Null
            powercfg /setacvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 0 | Out-Null
            powercfg /setactive SCHEME_CURRENT | Out-Null
        }
    },
    @{
        Id = "clear-temp"; Label = "Temporaere Dateien loeschen (kein Undo noetig)"
        Desc = "Loescht angesammelten Muell im Windows-Temp-Ordner (alte Installationsreste, Cache-Dateien). Reine Aufraeumaktion, hat keinen Performance-Effekt, schafft nur Speicherplatz. Kein Undo noetig, weil nichts Wichtiges geloescht wird."
        Apply = {
            Get-ChildItem -Path $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
        NoUndo = $true
    },
    @{
        Id = "highperfplan"; Label = "Energiesparplan auf Hoechstleistung"
        Desc = "Windows' offizieller 'Hoechstleistung'-Plan (im Gegensatz zu 'Ultimate Performance' ein normaler, standardmaessig verfuegbarer Plan). Haelt CPU durchgehend auf hoher Taktrate statt hoch/runter zu takten."
        Apply = {
            powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
            if ($LASTEXITCODE -ne 0) {
                powercfg -attributes SUB_PROCESSOR PROCTHROTTLEMIN -ATTRIB_HIDE 2>$null
                powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
            }
        }
    },
    @{
        Id = "updateactivehours"; Label = "Windows Update Aktive Stunden setzen (8-24 Uhr)"
        Desc = "Windows startet Updates/Neustarts sonst automatisch, auch mitten in einer Zock-Session. Setzt einen Zeitraum (8-24 Uhr), in dem garantiert kein automatischer Neustart passiert."
        Apply = {
            Set-RegValueTracked "ah1" "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" "ActiveHoursStart" 8
            Set-RegValueTracked "ah2" "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" "ActiveHoursEnd" 24
        }
    },
    @{
        Id = "cortanaoff"; Label = "Cortana deaktivieren"
        Desc = "Windows' Sprachassistentin laeuft bei vielen ungenutzt im Hintergrund mit und braucht etwas RAM. Deaktiviert sie komplett ueber die offizielle Richtlinien-Einstellung."
        Apply = {
            Set-RegValueTracked "cortana1" "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCortana" 0
        }
    },
    @{
        Id = "gpuprefFortnite"; Label = "GPU-Praeferenz: Fortnite auf 'Hohe Leistung'"
        Desc = "Wichtig vor allem bei Laptops mit 2 Grafikkarten (integrierte + dedizierte): stellt sicher, dass Fortnite immer auf der starken GPU laeuft statt versehentlich auf der schwachen internen. Bei reinen Desktop-PCs mit nur einer GPU wirkungslos, aber unschaedlich."
        Apply = {
            $exe = Get-FortniteExePath
            if ($exe) {
                Set-RegValueTracked "gpupref1" "HKCU:\SOFTWARE\Microsoft\DirectX\UserGpuPreferences" $exe "GpuPreference=2;" "String"
            } else {
                Write-Log "Fortnite-Installationspfad nicht gefunden - GPU-Praeferenz uebersprungen (Fortnite ueber Epic Games Launcher installieren und einmal starten)."
            }
        }
    },
    @{
        Id = "dnsflush"; Label = "DNS-Cache leeren (kein Undo noetig)"
        Desc = "Leert den lokalen DNS-Zwischenspeicher. Hilft, wenn Webseiten/Server-Verbindungen wegen veralteter, gecachter Adressen nicht richtig aufgebaut werden. Reine Einmal-Aktion, kein Dauer-Tweak."
        Apply = { ipconfig /flushdns | Out-Null }
        NoUndo = $true
    },
    @{
        Id = "gputelemetry"; Label = "GPU-Hersteller-Telemetrie/Updater-Tasks aus"
        Tier = "OPTIONAL"
        Desc = "NVIDIA/AMD lassen im Hintergrund eigene Telemetrie- und Update-Check-Prozesse laufen (z.B. NvTmMon). Kostet etwas RAM/CPU dauerhaft im Hintergrund - deaktiviert nur diese Zusatz-Tasks, der eigentliche Grafiktreiber bleibt unberuehrt."
        Apply = {
            $taskNames = @("NvTmMon*","NvTmRep*","NvNodeLauncher*","NVIDIA GeForce Experience*","AMD*Telemetry*")
            foreach ($pattern in $taskNames) {
                Get-ScheduledTask -TaskName $pattern -ErrorAction SilentlyContinue |
                    Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
            }
        }
    },
    @{
        Id = "hagson"; Label = "Hardware-accelerated GPU scheduling an (reboot)"
        Tier = "OPTIONAL"; Reboot = $true
        Desc = "Laesst die GPU selbst verwalten, welche Aufgaben sie wann abarbeitet, statt dass Windows das steuert. Kann bei manchen Systemen minimal die Latenz senken, bei anderen keinen Unterschied machen - je nach GPU/Treiber unterschiedlich."
        Apply = {
            Set-RegValueTracked "hags1" "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2
        }
    },
    @{
        Id = "gamemodeoff"; Label = "Windows Game Mode aus"
        Tier = "OPTIONAL"
        Desc = "Windows' eigener 'Game Mode' soll Ressourcen fuers Spiel freihalten, kann aber bei manchen Systemen eher Mikroruckler/Stottern verursachen als helfen. Schaltet ihn komplett aus (manche Spieler bevorzugen das)."
        Apply = {
            Set-RegValueTracked "gm1" "HKCU:\SOFTWARE\Microsoft\GameBar" "AutoGameModeEnabled" 0
            Set-RegValueTracked "gm2" "HKCU:\SOFTWARE\Microsoft\GameBar" "AllowAutoGameMode" 0
        }
    },
    @{
        Id = "gamebaroff"; Label = "Game Bar Pop-ups + Controller-Button aus"
        Tier = "OPTIONAL"
        Desc = "Verhindert, dass beim Druecken der Xbox-Taste/Win+G mitten im Spiel ploetzlich das Game-Bar-Overlay aufpoppt und dich stoert oder Leistung frisst."
        Apply = {
            Set-RegValueTracked "gb1" "HKCU:\SOFTWARE\Microsoft\GameBar" "ShowStartupPanel" 0
            Set-RegValueTracked "gb2" "HKCU:\SOFTWARE\Microsoft\GameBar" "UseNexusForGameBarEnabled" 0
            Set-RegValueTracked "gb3" "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" 0
        }
    },
    @{
        Id = "fsooff"; Label = "Fullscreen Optimizations global aus"
        Tier = "OPTIONAL"
        Desc = "Windows mischt sich bei Vollbild-Spielen manchmal ins Rendering ein (fuer schnelleres Alt+Tab). Kann in seltenen Faellen minimal Input-Lag verursachen. Schaltet das systemweit fuer alle Spiele ab, echtes Vollbild ohne Windows-Eingriff."
        Apply = {
            Set-RegValueTracked "fso1" "HKCU:\System\GameConfigStore" "GameDVR_FSEBehaviorMode" 2
            Set-RegValueTracked "fso2" "HKCU:\System\GameConfigStore" "GameDVR_HonorUserFSEBehaviorMode" 1
            Set-RegValueTracked "fso3" "HKCU:\System\GameConfigStore" "GameDVR_DXGIHonorFSEWindowsCompatible" 1
        }
    },
    @{
        Id = "powerthrottleoff"; Label = "Power Throttling von Hintergrund-Apps aus (Laptop, reboot)"
        Tier = "OPTIONAL"; Reboot = $true
        Desc = "Windows drosselt auf Laptops im Akkubetrieb automatisch Hintergrund-Apps, um Strom zu sparen. Nur relevant fuer Laptops - schaltet die Drosselung ab, falls sie faelschlich auch Spiel-relevante Prozesse trifft."
        Apply = {
            Set-RegValueTracked "pt1" "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" "PowerThrottlingOff" 1
        }
    },
    @{
        Id = "ultimateperf"; Label = "Ultimate Performance Energiesparplan (Desktop)"
        Tier = "OPTIONAL"
        Desc = "Ein spezieller Windows-Energiesparplan, der alle Stromspar-Mechanismen deaktiviert und CPU/GPU staendig auf voller Leistung haelt. Zieht mehr Strom, dafuer keine kurzen Leistungsabfaelle durch Energiesparen. Nur fuer Desktop-PCs sinnvoll."
        Apply = {
            $out = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61
            if ($out -match '([0-9a-f-]{36})') {
                powercfg /setactive $matches[1] | Out-Null
            }
        }
    },
    @{
        Id = "hibernationoff"; Label = "Hibernation aus (Desktop)"
        Tier = "OPTIONAL"
        Desc = "Deaktiviert den Ruhezustand (Systemzustand wird auf die Festplatte geschrieben statt Strom zu ziehen) und loescht die dafuer reservierte hiberfil.sys - gibt dir Speicherplatz zurueck. Nur sinnvoll, wenn du den Ruhezustand eh nie nutzt (bei Desktop-PCs meist der Fall)."
        Apply = { powercfg /hibernate off }
    },
    @{
        Id = "visualeffects"; Label = "Visuelle Effekte auf Leistung (sign-out)"
        Tier = "OPTIONAL"
        Desc = "Schaltet Windows-eigene optische Spielereien ab (Fenster-Animationen, Transparenz, Schatten im Desktop-UI). Bringt kaum echte Spiel-Performance, macht aber die Windows-Oberflaeche selbst spuerbar reaktionsschneller."
        Apply = {
            Set-RegValueTracked "ve1" "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 2
        }
    },
    @{
        Id = "deferfeature"; Label = "Feature-Updates ein Jahr verzoegern"
        Tier = "OPTIONAL"
        Desc = "Grosse Windows-Versions-Updates (z.B. 23H2 -> 24H2) werden ein Jahr lang zurueckgehalten. Sicherheitsupdates kommen trotzdem weiter normal. Verhindert, dass mitten in einer Zock-Session ploetzlich ein riesiges System-Upgrade ansteht."
        Apply = {
            Set-RegValueTracked "df1" "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" "DeferFeatureUpdates" 1
            Set-RegValueTracked "df2" "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" "DeferFeatureUpdatesPeriodInDays" 365
        }
    },
    @{
        Id = "netpowersave"; Label = "Netzwerkadapter Energiesparen + EEE aus"
        Tier = "OPTIONAL"
        Desc = "Netzwerkkarte und Ethernet-Kabel schalten sich sonst bei wenig Traffic kurzzeitig in einen Sparmodus, was minimale Verzoegerung/Ping-Spikes verursachen kann. Haelt die Verbindung durchgehend auf voller Leistung."
        Apply = {
            try { Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Disable-NetAdapterPowerManagement -ErrorAction SilentlyContinue } catch {}
            try {
                Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object {
                    Get-NetAdapterAdvancedProperty -Name $_.Name -DisplayName "Energy Efficient Ethernet" -ErrorAction SilentlyContinue |
                        Set-NetAdapterAdvancedProperty -DisplayValue "Disabled" -ErrorAction SilentlyContinue
                }
            } catch {}
        }
    },
    @{
        Id = "teredooff"; Label = "Teredo Tunnelling aus"
        Tier = "OPTIONAL"
        Desc = "Teredo ist ein IPv6-ueber-IPv4-Tunnel-Feature, das kaum noch jemand braucht, aber im Hintergrund mitlaeuft. Deaktiviert es, minimal weniger Netzwerk-Overhead."
        Apply = { netsh interface teredo set state disabled | Out-Null }
    },
    @{
        Id = "searchindexoff"; Label = "Windows Search Indexierung aus (reboot)"
        Tier = "OPTIONAL"; Reboot = $true
        Desc = "Windows durchsucht staendig im Hintergrund deine Festplatte, um die Windows-Suche schneller zu machen - kostet dauerhaft etwas Festplatten-/CPU-Last. Deaktiviert den Indexierungsdienst komplett, die Suche wird dafuer etwas langsamer."
        Apply = {
            Set-Service -Name "WSearch" -StartupType Disabled -ErrorAction SilentlyContinue
            Stop-Service -Name "WSearch" -Force -ErrorAction SilentlyContinue
        }
    },
    @{
        Id = "memintegrityoff"; Label = "Memory Integrity / Core Isolation aus (reboot)"
        Tier = "RISKY"; Reboot = $true
        Desc = "Prueft normalerweise, dass kein bösartiger Code in geschuetzte Speicherbereiche gelangt. Manche Spieler deaktivieren das fuer minimal mehr CPU-Leistung."
        Warning = "Schaltet einen Sicherheitsschutz gegen Kernel-Angriffe ab. Manche Anticheats (z.B. Vanguard) verlangen diesen AN - fuer PCs mit Valorant nicht empfohlen."
        Apply = {
            Set-RegValueTracked "mi1" "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" "Enabled" 0
        }
    },
    @{
        Id = "vbsoff"; Label = "Virtualization-based Security aus (reboot)"
        Tier = "RISKY"; Reboot = $true
        Desc = "VBS nutzt Virtualisierung, um kritische Windows-Teile vom Rest des Systems abzuschotten (moderner Sicherheitsschutz). Manche Spieler deaktivieren es fuer minimal mehr CPU-Leistung."
        Warning = "Deaktiviert den kompletten Hyper-V-Sicherheitsunterbau. Kann Boot-Probleme verursachen und wird von manchen Anticheats vorausgesetzt."
        Apply = {
            Set-RegValueTracked "vbs1" "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard" "EnableVirtualizationBasedSecurity" 0
        }
    },
    @{
        Id = "dyntickoff"; Label = "Dynamic Timer Tick aus (bcdedit, reboot)"
        Tier = "RISKY"; Reboot = $true
        Desc = "Windows passt normalerweise die interne Timer-Frequenz dynamisch an, um Strom zu sparen. Diese Option erzwingt eine konstante, hohe Timer-Frequenz, was manche fuer minimal stabilere Frametimes nutzen."
        Warning = "Systemweite Timer-Einstellung. Kann in seltenen Faellen Energiesparfunktionen/Stabilitaet beeinflussen. Undo per bcdedit noetig, nicht ueber Registry-Backup."
        Apply = { bcdedit /set disabledynamictick yes | Out-Null }
        NoUndo = $true
    },
    @{
        Id = "globaltimerres"; Label = "Global Timer Resolution (nur Windows 11 Build 22000+, reboot)"
        Tier = "RISKY"; Reboot = $true
        Desc = "Erlaubt Programmen, systemweit eine feinere Timer-Aufloesung anzufordern (weniger Mikroruckler moeglich)."
        Warning = "Nur auf Windows 11 (Build 22000 oder neuer) verfuegbar. Auf aelteren Builds wird der Tweak automatisch uebersprungen."
        Apply = {
            $build = [System.Environment]::OSVersion.Version.Build
            if ($build -lt 22000) {
                Write-Log "Uebersprungen: Windows Build $build ist kleiner als 22000."
                return
            }
            Set-RegValueTracked "gtr1" "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" "GlobalTimerResolutionRequests" 1
        }
    }
)

$FortniteIniPath = "$env:LOCALAPPDATA\FortniteGame\Saved\Config\WindowsClient\GameUserSettings.ini"
$FortniteBackupPath = "$FortniteIniPath.embofn7bak"

function Test-FortniteInstalled {
    return (Test-Path $FortniteIniPath)
}

function Set-IniValue {
    param([System.Collections.Generic.List[string]]$Lines, [string]$Section, [string]$Key, [string]$Value)
    $sectionPattern = "^\[" + [regex]::Escape($Section) + "\]\s*$"
    $keyPattern = "^" + [regex]::Escape($Key) + "\s*="
    $inSection = $false
    $found = $false
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($line in $Lines) {
        if ($line -match $sectionPattern) {
            $inSection = $true
            $result.Add($line)
            continue
        }
        if ($inSection -and $line -match "^\[.*\]\s*$") {
            if (-not $found) { $result.Add("$Key=$Value"); $found = $true }
            $inSection = $false
        }
        if ($inSection -and -not $found -and $line -match $keyPattern) {
            $result.Add("$Key=$Value")
            $found = $true
            continue
        }
        $result.Add($line)
    }
    if (-not $found) {
        if ($inSection) {
            $result.Add("$Key=$Value")
        } else {
            $result.Add("")
            $result.Add("[$Section]")
            $result.Add("$Key=$Value")
        }
    }
    return $result
}

function Backup-FortniteIni {
    if (-not (Test-Path $FortniteBackupPath)) {
        Copy-Item -Path $FortniteIniPath -Destination $FortniteBackupPath -Force
        Write-Log "Fortnite-Config gesichert nach: $FortniteBackupPath"
    }
}

function Set-FortniteProfile {
    param([string]$ProfileKey)
    if (-not (Test-FortniteInstalled)) {
        Write-Log "Fortnite-Config nicht gefunden. Bitte Fortnite einmal starten, ins Hauptmenue kommen und wieder schliessen, dann existiert die Datei."
        return
    }
    Backup-FortniteIni
    $section = "/Script/FortniteGame.FortGameUserSettings"
    $lines = [System.Collections.Generic.List[string]](Get-Content -Path $FortniteIniPath)

    $profiles = @{
        "MaxFPS" = @{
            "sg.ResolutionQuality" = "100"; "sg.ViewDistanceQuality" = "0"; "sg.AntiAliasingQuality" = "0"
            "sg.ShadowQuality" = "0"; "sg.PostProcessQuality" = "0"; "sg.EffectsQuality" = "0"
            "sg.FoliageQuality" = "0"; "sg.ShadingQuality" = "0"; "sg.TextureQuality" = "0"
            "bUseVSync" = "False"; "bUseDynamicResolution" = "False"
        }
        "Balanced" = @{
            "sg.ResolutionQuality" = "100"; "sg.ViewDistanceQuality" = "2"; "sg.AntiAliasingQuality" = "0"
            "sg.ShadowQuality" = "0"; "sg.PostProcessQuality" = "1"; "sg.EffectsQuality" = "1"
            "sg.FoliageQuality" = "1"; "sg.ShadingQuality" = "1"; "sg.TextureQuality" = "2"
            "bUseVSync" = "False"; "bUseDynamicResolution" = "False"
        }
        "LatencyOnly" = @{
            "bUseVSync" = "False"; "bUseDynamicResolution" = "False"
        }
        "Potato" = @{
            "sg.ResolutionQuality" = "75"; "sg.ViewDistanceQuality" = "0"; "sg.AntiAliasingQuality" = "0"
            "sg.ShadowQuality" = "0"; "sg.PostProcessQuality" = "0"; "sg.EffectsQuality" = "0"
            "sg.FoliageQuality" = "0"; "sg.ShadingQuality" = "0"; "sg.TextureQuality" = "0"
            "bUseVSync" = "False"; "bUseDynamicResolution" = "False"
        }
    }

    $settings = $profiles[$ProfileKey]
    if (-not $settings) { Write-Log "Unbekanntes Profil: $ProfileKey"; return }
    foreach ($key in $settings.Keys) {
        $lines = Set-IniValue -Lines $lines -Section $section -Key $key -Value $settings[$key]
    }
    [System.IO.File]::WriteAllLines($FortniteIniPath, $lines, (New-Object System.Text.UTF8Encoding($false)))
    Write-Log "Fortnite-Profil '$ProfileKey' angewendet ($($settings.Count) Werte gesetzt)."
    if ($ProfileKey -eq "MaxFPS" -or $ProfileKey -eq "Potato") {
        Write-Log "Hinweis: 'Performance Mode' selbst bitte einmalig im Spiel unter Video-Einstellungen aktivieren (Epic-interner Key aendert sich je Season)."
    }
}

function Clear-FortniteShaderCaches {
    $paths = @(
        "$env:LOCALAPPDATA\FortniteGame\Saved\VulkanPSOCache",
        "$env:LOCALAPPDATA\D3DSCache",
        "$env:LOCALAPPDATA\NVIDIA\DXCache",
        "$env:LOCALAPPDATA\NVIDIA\GLCache"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) {
            try {
                Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "Shader-Cache geleert: $p"
            } catch {
                Write-Log "Konnte Shader-Cache nicht vollstaendig leeren: $p"
            }
        }
    }
}

function Restore-FortniteIni {
    if (Test-Path $FortniteBackupPath) {
        Copy-Item -Path $FortniteBackupPath -Destination $FortniteIniPath -Force
        Remove-Item -Path $FortniteBackupPath -Force
        Write-Log "Fortnite-Config aus Backup wiederhergestellt."
    } else {
        Write-Log "Kein Fortnite-Backup gefunden."
    }
}

$form                 = New-Object System.Windows.Forms.Form
$form.Text            = "embofn7tweaks"
$form.Size            = New-Object System.Drawing.Size(950, 720)
$form.StartPosition   = "CenterScreen"
$form.BackColor       = $ColorBg
$form.ForeColor       = $ColorText
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox     = $false

$title = New-Object System.Windows.Forms.Label
$title.Text = "embofn7tweaks - SAFE / OPTIONAL / RISKY"
$title.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = $ColorRed
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(325,10)
$form.Controls.Add($title)

$userLbl = New-Object System.Windows.Forms.Label
$userLbl.Text = "eingeloggt als: $script:AuthorizedUser"
$userLbl.ForeColor = $ColorTextDim
$userLbl.AutoSize = $true
$userLbl.Location = New-Object System.Drawing.Point(730,15)
$form.Controls.Add($userLbl)

function New-StatBlock {
    param([string]$LabelText, [int]$Y)
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point(15, $Y)
    $panel.Size = New-Object System.Drawing.Size(290, 95)
    $panel.BackColor = $ColorPanelBg

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $LabelText
    $lbl.ForeColor = $ColorTextDim
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $lbl.AutoSize = $true
    $lbl.Location = New-Object System.Drawing.Point(8, 5)
    $panel.Controls.Add($lbl)

    $valLbl = New-Object System.Windows.Forms.Label
    $valLbl.Text = "..."
    $valLbl.ForeColor = $ColorRed
    $valLbl.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $valLbl.AutoSize = $true
    $valLbl.Location = New-Object System.Drawing.Point(8, 22)
    $panel.Controls.Add($valLbl)

    $graphBox = New-Object System.Windows.Forms.Panel
    $graphBox.Location = New-Object System.Drawing.Point(8, 50)
    $graphBox.Size = New-Object System.Drawing.Size(274, 38)
    $graphBox.BackColor = [System.Drawing.Color]::Black
    $panel.Controls.Add($graphBox)

    return @{ Panel = $panel; ValueLabel = $valLbl; GraphBox = $graphBox; History = New-Object System.Collections.ArrayList }
}

function Add-GraphPaintHandler {
    param($StatBlock, [double]$MaxValue = 100)
    $StatBlock.GraphBox.Add_Paint({
        param($sender, $e)
        $hist = $StatBlock.History
        if ($hist.Count -lt 2) { return }
        $w = $sender.Width; $h = $sender.Height
        $pen = New-Object System.Drawing.Pen($ColorRed, 1.5)
        $stepX = $w / [double]([Math]::Max($hist.Count - 1, 1))
        for ($i = 0; $i -lt $hist.Count - 1; $i++) {
            $v1 = [Math]::Min([double]$hist[$i] / $MaxValue, 1.0)
            $v2 = [Math]::Min([double]$hist[$i+1] / $MaxValue, 1.0)
            $x1 = $i * $stepX; $y1 = $h - ($v1 * $h)
            $x2 = ($i+1) * $stepX; $y2 = $h - ($v2 * $h)
            $e.Graphics.DrawLine($pen, $x1, $y1, $x2, $y2)
        }
        $pen.Dispose()
    }.GetNewClosure())
}

$statCpu = New-StatBlock "CPU" 45
$statRam = New-StatBlock "MEMORY" 150
$statGpu = New-StatBlock "GPU" 255
$statDisk = New-StatBlock "DISK ACTIVE" 360
$statNet = New-StatBlock "NETWORK" 465

foreach ($sb in @($statCpu, $statRam, $statGpu, $statDisk, $statNet)) {
    $form.Controls.Add($sb.Panel)
}
Add-GraphPaintHandler $statCpu 100
Add-GraphPaintHandler $statRam 100
Add-GraphPaintHandler $statGpu 100
Add-GraphPaintHandler $statDisk 100
Add-GraphPaintHandler $statNet 100000   # ~100 MB/s als Obergrenze fuer die Skala

try { $cpuCounter = New-Object System.Diagnostics.PerformanceCounter("Processor", "% Processor Time", "_Total"); $cpuCounter.NextValue() | Out-Null } catch { $cpuCounter = $null }
try { $diskCounter = New-Object System.Diagnostics.PerformanceCounter("PhysicalDisk", "% Disk Time", "_Total"); $diskCounter.NextValue() | Out-Null } catch { $diskCounter = $null }
try {
    $netInstances = (New-Object System.Diagnostics.PerformanceCounterCategory("Network Interface")).GetInstanceNames() |
        Where-Object { $_ -notmatch "Loopback|isatap|Teredo" }
    $netCounters = $netInstances | ForEach-Object { New-Object System.Diagnostics.PerformanceCounter("Network Interface", "Bytes Total/sec", $_) }
    $netCounters | ForEach-Object { $_.NextValue() | Out-Null }
} catch { $netCounters = @() }

$statTimer = New-Object System.Windows.Forms.Timer
$statTimer.Interval = 1500
$statTimer.Add_Tick({
    try {
        $cpuVal = if ($cpuCounter) { [Math]::Round($cpuCounter.NextValue(), 0) } else { $null }
    } catch { $cpuVal = $null }
    if ($cpuVal -ne $null) {
        $statCpu.ValueLabel.Text = "$cpuVal%"
        [void]$statCpu.History.Add($cpuVal)
    } else { $statCpu.ValueLabel.Text = "n/a" }

    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $totalGb = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $freeGb  = [Math]::Round($os.FreePhysicalMemory / 1MB, 1)
        $usedGb  = [Math]::Round($totalGb - $freeGb, 1)
        $ramPct  = [Math]::Round((($totalGb - $freeGb) / $totalGb) * 100, 0)
        $statRam.ValueLabel.Text = "$ramPct%  $usedGb / $totalGb GB"
        [void]$statRam.History.Add($ramPct)
    } catch { $statRam.ValueLabel.Text = "n/a" }

    try {
        $gpuSamples = (Get-Counter '\GPU Engine(*engtype_3D)\Utilization Percentage' -ErrorAction Stop).CounterSamples
        $gpuVal = [Math]::Round((($gpuSamples | Measure-Object CookedValue -Sum).Sum), 0)
        if ($gpuVal -gt 100) { $gpuVal = 100 }
        $statGpu.ValueLabel.Text = "$gpuVal%"
        [void]$statGpu.History.Add($gpuVal)
    } catch { $statGpu.ValueLabel.Text = "n/a" }

    try {
        $diskVal = if ($diskCounter) { [Math]::Round($diskCounter.NextValue(), 0) } else { $null }
        if ($diskVal -gt 100) { $diskVal = 100 }
    } catch { $diskVal = $null }
    if ($diskVal -ne $null) {
        $statDisk.ValueLabel.Text = "$diskVal%"
        [void]$statDisk.History.Add($diskVal)
    } else { $statDisk.ValueLabel.Text = "n/a" }

    try {
        $totalBytes = 0
        foreach ($nc in $netCounters) { $totalBytes += $nc.NextValue() }
        $kbps = [Math]::Round($totalBytes / 1024, 0)
        $statNet.ValueLabel.Text = "$kbps KB/s"
        [void]$statNet.History.Add($totalBytes)
    } catch { $statNet.ValueLabel.Text = "n/a" }

    foreach ($sb in @($statCpu, $statRam, $statGpu, $statDisk, $statNet)) {
        if ($sb.History.Count -gt 60) { $sb.History.RemoveAt(0) }
        $sb.GraphBox.Invalidate()
    }
})
$statTimer.Start()

$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Location = New-Object System.Drawing.Point(320,45)
$tabControl.Size = New-Object System.Drawing.Size(610, 605)
$form.Controls.Add($tabControl)

$tabTweaks = New-Object System.Windows.Forms.TabPage
$tabTweaks.Text = "TWEAKS"
$tabTweaks.BackColor = $ColorBg
$tabControl.Controls.Add($tabTweaks)

$tabNetwork = New-Object System.Windows.Forms.TabPage
$tabNetwork.Text = "NETWORK"
$tabNetwork.BackColor = $ColorBg
$tabControl.Controls.Add($tabNetwork)

$tabGameReady = New-Object System.Windows.Forms.TabPage
$tabGameReady.Text = "GAME READY"
$tabGameReady.BackColor = $ColorBg
$tabControl.Controls.Add($tabGameReady)

$tabInfo = New-Object System.Windows.Forms.TabPage
$tabInfo.Text = "INFO"
$tabInfo.BackColor = $ColorBg
$tabControl.Controls.Add($tabInfo)

$checkAll = New-Object System.Windows.Forms.CheckBox
$checkAll.Text = "SAFE-Preset auswaehlen (empfohlen)"
$checkAll.ForeColor = $ColorText
$checkAll.AutoSize = $true
$checkAll.Location = New-Object System.Drawing.Point(10,10)
$tabTweaks.Controls.Add($checkAll)

$restorePointCheck = New-Object System.Windows.Forms.CheckBox
$restorePointCheck.Text = "Restore Point vor dem Anwenden erstellen"
$restorePointCheck.ForeColor = $ColorText
$restorePointCheck.AutoSize = $true
$restorePointCheck.Checked = $true
$restorePointCheck.Location = New-Object System.Drawing.Point(10,35)
$tabTweaks.Controls.Add($restorePointCheck)

$listPanel = New-Object System.Windows.Forms.Panel
$listPanel.Location = New-Object System.Drawing.Point(10,65)
$listPanel.Size = New-Object System.Drawing.Size(585, 315)
$listPanel.AutoScroll = $true
$listPanel.BackColor = $ColorPanelBg
$tabTweaks.Controls.Add($listPanel)

$checkBoxes = @{}
$y = 5
$lastTier = $null
$tierColors = @{ "SAFE" = $ColorText; "OPTIONAL" = [System.Drawing.Color]::FromArgb(255,180,120); "RISKY" = $ColorRed }
$tierHeaders = @{ "SAFE" = "SAFE (empfohlen, keine Nachteile)"; "OPTIONAL" = "OPTIONAL (dokumentiert, meist unproblematisch)"; "RISKY" = "RISKY - jede Zeile vorher lesen!" }

foreach ($tweak in $Tweaks) {
    $tier = if ($tweak.Tier) { $tweak.Tier } else { "SAFE" }
    if ($tier -ne $lastTier) {
        if ($lastTier -ne $null) { $y += 8 }
        $header = New-Object System.Windows.Forms.Label
        $header.Text = $tierHeaders[$tier]
        $header.ForeColor = $tierColors[$tier]
        $header.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $header.AutoSize = $true
        $header.Location = New-Object System.Drawing.Point(10, $y)
        $listPanel.Controls.Add($header)
        $y += 22
        $lastTier = $tier
    }
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $tweak.Label
    $cb.ForeColor = $tierColors[$tier]
    $cb.AutoSize = $true
    $cb.Location = New-Object System.Drawing.Point(20, $y)
    $tooltipText = if ($tweak.Desc) { $tweak.Desc } else { "" }
    if ($tweak.Warning) { $tooltipText = "$tooltipText`r`nACHTUNG: $($tweak.Warning)".Trim() }
    if ($tooltipText -ne "") {
        $toolTip = New-Object System.Windows.Forms.ToolTip
        $toolTip.AutoPopDelay = 15000
        $toolTip.SetToolTip($cb, $tooltipText)
    }
    $listPanel.Controls.Add($cb)
    $checkBoxes[$tweak.Id] = $cb
    $y += 24
}

$checkAll.Add_CheckedChanged({
    foreach ($tweak in $Tweaks) {
        $tier = if ($tweak.Tier) { $tweak.Tier } else { "SAFE" }
        if ($tier -eq "SAFE") { $checkBoxes[$tweak.Id].Checked = $checkAll.Checked }
    }
})

$y += 15
$fnHeader = New-Object System.Windows.Forms.Label
$fnHeader.Text = "FORTNITE - Video settings profile (GameUserSettings.ini)"
$fnHeader.ForeColor = $ColorRed
$fnHeader.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$fnHeader.AutoSize = $true
$fnHeader.Location = New-Object System.Drawing.Point(10, $y)
$listPanel.Controls.Add($fnHeader)
$y += 22

$fnProfiles = @(
    @{ Name = "Max FPS (Performance Mode, everything low)"; Key = "MaxFPS" }
    @{ Name = "Balanced (niedrige Schatten/Effekte, mittlere Texturen)"; Key = "Balanced" }
    @{ Name = "Latency only (Optik bleibt, nur Input/Render-Latenz-Settings)"; Key = "LatencyOnly" }
    @{ Name = "Potato (75% Renderaufloesung, alles aus)"; Key = "Potato" }
)
$fnProfileRadios = @{}
foreach ($p in $fnProfiles) {
    $rb = New-Object System.Windows.Forms.RadioButton
    $rb.Text = $p.Name
    $rb.ForeColor = $ColorText
    $rb.AutoSize = $true
    $rb.Location = New-Object System.Drawing.Point(20, $y)
    $listPanel.Controls.Add($rb)
    $fnProfileRadios[$p.Key] = $rb
    $y += 22
}
$fnProfileRadios["MaxFPS"].Checked = $true

$fnApplyBtn = New-Object System.Windows.Forms.Button
$fnApplyBtn.Text = "Apply profile"
$fnApplyBtn.BackColor = $ColorRed
$fnApplyBtn.ForeColor = [System.Drawing.Color]::White
$fnApplyBtn.FlatStyle = "Flat"
$fnApplyBtn.Location = New-Object System.Drawing.Point(20, $y)
$fnApplyBtn.Size = New-Object System.Drawing.Size(110,28)
$listPanel.Controls.Add($fnApplyBtn)

$fnRestoreBtn = New-Object System.Windows.Forms.Button
$fnRestoreBtn.Text = "Restore original"
$fnRestoreBtn.BackColor = $ColorRedDark
$fnRestoreBtn.ForeColor = [System.Drawing.Color]::White
$fnRestoreBtn.FlatStyle = "Flat"
$fnRestoreBtn.Location = New-Object System.Drawing.Point(135, $y)
$fnRestoreBtn.Size = New-Object System.Drawing.Size(110,28)
$listPanel.Controls.Add($fnRestoreBtn)

$fnClearShaderBtn = New-Object System.Windows.Forms.Button
$fnClearShaderBtn.Text = "Clear shader caches"
$fnClearShaderBtn.BackColor = $ColorRedDark
$fnClearShaderBtn.ForeColor = [System.Drawing.Color]::White
$fnClearShaderBtn.FlatStyle = "Flat"
$fnClearShaderBtn.Location = New-Object System.Drawing.Point(250, $y)
$fnClearShaderBtn.Size = New-Object System.Drawing.Size(150,28)
$listPanel.Controls.Add($fnClearShaderBtn)
$y += 36

$fnResultLbl = New-Object System.Windows.Forms.Label
$fnResultLbl.Text = if (Test-FortniteInstalled) { "Fortnite-Config gefunden." } else { "Fortnite-Config nicht gefunden (bitte einmal starten und schliessen)." }
$fnResultLbl.ForeColor = $ColorTextDim
$fnResultLbl.AutoSize = $true
$fnResultLbl.Location = New-Object System.Drawing.Point(20, $y)
$listPanel.Controls.Add($fnResultLbl)
$y += 30

$fnLaunchHeader = New-Object System.Windows.Forms.Label
$fnLaunchHeader.Text = "Launch arguments (fuer Epic Games Launcher - manuell einfuegen)"
$fnLaunchHeader.ForeColor = $ColorRed
$fnLaunchHeader.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$fnLaunchHeader.AutoSize = $true
$fnLaunchHeader.Location = New-Object System.Drawing.Point(10, $y)
$listPanel.Controls.Add($fnLaunchHeader)
$y += 22

$fnArgs = @(
    @{ Arg = "-NOSPLASH"; Desc = "Skip the splash screen"; Default = $true }
    @{ Arg = "-FeatureLevelES31"; Desc = "Force Performance Mode renderer"; Default = $false }
    @{ Arg = "-d3d12"; Desc = "Force DirectX 12 (Shader Model 6)"; Default = $false }
    @{ Arg = "-high -d3d11"; Desc = "Legacy DirectX 11 Performance Mode (aeltere NVIDIA-Karten)"; Default = $false }
    @{ Arg = "-nosound"; Desc = "No audio device"; Default = $false }
)
$fnArgChecks = @{}
foreach ($a in $fnArgs) {
    $cb2 = New-Object System.Windows.Forms.CheckBox
    $cb2.Text = "$($a.Arg)   $($a.Desc)"
    $cb2.ForeColor = $ColorText
    $cb2.AutoSize = $true
    $cb2.Checked = $a.Default
    $cb2.Location = New-Object System.Drawing.Point(20, $y)
    $listPanel.Controls.Add($cb2)
    $fnArgChecks[$a.Arg] = $cb2
    $y += 22
}

$fnCopyArgsBtn = New-Object System.Windows.Forms.Button
$fnCopyArgsBtn.Text = "In Zwischenablage kopieren"
$fnCopyArgsBtn.BackColor = $ColorRed
$fnCopyArgsBtn.ForeColor = [System.Drawing.Color]::White
$fnCopyArgsBtn.FlatStyle = "Flat"
$fnCopyArgsBtn.Location = New-Object System.Drawing.Point(20, $y)
$fnCopyArgsBtn.Size = New-Object System.Drawing.Size(200,28)
$listPanel.Controls.Add($fnCopyArgsBtn)
$y += 36

$fnLaunchNote = New-Object System.Windows.Forms.Label
$fnLaunchNote.Text = "Einfuegen: Epic Games Launcher -> Fortnite -> Zahnrad-Icon -> Command Line Arguments -> einfuegen -> speichern."
$fnLaunchNote.ForeColor = $ColorTextDim
$fnLaunchNote.AutoSize = $true
$fnLaunchNote.MaximumSize = New-Object System.Drawing.Size(555,0)
$fnLaunchNote.Location = New-Object System.Drawing.Point(20, $y)
$listPanel.Controls.Add($fnLaunchNote)
$y += 40

$fnNvidiaHeader = New-Object System.Windows.Forms.Label
$fnNvidiaHeader.Text = "NVIDIA driver profile (manuell)"
$fnNvidiaHeader.ForeColor = $ColorRed
$fnNvidiaHeader.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$fnNvidiaHeader.AutoSize = $true
$fnNvidiaHeader.Location = New-Object System.Drawing.Point(10, $y)
$listPanel.Controls.Add($fnNvidiaHeader)
$y += 22

$fnNvidiaText = New-Object System.Windows.Forms.Label
$fnNvidiaText.Text = @"
Empfohlen fuer Fortnite:
 - Energieverwaltungsmodus: Maximale Leistung bevorzugen
 - Texturfilterung Qualitaet: Leistung
 - Vertikale Synchronisierung: Aus
 - Anzahl vorausberechneter Frames: 1

Manuell, weil: Diese Werte liegen in einer internen NVIDIA-Treiber-
Datenbank. Falsch gesetzt per Script = korruptes Profil. Ueber die
echte NVIDIA-Oberflaeche geht's sicher und dauert nur 30 Sekunden.
"@
$fnNvidiaText.ForeColor = $ColorText
$fnNvidiaText.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$fnNvidiaText.AutoSize = $true
$fnNvidiaText.MaximumSize = New-Object System.Drawing.Size(555, 0)
$fnNvidiaText.Location = New-Object System.Drawing.Point(20, $y)
$listPanel.Controls.Add($fnNvidiaText)
$y += 130

$fnOpenNvidiaBtn = New-Object System.Windows.Forms.Button
$fnOpenNvidiaBtn.Text = "NVIDIA Systemsteuerung oeffnen"
$fnOpenNvidiaBtn.BackColor = $ColorRedDark
$fnOpenNvidiaBtn.ForeColor = [System.Drawing.Color]::White
$fnOpenNvidiaBtn.FlatStyle = "Flat"
$fnOpenNvidiaBtn.Location = New-Object System.Drawing.Point(20, $y)
$fnOpenNvidiaBtn.Size = New-Object System.Drawing.Size(220,28)
$listPanel.Controls.Add($fnOpenNvidiaBtn)
$y += 40

$fnApplyBtn.Add_Click({
    $selectedProfile = ($fnProfileRadios.Keys | Where-Object { $fnProfileRadios[$_].Checked })
    Set-FortniteProfile -ProfileKey $selectedProfile
    if (Test-FortniteInstalled) {
        $fnResultLbl.ForeColor = [System.Drawing.Color]::FromArgb(90,200,90)
        $fnResultLbl.Text = "Profil '$selectedProfile' angewendet. Details im Log unten."
    } else {
        $fnResultLbl.ForeColor = $ColorRed
        $fnResultLbl.Text = "Fortnite-Config nicht gefunden - Fortnite einmal starten und schliessen."
    }
})

$fnRestoreBtn.Add_Click({
    Restore-FortniteIni
    $fnResultLbl.ForeColor = [System.Drawing.Color]::FromArgb(90,200,90)
    $fnResultLbl.Text = "Original-Config wiederhergestellt (falls Backup vorhanden war)."
})

$fnClearShaderBtn.Add_Click({
    Clear-FortniteShaderCaches
    $fnResultLbl.ForeColor = [System.Drawing.Color]::FromArgb(90,200,90)
    $fnResultLbl.Text = "Shader-Caches geleert."
})

$fnCopyArgsBtn.Add_Click({
    $chosen = $fnArgChecks.Keys | Where-Object { $fnArgChecks[$_].Checked }
    $argString = ($chosen -join " ")
    if ($argString -eq "") {
        Write-Log "Keine Launch Arguments ausgewaehlt."
    } else {
        [System.Windows.Forms.Clipboard]::SetText($argString)
        Write-Log "In Zwischenablage kopiert: $argString"
    }
})

$fnOpenNvidiaBtn.Add_Click({
    try { Start-Process "nvcplui.exe" } catch { Write-Log "NVIDIA Systemsteuerung konnte nicht geoeffnet werden - ist ein NVIDIA-Treiber installiert?" }
})

$OutputBox = New-Object System.Windows.Forms.TextBox
$OutputBox.Multiline = $true
$OutputBox.ScrollBars = "Vertical"
$OutputBox.ReadOnly = $true
$OutputBox.BackColor = [System.Drawing.Color]::Black
$OutputBox.ForeColor = $ColorRed
$OutputBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$OutputBox.Location = New-Object System.Drawing.Point(10,390)
$OutputBox.Size = New-Object System.Drawing.Size(585,110)
$tabTweaks.Controls.Add($OutputBox)

$statusLbl = New-Object System.Windows.Forms.Label
$statusLbl.Text = "bereit"
$statusLbl.ForeColor = $ColorTextDim
$statusLbl.AutoSize = $true
$statusLbl.Location = New-Object System.Drawing.Point(10,505)
$tabTweaks.Controls.Add($statusLbl)

$applyBtn = New-Object System.Windows.Forms.Button
$applyBtn.Text = "Apply selected"
$applyBtn.BackColor = $ColorRed
$applyBtn.ForeColor = [System.Drawing.Color]::White
$applyBtn.FlatStyle = "Flat"
$applyBtn.Location = New-Object System.Drawing.Point(10,525)
$applyBtn.Size = New-Object System.Drawing.Size(150,35)
$tabTweaks.Controls.Add($applyBtn)

$undoBtn = New-Object System.Windows.Forms.Button
$undoBtn.Text = "Undo everything"
$undoBtn.BackColor = $ColorRedDark
$undoBtn.ForeColor = [System.Drawing.Color]::White
$undoBtn.FlatStyle = "Flat"
$undoBtn.Location = New-Object System.Drawing.Point(175,525)
$undoBtn.Size = New-Object System.Drawing.Size(150,35)
$tabTweaks.Controls.Add($undoBtn)

$footer = New-Object System.Windows.Forms.Label
$footer.Text = "made by embofn7"
$footer.ForeColor = $ColorTextDim
$footer.AutoSize = $true
$footer.Location = New-Object System.Drawing.Point(790,655)
$form.Controls.Add($footer)

$netRegions = @(
    @{ Name = "Internet (Cloudflare)"; Host = "1.1.1.1" }
    @{ Name = "Europe"; Host = "185.228.168.9" }
    @{ Name = "NA-East"; Host = "8.8.8.8" }
    @{ Name = "NA-West"; Host = "208.67.222.222" }
    @{ Name = "Asia"; Host = "1.0.0.1" }
)

$netHint = New-Object System.Windows.Forms.Label
$netHint.Text = "Annaeherung ueber oeffentliche Anycast-Server in der Region - kein exakter Fortnite-Server-Ping."
$netHint.ForeColor = $ColorTextDim
$netHint.AutoSize = $true
$netHint.Location = New-Object System.Drawing.Point(10,10)
$tabNetwork.Controls.Add($netHint)

$netPingBtn = New-Object System.Windows.Forms.Button
$netPingBtn.Text = "Ping regions now"
$netPingBtn.BackColor = $ColorRed
$netPingBtn.ForeColor = [System.Drawing.Color]::White
$netPingBtn.FlatStyle = "Flat"
$netPingBtn.Location = New-Object System.Drawing.Point(10,35)
$netPingBtn.Size = New-Object System.Drawing.Size(150,30)
$tabNetwork.Controls.Add($netPingBtn)

$netGrid = New-Object System.Windows.Forms.DataGridView
$netGrid.Location = New-Object System.Drawing.Point(10,75)
$netGrid.Size = New-Object System.Drawing.Size(580,150)
$netGrid.BackgroundColor = $ColorPanelBg
$netGrid.ReadOnly = $true
$netGrid.AllowUserToAddRows = $false
$netGrid.RowHeadersVisible = $false
$netGrid.Columns.Add("Region","Region") | Out-Null
$netGrid.Columns.Add("Avg","AVG ms") | Out-Null
$netGrid.Columns.Add("Min","MIN ms") | Out-Null
$netGrid.Columns.Add("Max","MAX ms") | Out-Null
$netGrid.Columns.Add("Loss","LOSS") | Out-Null
foreach ($r in $netRegions) { $netGrid.Rows.Add($r.Name, "-", "-", "-", "-") | Out-Null }
$tabNetwork.Controls.Add($netGrid)

$netPingBtn.Add_Click({
    $netPingBtn.Enabled = $false
    for ($i = 0; $i -lt $netRegions.Count; $i++) {
        $region = $netRegions[$i]
        try {
            $results = Test-Connection -ComputerName $region.Host -Count 4 -ErrorAction Stop
            $times = $results | ForEach-Object { $_.ResponseTime }
            $avg = [Math]::Round(($times | Measure-Object -Average).Average, 0)
            $min = ($times | Measure-Object -Minimum).Minimum
            $max = ($times | Measure-Object -Maximum).Maximum
            $loss = [Math]::Round((4 - $results.Count) / 4 * 100, 0)
            $netGrid.Rows[$i].Cells["Avg"].Value = $avg
            $netGrid.Rows[$i].Cells["Min"].Value = $min
            $netGrid.Rows[$i].Cells["Max"].Value = $max
            $netGrid.Rows[$i].Cells["Loss"].Value = "$loss%"
        } catch {
            $netGrid.Rows[$i].Cells["Avg"].Value = "n/a"
            $netGrid.Rows[$i].Cells["Loss"].Value = "100%"
        }
    }
    $netPingBtn.Enabled = $true
})

$dnsHeader = New-Object System.Windows.Forms.Label
$dnsHeader.Text = "DNS resolver"
$dnsHeader.ForeColor = $ColorRed
$dnsHeader.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$dnsHeader.AutoSize = $true
$dnsHeader.Location = New-Object System.Drawing.Point(10,235)
$tabNetwork.Controls.Add($dnsHeader)

$dnsResolvers = @(
    @{ Name = "Cloudflare (1.1.1.1)"; Ip = "1.1.1.1" }
    @{ Name = "Google (8.8.8.8)"; Ip = "8.8.8.8" }
    @{ Name = "Quad9 (9.9.9.9)"; Ip = "9.9.9.9" }
    @{ Name = "OpenDNS (208.67.222.222)"; Ip = "208.67.222.222" }
    @{ Name = "AdGuard (94.140.14.14)"; Ip = "94.140.14.14" }
)

$dnsList = New-Object System.Windows.Forms.ListBox
$dnsList.Location = New-Object System.Drawing.Point(10,260)
$dnsList.Size = New-Object System.Drawing.Size(280,110)
$dnsList.BackColor = $ColorPanelBg
$dnsList.ForeColor = $ColorText
foreach ($d in $dnsResolvers) { [void]$dnsList.Items.Add($d.Name) }
$tabNetwork.Controls.Add($dnsList)

$dnsResultBox = New-Object System.Windows.Forms.TextBox
$dnsResultBox.Multiline = $true
$dnsResultBox.ReadOnly = $true
$dnsResultBox.BackColor = [System.Drawing.Color]::Black
$dnsResultBox.ForeColor = $ColorRed
$dnsResultBox.Location = New-Object System.Drawing.Point(300,260)
$dnsResultBox.Size = New-Object System.Drawing.Size(290,110)
$tabNetwork.Controls.Add($dnsResultBox)

$dnsBenchBtn = New-Object System.Windows.Forms.Button
$dnsBenchBtn.Text = "Benchmark resolvers"
$dnsBenchBtn.BackColor = $ColorRedDark
$dnsBenchBtn.ForeColor = [System.Drawing.Color]::White
$dnsBenchBtn.FlatStyle = "Flat"
$dnsBenchBtn.Location = New-Object System.Drawing.Point(10,380)
$dnsBenchBtn.Size = New-Object System.Drawing.Size(150,30)
$tabNetwork.Controls.Add($dnsBenchBtn)

$dnsUseBtn = New-Object System.Windows.Forms.Button
$dnsUseBtn.Text = "Use selected resolver"
$dnsUseBtn.BackColor = $ColorRed
$dnsUseBtn.ForeColor = [System.Drawing.Color]::White
$dnsUseBtn.FlatStyle = "Flat"
$dnsUseBtn.Location = New-Object System.Drawing.Point(170,380)
$dnsUseBtn.Size = New-Object System.Drawing.Size(180,30)
$tabNetwork.Controls.Add($dnsUseBtn)

$dnsResetBtn = New-Object System.Windows.Forms.Button
$dnsResetBtn.Text = "Back to automatic"
$dnsResetBtn.BackColor = $ColorRedDark
$dnsResetBtn.ForeColor = [System.Drawing.Color]::White
$dnsResetBtn.FlatStyle = "Flat"
$dnsResetBtn.Location = New-Object System.Drawing.Point(360,380)
$dnsResetBtn.Size = New-Object System.Drawing.Size(180,30)
$tabNetwork.Controls.Add($dnsResetBtn)

$dnsStatusLbl = New-Object System.Windows.Forms.Label
$dnsStatusLbl.Text = "aendert deine System-DNS-Server - echte Netzwerkaenderung"
$dnsStatusLbl.ForeColor = $ColorTextDim
$dnsStatusLbl.AutoSize = $true
$dnsStatusLbl.Location = New-Object System.Drawing.Point(10,420)
$tabNetwork.Controls.Add($dnsStatusLbl)

$dnsBenchBtn.Add_Click({
    $dnsResultBox.Clear()
    foreach ($d in $dnsResolvers) {
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            Resolve-DnsName -Name "www.fortnite.com" -Server $d.Ip -ErrorAction Stop | Out-Null
            $sw.Stop()
            $dnsResultBox.AppendText("$($d.Name): $($sw.ElapsedMilliseconds) ms`r`n")
        } catch {
            $dnsResultBox.AppendText("$($d.Name): Fehler/Timeout`r`n")
        }
    }
})

function Get-ActiveAdapterAlias {
    return (Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1 -ExpandProperty Name)
}

$dnsUseBtn.Add_Click({
    if ($dnsList.SelectedIndex -lt 0) { Write-Log "Kein DNS-Resolver ausgewaehlt."; return }
    $selected = $dnsResolvers[$dnsList.SelectedIndex]
    $adapter = Get-ActiveAdapterAlias
    if (-not $adapter) { Write-Log "Kein aktiver Netzwerkadapter gefunden."; return }
    try {
        Set-DnsClientServerAddress -InterfaceAlias $adapter -ServerAddresses $selected.Ip
        Write-Log "DNS auf $($selected.Name) gesetzt (Adapter: $adapter)."
    } catch {
        Write-Log "Fehler beim Setzen des DNS-Servers: $($_.Exception.Message)"
    }
})

$dnsResetBtn.Add_Click({
    $adapter = Get-ActiveAdapterAlias
    if (-not $adapter) { Write-Log "Kein aktiver Netzwerkadapter gefunden."; return }
    try {
        Set-DnsClientServerAddress -InterfaceAlias $adapter -ResetServerAddresses
        Write-Log "DNS zurueck auf automatisch/Router (Adapter: $adapter)."
    } catch {
        Write-Log "Fehler beim Zuruecksetzen des DNS-Servers: $($_.Exception.Message)"
    }
})

$grHeader = New-Object System.Windows.Forms.Label
$grHeader.Text = "Laufende Programme mit Fenster"
$grHeader.ForeColor = $ColorRed
$grHeader.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$grHeader.AutoSize = $true
$grHeader.Location = New-Object System.Drawing.Point(10,10)
$tabGameReady.Controls.Add($grHeader)

$grRefreshBtn = New-Object System.Windows.Forms.Button
$grRefreshBtn.Text = "Refresh"
$grRefreshBtn.BackColor = $ColorRedDark
$grRefreshBtn.ForeColor = [System.Drawing.Color]::White
$grRefreshBtn.FlatStyle = "Flat"
$grRefreshBtn.Location = New-Object System.Drawing.Point(480,5)
$grRefreshBtn.Size = New-Object System.Drawing.Size(100,28)
$tabGameReady.Controls.Add($grRefreshBtn)

$grListPanel = New-Object System.Windows.Forms.Panel
$grListPanel.Location = New-Object System.Drawing.Point(10,35)
$grListPanel.Size = New-Object System.Drawing.Size(580,480)
$grListPanel.AutoScroll = $true
$grListPanel.BackColor = $ColorPanelBg
$tabGameReady.Controls.Add($grListPanel)

$grCloseBtn = New-Object System.Windows.Forms.Button
$grCloseBtn.Text = "Close selected"
$grCloseBtn.BackColor = $ColorRed
$grCloseBtn.ForeColor = [System.Drawing.Color]::White
$grCloseBtn.FlatStyle = "Flat"
$grCloseBtn.Location = New-Object System.Drawing.Point(10,525)
$grCloseBtn.Size = New-Object System.Drawing.Size(150,30)
$tabGameReady.Controls.Add($grCloseBtn)

$grStatusLbl = New-Object System.Windows.Forms.Label
$grStatusLbl.Text = "angehakt = wird geschlossen. Nichts wird automatisch beendet."
$grStatusLbl.ForeColor = $ColorTextDim
$grStatusLbl.AutoSize = $true
$grStatusLbl.Location = New-Object System.Drawing.Point(170,530)
$tabGameReady.Controls.Add($grStatusLbl)

$grProtectedNames = @("embofn7tweaks","powershell","powershell_ise","explorer","dwm","csrss","wininit","winlogon","services","lsass","svchost")

function Update-GameReadyList {
    $grListPanel.Controls.Clear()
    $script:grCheckBoxes = @{}
    $yy = 5
    $procs = Get-Process | Where-Object { $_.MainWindowTitle -ne "" -and $grProtectedNames -notcontains $_.ProcessName } | Sort-Object ProcessName -Unique
    foreach ($p in $procs) {
        $cb3 = New-Object System.Windows.Forms.CheckBox
        try { $mem = [Math]::Round($p.WorkingSet64 / 1MB, 0) } catch { $mem = 0 }
        $cb3.Text = "$($p.ProcessName)  -  $($p.MainWindowTitle)  ($mem MB)"
        $cb3.ForeColor = $ColorText
        $cb3.AutoSize = $true
        $cb3.Location = New-Object System.Drawing.Point(10, $yy)
        $cb3.Tag = $p.Id
        $grListPanel.Controls.Add($cb3)
        $script:grCheckBoxes[$p.Id] = $cb3
        $yy += 24
    }
}
Update-GameReadyList

$grRefreshBtn.Add_Click({ Update-GameReadyList })

$grCloseBtn.Add_Click({
    $toClose = $script:grCheckBoxes.Keys | Where-Object { $script:grCheckBoxes[$_].Checked }
    $closed = 0
    foreach ($procId in $toClose) {
        try {
            Stop-Process -Id $procId -Force -ErrorAction Stop
            $closed++
        } catch {
            Write-Log "Konnte Prozess $procId nicht schliessen: $($_.Exception.Message)"
        }
    }
    Write-Log "Game Ready: $closed Programm(e) geschlossen."
    Update-GameReadyList
})

$infoText = New-Object System.Windows.Forms.TextBox
$infoText.Multiline = $true
$infoText.ReadOnly = $true
$infoText.ScrollBars = "Vertical"
$infoText.BackColor = [System.Drawing.Color]::Black
$infoText.ForeColor = $ColorText
$infoText.Font = New-Object System.Drawing.Font("Consolas", 10)
$infoText.Location = New-Object System.Drawing.Point(10,10)
$infoText.Size = New-Object System.Drawing.Size(580,540)
$tabInfo.Controls.Add($infoText)

try {
    $cs = Get-CimInstance Win32_ComputerSystem
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor
    $gpu = Get-CimInstance Win32_VideoController | Select-Object -First 1
    $ramGb = [Math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    $infoLines = @(
        "embofn7tweaks v1.0"
        "made by embofn7"
        ""
        "CPU:      $($cpu.Name)"
        "GPU:      $($gpu.Name)"
        "RAM:      $ramGb GB"
        "OS:       $($os.Caption) (Build $($os.BuildNumber))"
        "Rechner:  $($cs.Name)"
        ""
        "Log-Ordner:   $LogFolder"
        "Aktuelles Log: $LogFile"
        "Backup-Datei:  $BackupFile"
        ""
        "Fortnite-Config: $(if (Test-FortniteInstalled) { $FortniteIniPath } else { 'nicht gefunden' })"
        ""
        "Funktionsidee inspiriert von unknowntweaks (unknownaimer)."
    )
    $infoText.Text = ($infoLines -join "`r`n")
} catch {
    $infoText.Text = "Systeminfos konnten nicht vollstaendig geladen werden: $($_.Exception.Message)"
}

$applyBtn.Add_Click({
    $applyBtn.Enabled = $false
    $statusLbl.Text = "laeuft..."
    $selected = $Tweaks | Where-Object { $checkBoxes[$_.Id].Checked }
    if ($selected.Count -eq 0) {
        Write-Log "Keine Tweaks ausgewaehlt."
        $statusLbl.Text = "nichts ausgewaehlt"
        $applyBtn.Enabled = $true
        return
    }
    if ($restorePointCheck.Checked) {
        Write-Log "Erstelle Restore Point..."
        New-SystemRestorePoint
    }
    $ok = 0; $fail = 0; $rebootNeeded = $false
    foreach ($tweak in $selected) {
        try {
            & $tweak.Apply
            Write-Log "OK: $($tweak.Label)"
            $ok++
            if ($tweak.Reboot) { $rebootNeeded = $true }
        } catch {
            Write-Log "FEHLER bei $($tweak.Label): $($_.Exception.Message)"
            $fail++
        }
    }
    $summary = "Fertig. $ok erfolgreich, $fail fehlgeschlagen."
    Write-Log $summary
    if ($fail -eq 0) {
        $statusLbl.Text = "$ok erfolgreich - alles ok"
        $statusLbl.ForeColor = [System.Drawing.Color]::FromArgb(90,200,90)
    } else {
        $statusLbl.Text = "$ok erfolgreich, $fail fehlgeschlagen - siehe Log unten"
        $statusLbl.ForeColor = $ColorRed
    }
    $applyBtn.Enabled = $true

    if ($rebootNeeded) {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            "Einige der angewendeten Tweaks werden erst nach einem Neustart aktiv.`n`nJetzt neu starten?",
            "Neustart empfohlen",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
            Write-Log "Neustart durch Nutzer bestaetigt."
            Restart-Computer -Force
        } else {
            Write-Log "Neustart abgelehnt - Tweaks werden erst nach manuellem Neustart voll wirksam."
        }
    }
})

$undoBtn.Add_Click({
    $undoBtn.Enabled = $false
    $statusLbl.Text = "setze zurueck..."
    $backup = Get-Backup
    if ($backup.Count -eq 0) {
        Write-Log "Nichts zum Rueckgaengigmachen gefunden."
        $statusLbl.Text = "nichts zum zuruecksetzen"
        $undoBtn.Enabled = $true
        return
    }
    $count = 0
    foreach ($id in @($backup.Keys)) {
        try {
            Restore-RegValueTracked -TweakId $id
            Write-Log "Zurueckgesetzt: $id"
            $count++
        } catch {
            Write-Log "Fehler beim Zuruecksetzen von $id : $($_.Exception.Message)"
        }
    }
    Write-Log "Undo abgeschlossen. $count Werte zurueckgesetzt."
    $statusLbl.Text = "$count Werte zurueckgesetzt"
    $statusLbl.ForeColor = [System.Drawing.Color]::FromArgb(90,200,90)
    $undoBtn.Enabled = $true
})

$form.Add_FormClosing({ $statTimer.Stop() })

Write-Log "embofn7tweaks gestartet von: $script:AuthorizedUser | Log: $LogFile"
[void]$form.ShowDialog()

