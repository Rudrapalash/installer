<#
.SYNOPSIS
    Select-and-install software launcher using winget.
.DESCRIPTION
    Shows a checklist GUI of common software. Elevates to Admin ONCE at startup
    (single UAC prompt), then installs everything you check in one run.
.NOTES
    Requires: Windows 10 21H2+ / Windows 11.
    If winget (App Installer) is missing, this script will attempt to
    download and install it automatically before continuing.
#>

# ============================================================
# 1. SELF-ELEVATION (ask for admin only once)
# ============================================================
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if (-not $IsAdmin) {
    $scriptPath = $MyInvocation.MyCommand.Path
    Start-Process -FilePath "powershell.exe" `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" `
        -Verb RunAs
    exit
}

# From here on, everything runs elevated — no further UAC prompts.

# ============================================================
# 2. ENSURE WINGET IS AVAILABLE (auto-install if missing)
# ============================================================
function Install-Winget {
    <#
        Installs the "App Installer" package (which provides winget) by
        downloading the latest release directly from Microsoft/winget-cli
        on GitHub, along with its required dependency packages, and
        registering them with Add-AppxPackage.
    #>

    Write-Host "winget not found. Attempting to install it automatically..."

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $tempDir = Join-Path $env:TEMP ("winget-setup-" + [Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        # --- Dependencies required by the App Installer package ---
        $vclibsUrl = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
        $vclibsFile = Join-Path $tempDir "Microsoft.VCLibs.x64.14.00.Desktop.appx"
        Invoke-WebRequest -Uri $vclibsUrl -OutFile $vclibsFile -UseBasicParsing

        # UI.Xaml is shipped as a nupkg containing the appx; grab it via GitHub mirror instead
        $uiXamlUrl = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx"
        $uiXamlFile = Join-Path $tempDir "Microsoft.UI.Xaml.2.8.x64.appx"
        Invoke-WebRequest -Uri $uiXamlUrl -OutFile $uiXamlFile -UseBasicParsing

        # --- Main App Installer (winget) package ---
        $wingetUrl = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        $wingetFile = Join-Path $tempDir "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        Invoke-WebRequest -Uri $wingetUrl -OutFile $wingetFile -UseBasicParsing

        # License file needed for provisioning on some SKUs (best-effort, ignore failure)
        try {
            $licenseUrl = "https://github.com/microsoft/winget-cli/releases/latest/download/6d61be7c65e9491587bec06e6a1e2be3_License1.xml"
            $licenseFile = Join-Path $tempDir "License1.xml"
            Invoke-WebRequest -Uri $licenseUrl -OutFile $licenseFile -UseBasicParsing -ErrorAction SilentlyContinue
        } catch { }

        # Install dependencies first, then the main package
        Add-AppxPackage -Path $vclibsFile -ErrorAction SilentlyContinue
        Add-AppxPackage -Path $uiXamlFile -ErrorAction SilentlyContinue
        Add-AppxPackage -Path $wingetFile -ErrorAction Stop

        Write-Host "App Installer (winget) installation attempted successfully."
    }
    catch {
        Write-Host "Automatic winget installation failed: $($_.Exception.Message)"
    }
    finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Refresh PATH for the current process in case winget was just registered
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Install-Winget

    # Give the system a moment to register the app, then re-check
    Start-Sleep -Seconds 3

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            "winget (Windows Package Manager) could not be installed automatically.`n`nPlease install 'App Installer' from the Microsoft Store manually, then re-run this script.",
            "Missing Dependency",
            "OK",
            "Error"
        ) | Out-Null
        exit
    }

    Write-Host "winget is now available. Continuing..."
}

# ============================================================
# 3. SOFTWARE CATALOG  -> Display Name = winget package ID
#    Add/remove/edit entries here as you like.
# ============================================================
$Catalog = [ordered]@{
    "Google Chrome"              = "Google.Chrome"
    "Mozilla Firefox"            = "Mozilla.Firefox"
    "Microsoft Edge"             = "Microsoft.Edge"
    "7-Zip"                      = "7zip.7zip"
    "WinRAR"                     = "RARLab.WinRAR"
    "VLC Media Player"           = "VideoLAN.VLC"
    "Visual Studio Code"         = "Microsoft.VisualStudioCode"
    "Notepad++"                  = "Notepad++.Notepad++"
    "Git"                        = "Git.Git"
    "Python 3"                   = "Python.Python.3.12"
    "Node.js LTS"                = "OpenJS.NodeJS.LTS"
    "Java (Temurin 21 LTS)"      = "EclipseAdoptium.Temurin.21.JDK"
    "Docker Desktop"             = "Docker.DockerDesktop"
    "PuTTY"                      = "PuTTY.PuTTY"
    "WinSCP"                     = "WinSCP.WinSCP"
    "Postman"                    = "Postman.Postman"
    "Slack"                      = "SlackTechnologies.Slack"
    "Zoom"                       = "Zoom.Zoom"
    "Discord"                    = "Discord.Discord"
    "Telegram Desktop"           = "Telegram.TelegramDesktop"
    "Spotify"                    = "Spotify.Spotify"
    "Adobe Acrobat Reader"       = "Adobe.Acrobat.Reader.64-bit"
    "GIMP"                       = "GIMP.GIMP"
    "Paint.NET"                  = "dotPDN.PaintDotNet"
    "OBS Studio"                 = "OBSProject.OBSStudio"
    "qBittorrent"                = "qBittorrent.qBittorrent"
    "Steam"                      = "Valve.Steam"
    "Microsoft PowerToys"        = "Microsoft.PowerToys"
    "TeamViewer"                 = "TeamViewer.TeamViewer"
    "AnyDesk"                    = "AnyDeskSoftwareGmbH.AnyDesk"
    "CCleaner"                   = "Piriform.CCleaner"

    # --- Requested additions (31-42 + related) ---
    "MySQL Workbench"            = "Oracle.MySQLWorkbench"
    "Eclipse IDE for Java Developers (2026-06)" = "EclipseFoundation.Eclipse.Java"
    "Burp Suite (Community Edition)" = "PortSwigger.BurpSuite.Community"
    "PowerShell 7"               = "Microsoft.PowerShell"
    "AWS CLI v2"                 = "Amazon.AWSCLI"
    "Microsoft Azure CLI"        = "Microsoft.AzureCLI"
    "SQL DACPAC (SqlPackage)"    = "Microsoft.SqlPackage"
    "Ubuntu 24.04 LTS (WSL)"     = "Canonical.Ubuntu.2404"
}

