# Continue (not Stop): in PS5.1, Stop turns any native-exe stderr line into a throw, which makes
# plink's "Keyboard-interactive authentication prompts from server" chatter abort the whole script.
$ErrorActionPreference = "Continue"
$Here = $PSScriptRoot

$envFile = Join-Path $Here ".env"
if (-not (Test-Path $envFile)) { Write-Host "X .env not found (copy .env.example)" -ForegroundColor Red; exit 1 }

$cfg = @{}
Get-Content $envFile | ForEach-Object {
  if ($_ -match '^\s*([A-Z_]+)\s*=\s*(.*?)\s*$') { $cfg[$matches[1]] = $matches[2].Trim('"').Trim("'") }
}
$pw   = $cfg.ROOT_PASSWORD
$port = if ($cfg.PORT) { $cfg.PORT } else { "2222" }
if (-not $pw) { Write-Host "X ROOT_PASSWORD missing in .env" -ForegroundColor Red; exit 1 }

$target = "root@127.0.0.1"
$remote = "/var/mobile/auto-tweak"

# Resolve URLs in ipa.txt to actual .ipa files in _ipas/ (cached by filename).
$ipaFile = Join-Path $Here "ipa.txt"
$ipaDir  = Join-Path $Here "_ipas"
if (-not (Test-Path $ipaDir)) { New-Item -ItemType Directory -Path $ipaDir | Out-Null }
if (Test-Path $ipaFile) {
  foreach ($line in Get-Content $ipaFile) {
    $url = ($line -replace '#.*$', '').Trim()
    if (-not $url) { continue }

    if ($url -match '^https://github\.com/([^/]+)/([^/?#]+)') {
      $owner = $matches[1]; $repo = $matches[2] -replace '\.git$', ''
      try {
        $rel = Invoke-RestMethod "https://api.github.com/repos/$owner/$repo/releases/latest" -UserAgent "auto-tweak"
      } catch { Write-Host "[host] X $owner/$repo : $($_.Exception.Message)" -ForegroundColor Red; continue }
      $asset = $rel.assets | Where-Object { $_.name -match '\.(ipa|tipa)$' } | Select-Object -First 1
      if (-not $asset) { Write-Host "[host] X $owner/$repo : no .ipa/.tipa in latest release" -ForegroundColor Red; continue }
      $dst = Join-Path $ipaDir $asset.name
      if (Test-Path $dst) { Write-Host "[host] cached $($asset.name)"; continue }
      Write-Host "[host] downloading $($asset.name)"
      Invoke-WebRequest $asset.browser_download_url -OutFile $dst -UseBasicParsing
    }
    elseif ($url -match '\.(ipa|tipa)(\?.*)?$') {
      $name = [IO.Path]::GetFileName(($url -split '\?')[0])
      $dst = Join-Path $ipaDir $name
      if (Test-Path $dst) { Write-Host "[host] cached $name"; continue }
      Write-Host "[host] downloading $name"
      Invoke-WebRequest $url -OutFile $dst -UseBasicParsing
    }
    else {
      Write-Host "[host] X unsupported ipa.txt entry: $url" -ForegroundColor Red
    }
  }
}

# Start iproxy via .NET (Start-Process can throw "operation canceled" in some headless contexts).
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = (Get-Command iproxy).Source
$psi.Arguments = "$port 22"
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$iproxy = [System.Diagnostics.Process]::Start($psi)
Start-Sleep 2

try {
  # Probe the device's host key by letting `-batch` refuse, then parsing the SHA256 fingerprint
  # out of plink's stderr. iOS dropbear regenerates this key, so doing it every run is correct.
  $probe = New-Object System.Diagnostics.ProcessStartInfo
  $probe.FileName = (Get-Command plink).Source
  $probe.Arguments = "-batch -P $port -pw `"$pw`" $target exit"
  $probe.UseShellExecute = $false
  $probe.RedirectStandardError = $true
  $probe.RedirectStandardOutput = $true
  $probe.CreateNoWindow = $true
  $p = [System.Diagnostics.Process]::Start($probe)
  if (-not $p.WaitForExit(15000)) { $p.Kill(); throw "host key probe timed out (.env / USB / OpenSSH on device)" }
  $stderr = $p.StandardError.ReadToEnd()
  if ($stderr -notmatch '(SHA256:[A-Za-z0-9+/=]+)') {
    throw "could not read host key (.env / USB / OpenSSH on device)`n$stderr"
  }
  $fp = $matches[1]

  $opts = @("-batch", "-hostkey", $fp, "-P", $port, "-pw", $pw)

  # plink chats "Keyboard-interactive authentication prompts" on stderr even with -batch + -pw;
  # we don't need device-side stderr, so drop it.
  & plink @opts $target "mkdir -p $remote" 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "ssh connect failed" }

  # First clear the remote IPA dir so stale files don't get installed if ipa.txt changed.
  & plink @opts $target "rm -rf $remote/_ipas" 2>$null | Out-Null

  & pscp @opts -r "$Here\repo.txt" "$Here\tweak.txt" "$Here\additional.txt" "$Here\device.sh" "$Here\_ipas" "${target}:$remote/" 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "upload failed" }

  & plink @opts $target "chmod +x $remote/device.sh && $remote/device.sh" 2>$null
  if ($LASTEXITCODE -ne 0) { throw "install failed" }
}
catch {
  Write-Host "X $_" -ForegroundColor Red
  exit 1
}
finally {
  if ($iproxy -and -not $iproxy.HasExited) { Stop-Process -Id $iproxy.Id -Force }
}
