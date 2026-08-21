# --- Admin Elevation Logic ---
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output "Cerberus needs to be run as Administrator. Attempting to relaunch."
    $argList = $args
    $script = if ($PSCommandPath) {
        "& { & `'$($PSCommandPath)`' $($argList -join ' ') }"
    } else {
        "&([ScriptBlock]::Create((irm mcinstall.narwal.llc))) $($argList -join ' ')"
    }
    $powershellCmd = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
    $processCmd = if (Get-Command wt.exe -ErrorAction SilentlyContinue) { "wt.exe" } else { "$powershellCmd" }
    if ($processCmd -eq "wt.exe") {
        Start-Process $processCmd -ArgumentList "$powershellCmd -ExecutionPolicy Bypass -NoProfile -Command `"$script`"" -Verb RunAs
    } else {
        Start-Process $processCmd -ArgumentList "-ExecutionPolicy Bypass -NoProfile -Command `"$script`"" -Verb RunAs
    }
    break
}

# --- Configuration ---
$prismExePath = "$env:LOCALAPPDATA\Programs\PrismLauncher\prismlauncher.exe"
$prismPath = "$env:APPDATA\PrismLauncher"
$instancePath = "$prismPath\instances\Euphoria Pack +"
$minecraftPath = "$instancePath\minecraft"
$modsPath = "$minecraftPath\mods"
$autoModPath = "$minecraftPath\automodpack"

$dropboxUrl = "https://www.dropbox.com/scl/fi/3htbxd9sr9vw3n4e2ltsc/Euphoria-Pack.zip?rlkey=vca2u4tw0pyjihcrji2a7kll8&st=zk8c5262&dl=1"
$tempZip = "$env:TEMP\EuphoriaDownload.zip"
$tempExtract = "$env:TEMP\EuphoriaExtract"

# --- Execution ---
Clear-Host

Write-Host "  ==============================================" -ForegroundColor DarkGray
Write-Host "       CERBERUS  //  Euphoria Pack Installer    " -ForegroundColor Cyan
Write-Host "  ==============================================" -ForegroundColor DarkGray
Write-Host ""

$choice = Read-Host "  Would you like to update/install the modpack? (yes/no)"
if ($choice -ne "yes") { exit }
Write-Host ""

# 1. Prism Launcher Check & Auto-Install
if (!(Test-Path $prismExePath)) {
    Write-Host "  [!] Prism Launcher not found. Attempting install via Winget..." -ForegroundColor Yellow
    Write-Host ""
    winget install PrismLauncher.PrismLauncher --accept-source-agreements --accept-package-agreements -e
    if ($LASTEXITCODE -ne 0 -and !(Test-Path $prismExePath)) {
        Write-Host ""
        Write-Host "  [X] Winget install failed!" -ForegroundColor Red
        Write-Host "      Install manually: https://prismlauncher.org/" -ForegroundColor Red
        Write-Host "      Then re-run this script." -ForegroundColor Red
        Write-Host ""
        Pause; exit
    }
    Write-Host ""
    Start-Sleep -Seconds 5
}

# 2. Folder Preparation
if (!(Test-Path $instancePath)) { New-Item -ItemType Directory -Path $instancePath | Out-Null }
if (!(Test-Path $minecraftPath)) { New-Item -ItemType Directory -Path $minecraftPath | Out-Null }

# 3. Download
Write-Host "  [1/5] Downloading modpack contents..." -ForegroundColor Cyan
if (Test-Path $tempZip) { Remove-Item $tempZip -Force }
$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -Uri $dropboxUrl -OutFile $tempZip
$ProgressPreference = 'Continue'

# 4. Extraction
Write-Host "  [2/5] Extracting files..." -ForegroundColor Cyan
if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue }
Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force

# 5. File Handling & Dynamic Path Patching
Write-Host "  [3/5] Patching configuration files..." -ForegroundColor Cyan
$filesToOverwrite = @("instance.cfg", "mmc-pack.json", "minecraft/servers.dat")

foreach ($relPath in $filesToOverwrite) {
    $srcFile = Join-Path $tempExtract $relPath
    $destFile = Join-Path $instancePath $relPath
    
    if (Test-Path $srcFile) {
        if ($relPath -eq "instance.cfg") {
            Write-Host "        > Patching instance.cfg for current user..." -ForegroundColor DarkGray
            $content = Get-Content $srcFile -Raw
            $pattern = "JavaPath=C:/Users/[^/]+/AppData/Roaming/PrismLauncher"
            $replacement = "JavaPath=$($env:APPDATA -replace '\\', '/')/PrismLauncher"
            $content = $content -replace $pattern, $replacement
            Set-Content -Path $destFile -Value $content
        } else {
            Write-Host "        > Updating $($relPath)..." -ForegroundColor DarkGray
            $destDir = Split-Path $destFile
            if (!(Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir | Out-Null }
            Copy-Item $srcFile $destFile -Force
        }
    }
}

# options.txt keybind overwrite prompt
$srcOptions = Join-Path $tempExtract "minecraft/options.txt"
if (Test-Path $srcOptions) {
    Write-Host ""
    Write-Host "  [?] Would you like to overwrite keybinds with the server default? (y/n)" -ForegroundColor Yellow
    Write-Host "      Recommended if this is your first time using the modpack."
    Write-Host "      Warning: This will overwrite your current keybinds for this instance." -ForegroundColor Red
    Write-Host ""
    $keybindChoice = Read-Host "  y/n"
    if ($keybindChoice -eq "y") {
        $destOptions = Join-Path $minecraftPath "options.txt"
        $destDir = Split-Path $destOptions
        if (!(Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir | Out-Null }
        Copy-Item $srcOptions $destOptions -Force
        Write-Host "        > Keybinds overwritten." -ForegroundColor DarkGray
    } else {
        Write-Host "        > Keybinds skipped." -ForegroundColor DarkGray
    }
    Write-Host ""
}

# 6. Mods Folder Handling
Write-Host "  [4/5] Refreshing mods folder..." -ForegroundColor Cyan
$srcMods = Join-Path $tempExtract "minecraft/mods"
if (!(Test-Path $srcMods)) { $srcMods = Join-Path $tempExtract "mods" }
if (Test-Path $srcMods) {
    if (Test-Path $modsPath) { Remove-Item "$modsPath\*" -Recurse -Force -ErrorAction SilentlyContinue }
    else { New-Item -ItemType Directory -Path $modsPath | Out-Null }
    Copy-Item "$srcMods\*" $modsPath -Recurse -Force
}

# 7. Wipe AutoModPack folder
Write-Host "  [5/5] Wiping automodpack cache..." -ForegroundColor Cyan
if (Test-Path $autoModPath) {
    Remove-Item "$autoModPath\*" -Recurse -Force -ErrorAction SilentlyContinue
}

# 8. Cleanup
Remove-Item $tempZip -ErrorAction SilentlyContinue
Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "  ==============================================" -ForegroundColor DarkGray
Write-Host "  [+] Update complete! Launching Prism..." -ForegroundColor Green
Write-Host "  ==============================================" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Server Fingerprint Key:" -ForegroundColor Gray
Write-Host "  856ceffce2e6e12be4cafc7cfd64a4b96a0522a07fcd1d004e910cfcd4e6eae5" -ForegroundColor Red
Write-Host "  Copy the key above before joining the server." -ForegroundColor Gray
Write-Host ""

# 9. Launch Prism Launcher
Start-Process "cmd.exe" -ArgumentList "/c start `"`" `"$prismExePath`"" -WindowStyle Hidden
Pause