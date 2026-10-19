param([switch]$Tests, [switch]$Reference, [switch]$Benchmark, [switch]$FullMap, [switch]$PaperIterations, [switch]$Capture, [switch]$S11, [switch]$Base, [switch]$Quick)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$godotCommand = Get-Command godot -ErrorAction SilentlyContinue
$godotPath = if ($godotCommand) { $godotCommand.Source } else { 'D:/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' }
if (-not (Test-Path -LiteralPath $godotPath)) { throw 'No se encontro Godot 4.7. Agrega el ejecutable a PATH como godot.' }
Push-Location $taskRoot
try {
    New-Item -ItemType Directory -Force tmp | Out-Null
    if ($Tests) {
        $nativeCompiler = Join-Path $taskRoot '.tools/llvm-mingw-20261006-ucrt-x86_64/bin/clang++.exe'
        if (Test-Path -LiteralPath $nativeCompiler) {
            & $nativeCompiler -std=c++17 -static -Isrc tools/breach_native_test.cpp src/drainage.cpp -o tmp/breach_native_test.exe
            if ($LASTEXITCODE -ne 0) { throw 'No se pudo compilar la prueba de apertura de cauces.' }
            & "$taskRoot/tmp/breach_native_test.exe"
            if ($LASTEXITCODE -ne 0) { throw 'Fallo la prueba de depresion cerrada.' }
        }
        foreach ($test in @('smoke_test', 'regions_test', 'regional_relief_test', 'region_layout_test', 'roads_test', 'hierarchy_test', 'drainage_test', 'water_density_test', 'original_scene_test', 'workflow_test', 'textures_test')) {
            $testArguments = @('--headless', '--path', 'project', '--script', "res://tests/$test.gd", '--log-file', ('"{0}/tmp/{1}.log"' -f $taskRoot, $test))
            $testProcess = Start-Process -FilePath $godotPath -ArgumentList $testArguments -PassThru -Wait -WindowStyle Hidden
            Get-Content -LiteralPath "$taskRoot/tmp/$test.log" -Tail 2
            if ($testProcess.ExitCode -ne 0) { throw "Fallo la prueba $test" }
        }
    } elseif ($Benchmark) {
        $benchmarkArguments = @('--headless', '--path', 'project', '--script', 'res://tests/benchmark.gd', '--log-file', ('"{0}/tmp/benchmark.log"' -f $taskRoot), '--')
        if ($PaperIterations) { $benchmarkArguments += '--paper-iterations' }
        $benchmarkProcess = Start-Process -FilePath $godotPath -ArgumentList $benchmarkArguments -PassThru -Wait -WindowStyle Hidden
        Get-Content -LiteralPath "$taskRoot/tmp/benchmark.log" -Tail 2
        if ($benchmarkProcess.ExitCode -ne 0) { throw 'Fallo la medicion del mapa completo.' }
    } elseif ($Reference) {
        $referenceArguments = @('--path', 'project', '--rendering-method', 'mobile', '--script', 'res://tests/reference_compare.gd', '--log-file', ('"{0}/tmp/reference.log"' -f $taskRoot))
        $referenceProcess = Start-Process -FilePath $godotPath -ArgumentList $referenceArguments -PassThru -Wait -WindowStyle Hidden
        Get-Content -LiteralPath "$taskRoot/tmp/reference.log" -Tail 4
        if ($referenceProcess.ExitCode -ne 0) { throw 'Fallo la comparacion oficial.' }
    } else {
        $arguments = @('--path', 'project', '--log-file', "$taskRoot/tmp/viewer.log", '--')
        if ($FullMap) { $arguments += '--full-map' }
        if ($PaperIterations) { $arguments += '--paper-iterations' }
        if ($Capture) { $arguments += '--capture' }
        if ($S11) { $arguments += '--s11' }
        if ($Base) { $arguments += '--base' }
        if ($Quick) { $arguments += '--quick' }
        Start-Process -FilePath $godotPath -ArgumentList $arguments -Wait
    }
} finally { Pop-Location }