# Custom installers for packages not available (or not reliably available) via winget.
# Each entry: Type = exe | zip | psmodule | jar
$CustomCatalog = [ordered]@{
    "Maven" = @{
        Type        = "zip"
        Url         = "https://dlcdn.apache.org/maven/maven-3/3.9.9/binaries/apache-maven-3.9.9-bin.zip"
        InstallRoot = "$env:ProgramFiles\Apache"
        BinPath     = "$env:ProgramFiles\Apache\apache-maven-3.9.9\bin"
    }
    "TestNG" = @{
        Type        = "jar"
        Url         = "https://repo1.maven.org/maven2/org/testng/testng/7.10.2/testng-7.10.2.jar"
        InstallPath = "$env:ProgramFiles\TestNG\testng-7.10.2.jar"
    }
    "PowerShell for AWS" = @{
        Type   = "psmodule"
        Module = "AWS.Tools.Installer"
    }
    ".NET Runtime 2.0.5" = @{
        Type = "exe"
        Url  = "https://download.microsoft.com/download/1/1/0/11046135-4207-40D3-A795-13ECEA741B32/dotnet-runtime-2.0.5-win-x64.exe"
        Args = "/install /quiet /norestart"
    }
    ".NET Core Windows Hosting 2.0.5" = @{
        Type = "exe"
        Url  = "https://download.microsoft.com/download/1/1/0/11046135-4207-40D3-A795-13ECEA741B32/DotNetCore.2.0.5-WindowsHosting.exe"
        Args = "/install /quiet /norestart"
    }
    ".NET SDK 2.1.4" = @{
        Type = "exe"
        Url  = "https://download.microsoft.com/download/1/1/5/115B762D-2B41-4AF3-9A63-92D9680B9409/dotnet-sdk-2.1.4-win-x64.exe"
        Args = "/install /quiet /norestart"
    }
}

function Add-ToMachinePath([string]$PathToAdd) {
    if (-not (Test-Path $PathToAdd)) { return $false }

    $current = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $parts = $current -split ";" | Where-Object { $_ -and $_.Trim() -ne "" }
    if ($parts -contains $PathToAdd) { return $true }

    $updated = ($parts + $PathToAdd) -join ";"
    [Environment]::SetEnvironmentVariable("Path", $updated, "Machine")
    return $true
}

function Install-CustomPackage {
    param(
        [string]$Name,
        [hashtable]$Config
    )

    switch ($Config.Type) {
        "exe" {
            $tempFile = Join-Path $env:TEMP ("installer-" + [Guid]::NewGuid().ToString() + ".exe")
            Invoke-WebRequest -Uri $Config.Url -OutFile $tempFile -UseBasicParsing
            $proc = Start-Process -FilePath $tempFile -ArgumentList $Config.Args -Wait -PassThru
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            return ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010)
        }
        "zip" {
            $tempZip = Join-Path $env:TEMP ("package-" + [Guid]::NewGuid().ToString() + ".zip")
            Invoke-WebRequest -Uri $Config.Url -OutFile $tempZip -UseBasicParsing
            New-Item -ItemType Directory -Path $Config.InstallRoot -Force | Out-Null
            Expand-Archive -Path $tempZip -DestinationPath $Config.InstallRoot -Force
            Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
            return (Add-ToMachinePath $Config.BinPath)
        }
        "jar" {
            $destDir = Split-Path $Config.InstallPath -Parent
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            Invoke-WebRequest -Uri $Config.Url -OutFile $Config.InstallPath -UseBasicParsing
            return (Test-Path $Config.InstallPath)
        }
        "psmodule" {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
            }
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
            Install-Module -Name $Config.Module -Force -Scope AllUsers -AllowClobber -ErrorAction Stop
            Install-AWSToolsModule AWS.Tools.Common -Force -ErrorAction Stop
            return $true
        }
        default {
            throw "Unsupported custom install type: $($Config.Type)"
        }
    }
}

