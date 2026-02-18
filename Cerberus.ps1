# --- Admin Elevation Logic ---
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output "Depth needs to be run as Administrator. Attempting to relaunch."
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
$prismPath = "$env:APPDATA\PrismLauncher"
$instancePath = "$prismPath\instances\Euphoria Pack +"
$minecraftPath = "$instancePath\minecraft"
$modsPath = "$minecraftPath\mods"
$autoModPath = "$minecraftPath\automodpack"

$dropboxUrl = "https://www.dropbox.com/scl/fo/fixz2jzj2h9cb7tqzxb6s/ALMbFcvwLNg1XUWlySVR9Ro?rlkey=28l2d8a7i0dveyyapuoq8sw3e&st=4o8g0fvz&dl=1"
$tempZip = "$env:TEMP\EuphoriaDownload.zip"
$tempExtract = "$env:TEMP\EuphoriaExtract"

# --- Execution ---
Clear-Host
$choice = Read-Host "Would you like to update/install the modpack? (yes/no)"
if ($choice -ne "yes") { exit }

# 1. Prism Launcher Check & Auto-Install
if (!(Test-Path $prismPath)) {
    Write-Host "Prism Launcher not found. Attempting to install via Winget..." -ForegroundColor Yellow
    winget install PrismLauncher.PrismLauncher --accept-source-agreements --accept-package-agreements -e
    if ($LASTEXITCODE -ne 0 -and !(Test-Path $prismPath)) {
        Write-Host "`nWinget download failed! Install manually: https://prismlauncher.org/" -ForegroundColor Red
        Pause; exit
    }
    Start-Sleep -Seconds 5
}

# 2. Folder Preparation
if (!(Test-Path $instancePath)) { New-Item -ItemType Directory -Path $instancePath | Out-Null }
if (!(Test-Path $minecraftPath)) { New-Item -ItemType Directory -Path $minecraftPath | Out-Null }

# 3. Download (Silent & Fast)
Write-Host "Downloading modpack contents..." -ForegroundColor Cyan
if (Test-Path $tempZip) { Remove-Item $tempZip -Force }
$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -Uri $dropboxUrl -OutFile $tempZip
$ProgressPreference = 'Continue'

# 4. Extraction
if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host "Extracting files..." -ForegroundColor Cyan
Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force

# 5. File Handling & Dynamic Path Patching
$filesToOverwrite = @("instance.cfg", "mmc-pack.json", "minecraft/servers.dat")

foreach ($relPath in $filesToOverwrite) {
    $srcFile = Join-Path $tempExtract $relPath
    $destFile = Join-Path $instancePath $relPath
    
    if (Test-Path $srcFile) {
        if ($relPath -eq "instance.cfg") {
            Write-Host "Patching instance.cfg for current user..." -ForegroundColor Gray
            # Read the file, replace the hardcoded "Euphoria" path with the current user's roaming path
            $content = Get-Content $srcFile -Raw
            # We use -replace with a regex that looks for the JavaPath and swaps the user segment
            $pattern = "JavaPath=C:/Users/[^/]+/AppData/Roaming/PrismLauncher"
            $replacement = "JavaPath=$($env:APPDATA -replace '\\', '/')"
            $content = $content -replace $pattern, $replacement
            Set-Content -Path $destFile -Value $content
        } else {
            Write-Host "Updating $($relPath)..." -ForegroundColor Gray
            $destDir = Split-Path $destFile
            if (!(Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir | Out-Null }
            Copy-Item $srcFile $destFile -Force
        }
    }
}

# 6. Mods Folder Handling
$srcMods = Join-Path $tempExtract "minecraft/mods"
if (!(Test-Path $srcMods)) { $srcMods = Join-Path $tempExtract "mods" }
if (Test-Path $srcMods) {
    Write-Host "Refreshing mods folder..." -ForegroundColor Cyan
    if (Test-Path $modsPath) { Remove-Item "$modsPath\*" -Recurse -Force -ErrorAction SilentlyContinue }
    else { New-Item -ItemType Directory -Path $modsPath | Out-Null }
    Copy-Item "$srcMods\*" $modsPath -Recurse -Force
}

# 7. Wipe AutoModPack folder
if (Test-Path $autoModPath) {
    Write-Host "Wiping automodpack folder..." -ForegroundColor Gray
    Remove-Item "$autoModPath\*" -Recurse -Force -ErrorAction SilentlyContinue
}

# 8. Cleanup
Remove-Item $tempZip -ErrorAction SilentlyContinue
Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`nUpdate Complete!" -ForegroundColor Green
Write-Host "Relaunch Prism Launcher if it was already open." -ForegroundColor Yellow
Write-Host -NoNewline "The fingerprint key is: "
Write-Host "856ceffce2e6e12be4cafc7cfd64a4b96a0522a07fcd1d004e910cfcd4e6eae5" -ForegroundColor Red
Write-Host "Please copy the key above to join the server."
Pause