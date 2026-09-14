# Downloads the Qwen3-0.6B Q4_0 GGUF used by the on-device SLM into
# mobile/assets/models/Qwen3-0.6B-Q4_0.gguf.
#
# The file is ~364 MB and is NOT committed to git (see .gitignore). Without it
# the Insights tab reports a clear "asset missing" error instead of failing
# silently.
#
# Q4_0 is a legacy (non-K) quant: it dequantizes with simpler SIMD than the
# K-quants, so token decode is faster on a CPU-only phone.
#
# Usage:
#   pwsh mobile/tool/download_qwen3_gguf.ps1
#   pwsh mobile/tool/download_qwen3_gguf.ps1 -Url <custom-gguf-url>
#
# Non-Windows / manual alternative:
#   curl -L -o mobile/assets/models/Qwen3-0.6B-Q4_0.gguf <gguf-url>
#
# Verify the download against the publisher's checksum or size before use.

param(
  [string]$Url = 'https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_0.gguf',
  [string]$OutFile = ''
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutFile)) {
  $OutFile = Join-Path $repoRoot 'assets\models\Qwen3-0.6B-Q4_0.gguf'
}

$outDir = Split-Path -Parent $OutFile
if (-not (Test-Path $outDir)) {
  New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

if ((Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 100MB)) {
  Write-Host "Already present: $OutFile ($([Math]::Round((Get-Item $OutFile).Length / 1MB)) MB)"
  exit 0
}

Write-Host "Downloading $Url"
Write-Host "  -> $OutFile"
Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing

$size = (Get-Item $OutFile).Length
if ($size -lt 100MB) {
  Remove-Item $OutFile -Force
  throw "Downloaded file is only $([Math]::Round($size / 1MB)) MB — expected ~364 MB. Check the URL and retry."
}

# A valid GGUF starts with the ASCII magic "GGUF". Catch HTML error pages saved
# as .gguf before they reach a build. Read only the header bytes — the file is
# hundreds of MB and does not need to be loaded to check its first four.
$stream = [System.IO.File]::OpenRead($OutFile)
try {
  $bytes = New-Object byte[] 4
  [void]$stream.Read($bytes, 0, 4)
} finally {
  $stream.Dispose()
}
$magic = [System.Text.Encoding]::ASCII.GetString($bytes)
if ($magic -ne 'GGUF') {
  Remove-Item $OutFile -Force
  throw "File does not start with the GGUF magic bytes (got '$magic'). The URL likely returned an error page."
}

Write-Host "OK: $OutFile ($([Math]::Round($size / 1MB)) MB, GGUF magic verified)"
