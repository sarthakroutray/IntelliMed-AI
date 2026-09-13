# Builds the native llama.cpp shared libraries for Android and installs them
# into android/app/src/main/jniLibs/<abi>/.
#
# Why this exists: `llama_cpp_dart` is a plain Dart package (not a Flutter
# plugin) and ships no Android binaries, so the app must supply
# libmtmd.so + libllama.so + the libggml*.so set itself. QwenSlmRuntime reaches
# llama.cpp through libmtmd.so (llama_cpp_dart's default library name on
# Android), so that exact set must be present in the APK.
#
# The pinned commit MUST match the llama_cpp_dart version in pubspec.lock —
# the FFI bindings are generated from that revision's headers. Update both
# together.
#
# Usage:
#   pwsh mobile/tool/build_llama_android.ps1
#   pwsh mobile/tool/build_llama_android.ps1 -Abi x86_64     # emulator
#
# Requirements: Android SDK with an NDK (r27+) and CMake, plus git.

param(
  [ValidateSet('arm64-v8a', 'x86_64')]
  [string]$Abi = 'arm64-v8a',
  [string]$WorkDir = 'D:\llamabuild',
  [string]$LlamaCommit = '4ffc47cb2001e7d523f9ff525335bbe34b1a2858'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repoRoot = Split-Path -Parent $PSScriptRoot
$localProps = Join-Path $repoRoot 'android\local.properties'
if (-not (Test-Path $localProps)) { throw "Missing $localProps" }
$m = [regex]::Match((Get-Content $localProps -Raw), '(?im)^sdk\.dir=(.+?)\s*$')
if (-not $m.Success) { throw "No sdk.dir entry in $localProps" }
$sdkDir = $m.Groups[1].Value.Trim() -replace '\\\\', '\'
if (-not (Test-Path $sdkDir)) { throw "Android SDK not found at $sdkDir" }

# NDK sysroot/triple is not the same string as the ABI name.
$triple = switch ($Abi) {
  'arm64-v8a' { 'aarch64-linux-android' }
  'x86_64' { 'x86_64-linux-android' }
}
# Clang runtime directory name (used to locate libomp.so).
$clangArch = switch ($Abi) {
  'arm64-v8a' { 'aarch64' }
  'x86_64' { 'x86_64' }
}

$ndkDir = Get-ChildItem (Join-Path $sdkDir 'ndk') -Directory |
  Sort-Object { [version]($_.Name -replace '[^0-9.]', '') } -Descending |
  Select-Object -First 1
if (-not $ndkDir) { throw "No NDK found under $sdkDir\ndk — install one via sdkmanager." }
$cmakeDir = Get-ChildItem (Join-Path $sdkDir 'cmake') -Directory |
  Sort-Object Name -Descending | Select-Object -First 1
if (-not $cmakeDir) { throw "No CMake found under $sdkDir\cmake — install 'cmake;3.22.1'." }

$cmake = Join-Path $cmakeDir.FullName 'bin\cmake.exe'
$ninja = Join-Path $cmakeDir.FullName 'bin\ninja.exe'
$toolchain = Join-Path $ndkDir.FullName 'build\cmake\android.toolchain.cmake'
$llvmBin = Join-Path $ndkDir.FullName 'toolchains\llvm\prebuilt\windows-x86_64\bin'
$strip = Join-Path $llvmBin 'llvm-strip.exe'
$sysLib = Join-Path $ndkDir.FullName "toolchains\llvm\prebuilt\windows-x86_64\sysroot\usr\lib\$triple\libc++_shared.so"

Write-Host "NDK:   $($ndkDir.Name)"
Write-Host "CMake: $($cmakeDir.Name)"
Write-Host "ABI:   $Abi"

# Android platform level: API 26 matches the app's minSdk.
$apiLevel = 26

$src = Join-Path $WorkDir 'llama.cpp'
$build = Join-Path $WorkDir "build-$Abi"

if (-not (Test-Path (Join-Path $src '.git'))) {
  New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
  git init $src | Out-Null
  git -C $src remote add origin https://github.com/ggml-org/llama.cpp
}
if (-not (Test-Path (Join-Path $src (Join-Path 'tools' 'mtmd')))) {
  git -C $src fetch --depth 1 origin $LlamaCommit
  if ($LASTEXITCODE -ne 0) { throw "Failed to fetch llama.cpp $LlamaCommit" }
  git -C $src checkout FETCH_HEAD
}

# CPU-only (GGML_OPENCL=OFF): QwenSlmRuntime requests nGpuLayers=0 so the GPU
# backend would only add size and a device-driver dependency.
Write-Host "Configuring..."
& $cmake -G Ninja -S $src -B $build `
  -DCMAKE_MAKE_PROGRAM="$ninja" `
  -DCMAKE_TOOLCHAIN_FILE="$toolchain" `
  -DANDROID_ABI=$Abi `
  -DANDROID_PLATFORM="android-$apiLevel" `
  -DANDROID_STL=c++_shared `
  -DCMAKE_BUILD_TYPE=Release `
  -DBUILD_SHARED_LIBS=ON `
  -DLLAMA_BUILD_COMMON=ON `
  -DLLAMA_BUILD_TOOLS=ON `
  -DLLAMA_BUILD_TESTS=OFF `
  -DLLAMA_BUILD_EXAMPLES=OFF `
  -DLLAMA_BUILD_SERVER=OFF `
  -DLLAMA_CURL=OFF `
  -DLLAMA_OPENSSL=OFF `
  -DGGML_OPENCL=OFF `
  -DGGML_NATIVE=OFF | Out-Null
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed" }

# Build only the mtmd target: it pulls in llama + ggml without compiling every
# CLI tool.
Write-Host "Building mtmd (this takes a few minutes)..."
& $cmake --build $build --target mtmd
if ($LASTEXITCODE -ne 0) { throw "Build failed" }

$dst = Join-Path $repoRoot "android\app\src\main\jniLibs\$Abi"
New-Item -ItemType Directory -Path $dst -Force | Out-Null
foreach ($lib in 'libmtmd.so', 'libllama.so', 'libggml.so', 'libggml-cpu.so', 'libggml-base.so') {
  $out = Join-Path $dst $lib
  Copy-Item (Join-Path $build "bin\$lib") $out -Force
  & $strip --strip-unneeded $out
}
Copy-Item $sysLib (Join-Path $dst 'libc++_shared.so') -Force
& $strip --strip-unneeded (Join-Path $dst 'libc++_shared.so')

# libggml-cpu.so is linked against the OpenMP runtime, so libomp.so must ship
# too or dlopen fails with "library libomp.so not found". The NDK provides it
# as a Clang runtime (not under the sysroot).
$clangLib = Join-Path $ndkDir.FullName 'toolchains\llvm\prebuilt\windows-x86_64\lib\clang'
$omp = Get-ChildItem $clangLib -Recurse -Filter 'libomp.so' -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match "linux\\$clangArch\\libomp\.so$" } |
  Select-Object -First 1
if (-not $omp) { throw "libomp.so for $clangArch not found under $clangLib" }
Copy-Item $omp.FullName (Join-Path $dst 'libomp.so') -Force
& $strip --strip-unneeded (Join-Path $dst 'libomp.so')

$total = (Get-ChildItem $dst | Measure-Object Length -Sum).Sum
Write-Host ("Installed to {0} ({1} MB total)" -f $dst, [Math]::Round($total / 1MB, 2))