# ============================================================
# 4. BUILD THE GUI
# ============================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$form                 = New-Object System.Windows.Forms.Form
$form.Text            = "Software Installer"
$form.Size            = New-Object System.Drawing.Size(560, 680)
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox     = $false

$label = New-Object System.Windows.Forms.Label
$label.Text = "Select the software to install, then click Install."
$label.AutoSize = $true
$label.Location = New-Object System.Drawing.Point(15, 15)
$form.Controls.Add($label)

$checkList = New-Object System.Windows.Forms.CheckedListBox
$checkList.Location = New-Object System.Drawing.Point(15, 40)
$checkList.Size = New-Object System.Drawing.Size(515, 460)
$checkList.CheckOnClick = $true
foreach ($name in $Catalog.Keys) { [void]$checkList.Items.Add($name) }
foreach ($name in $CustomCatalog.Keys) { [void]$checkList.Items.Add($name) }
$form.Controls.Add($checkList)

$selectAllBtn = New-Object System.Windows.Forms.Button
$selectAllBtn.Text = "Select All"
$selectAllBtn.Location = New-Object System.Drawing.Point(15, 510)
$selectAllBtn.Size = New-Object System.Drawing.Size(100, 28)
$selectAllBtn.Add_Click({
    for ($i = 0; $i -lt $checkList.Items.Count; $i++) { $checkList.SetItemChecked($i, $true) }
})
$form.Controls.Add($selectAllBtn)

$clearBtn = New-Object System.Windows.Forms.Button
$clearBtn.Text = "Clear All"
$clearBtn.Location = New-Object System.Drawing.Point(125, 510)
$clearBtn.Size = New-Object System.Drawing.Size(100, 28)
$clearBtn.Add_Click({
    for ($i = 0; $i -lt $checkList.Items.Count; $i++) { $checkList.SetItemChecked($i, $false) }
})
$form.Controls.Add($clearBtn)

$installBtn = New-Object System.Windows.Forms.Button
$installBtn.Text = "Install Selected"
$installBtn.Location = New-Object System.Drawing.Point(405, 510)
$installBtn.Size = New-Object System.Drawing.Size(125, 28)
$form.Controls.Add($installBtn)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(15, 550)
$logBox.Size = New-Object System.Drawing.Size(515, 90)
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$form.Controls.Add($logBox)

function Write-Log($text) {
    $logBox.AppendText("$text`r`n")
    $logBox.SelectionStart = $logBox.Text.Length
    $logBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

# ============================================================
# 5. INSTALL LOGIC
# ============================================================
$installBtn.Add_Click({
    $selected = $checkList.CheckedItems
    if ($selected.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No software selected.", "Nothing to do") | Out-Null
        return
    }

    $installBtn.Enabled    = $false
    $selectAllBtn.Enabled  = $false
    $clearBtn.Enabled      = $false
    $checkList.Enabled     = $false

    Write-Log "Starting installation of $($selected.Count) package(s)..."
    Write-Log "------------------------------------------------"

    $results = @()

    foreach ($name in $selected) {
        try {
            if ($CustomCatalog.Contains($name)) {
                Write-Log "Installing: $name  (custom) ..."
                $ok = Install-CustomPackage -Name $name -Config $CustomCatalog[$name]
                if ($ok) {
                    Write-Log "  -> SUCCESS: $name"
                    $results += "[OK]   $name"
                } else {
                    Write-Log "  -> FAILED: $name"
                    $results += "[FAIL] $name"
                }
                continue
            }

            $pkgId = $Catalog[$name]
            Write-Log "Installing: $name  ($pkgId) ..."

            $args = @(
                "install",
                "--id", $pkgId,
                "-e",
                "--silent",
                "--accept-package-agreements",
                "--accept-source-agreements",
                "--disable-interactivity"
            )

            $proc = Start-Process -FilePath "winget" -ArgumentList $args -Wait -PassThru -WindowStyle Hidden

            if ($proc.ExitCode -eq 0) {
                Write-Log "  -> SUCCESS: $name"
                $results += "[OK]   $name"
            } else {
                Write-Log "  -> FAILED (exit code $($proc.ExitCode)): $name"
                $results += "[FAIL] $name (exit $($proc.ExitCode))"
            }
        } catch {
            Write-Log "  -> FAILED: $name ($($_.Exception.Message))"
            $results += "[FAIL] $name ($($_.Exception.Message))"
        }
    }

    Write-Log "------------------------------------------------"
    Write-Log "All done."

    $summary = $results -join "`r`n"
    [System.Windows.Forms.MessageBox]::Show($summary, "Installation Summary") | Out-Null

    $installBtn.Enabled    = $true
    $selectAllBtn.Enabled  = $true
    $clearBtn.Enabled      = $true
    $checkList.Enabled     = $true
})

[void]$form.ShowDialog()