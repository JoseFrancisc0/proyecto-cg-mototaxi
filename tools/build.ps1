param([int]$Jobs = 8)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
Push-Location $taskRoot
try {
    $portable = Join-Path $taskRoot '.tools/llvm-mingw-20261006-ucrt-x86_64'
    $pythonModules = Join-Path $taskRoot '.tools/python'
    $arguments = @('-m', 'SCons', 'platform=windows', 'target=template_debug', 'arch=x86_64', 'api_version=4.7', 'build_profile=build_profile.json', 'lto=none', "-j$Jobs")
    if (Test-Path -LiteralPath $pythonModules) {
        $env:PYTHONPATH = "$pythonModules;$env:PYTHONPATH"
    }
    if (Test-Path -LiteralPath "$portable/bin/clang++.exe") {
        $env:PATH = "$portable/bin;$env:PATH"
        $arguments += @('use_mingw=yes', 'use_llvm=yes', 'use_static_cpp=yes', "mingw_prefix=$portable")
    }
    Write-Host 'Compilando la extension de terreno. Cierra antes el visor y el editor de este proyecto.'
    & python @arguments
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo compilar. Revisa el primer error mostrado arriba.' }
    Write-Host 'Compilacion terminada: project/bin/windows/CrazyTerrain.windows.template_debug.x86_64.dll'
} finally {
    Pop-Location
}
