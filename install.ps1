# xagt installer for Windows (amd64, arm64).
#
#   irm https://raw.githubusercontent.com/38159/xagt/main/install.ps1 | iex
#
# Installs the prebuilt binary of the latest tag (or $env:XAGT_VERSION) into
# $env:XAGT_DIR\bin (default %USERPROFILE%\.xagt\bin), seeds a config
# template, and adds the bin directory and XAGT_CONFIG to your user
# environment. When xagt is already installed it asks update / remove / quit.
$ErrorActionPreference = 'Stop'

$repo = '38159/xagt'
$dir = if ($env:XAGT_DIR) { $env:XAGT_DIR } else { Join-Path $env:USERPROFILE '.xagt' }
$arch = if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64') { 'arm64' } else { 'amd64' }

# --- version: $env:XAGT_VERSION or the latest v* tag ------------------------
$version = $env:XAGT_VERSION
if (-not $version) {
    $tags = Invoke-RestMethod "https://api.github.com/repos/$repo/tags"
    $version = ($tags | Where-Object { $_.name -match '^v\d+\.\d+\.\d+$' } |
        Sort-Object { [version]($_.name.Substring(1)) } | Select-Object -Last 1).name
}
if (-not $version) { throw 'xagt-install: could not determine the latest version (set $env:XAGT_VERSION to pin one)' }

$binDir = Join-Path $dir 'bin'
$exe = Join-Path $binDir 'xagt.exe'

# --- already installed? offer update or remove ------------------------------
$installed = $null
if (Test-Path $exe) { $installed = $exe }
else {
    $cmd = Get-Command xagt.exe -ErrorAction SilentlyContinue
    if ($cmd) { $installed = $cmd.Source }
}
if ($installed) {
    $current = ((& $installed --version) -replace '^xagt\s*', '')
    if (-not $current) { $current = 'unknown' }
    Write-Host "xagt-install: xagt $current is already installed at $installed (latest: $version)"
    $choice = Read-Host 'xagt-install: [u]pdate, [r]emove the installed version, or [q]uit? [u/r/q]'
    switch ($choice.ToLower()) {
        'r' {
            Remove-Item $installed -Force
            Write-Host "xagt-install: removed $installed (config left untouched)"
            return
        }
        'q' { Write-Host 'xagt-install: nothing done'; return }
        default {
            # An update goes to wherever the binary already lives.
            $exe = $installed
            $binDir = Split-Path $installed
        }
    }
}

# --- download and place the binary ------------------------------------------
Write-Host "xagt-install: installing xagt $version for windows-$arch to $exe"
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
$zip = Join-Path $env:TEMP "xagt-$version.zip"
$extract = Join-Path $env:TEMP "xagt-extract"
Invoke-WebRequest "https://raw.githubusercontent.com/$repo/$version/dist/xagt-windows-$arch.zip" -OutFile $zip
Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive $zip -DestinationPath $extract
# A running/locked exe cannot be overwritten, but it can be renamed aside.
Remove-Item "$exe.old" -Force -ErrorAction SilentlyContinue
if (Test-Path $exe) { Move-Item $exe "$exe.old" -Force }
Move-Item (Join-Path $extract 'xagt.exe') $exe -Force
Remove-Item $zip -Force -ErrorAction SilentlyContinue
Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$exe.old" -Force -ErrorAction SilentlyContinue

# --- config template (never overwrites an existing file) --------------------
$config = Join-Path $dir 'xagt.toml'
if (-not (Test-Path $config)) {
    Set-Content -Path $config -Encoding UTF8 -Value @'
# xagt config — one [[agent]] table per OpenAI-compatible endpoint.
# provider openai/qwen/qwen-cn fills in apiurl; anything else needs apiurl.
# priority: "primary" answers first; a "secondary" is only asked on failure.

# per-call timeout, seconds (XAGT_TIMEOUT_SEC overrides)
timeout = 300

[[agent]]
name     = "my-gpt"
provider = "openai"
apikey   = "sk-REPLACE-ME"
model    = "gpt-4.1"
priority = "primary"

# [[agent]]
# name     = "qwen"
# provider = "qwen"
# apikey   = "sk-REPLACE-ME"
# model    = "qwen3.7-plus"
# priority = "secondary"
'@
    Write-Host "xagt-install: seeded config template at $config - put your API keys there"
}

# --- user environment: PATH and XAGT_CONFIG ---------------------------------
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($userPath -split ';') -notcontains $binDir) {
    [Environment]::SetEnvironmentVariable('Path', "$binDir;$userPath", 'User')
    Write-Host "xagt-install: added $binDir to your user PATH"
}
if (-not [Environment]::GetEnvironmentVariable('XAGT_CONFIG', 'User')) {
    [Environment]::SetEnvironmentVariable('XAGT_CONFIG', $config, 'User')
    Write-Host "xagt-install: set XAGT_CONFIG=$config for your user"
}

Write-Host "xagt-install: installed: $(& $exe --version) at $exe"
Write-Host "xagt-install: open a new terminal, put your API key in $config, then:  xagt `"hello`""
Write-Host "xagt-install: later, 'xagt update' brings the installed binary to the latest release"
