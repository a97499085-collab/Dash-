#------------------------------------------------------------------------------
#  run_tests.ps1 -- the test suite of the DCM.
#
#  Every program under examples/ is run twice: once on the virtual machine
#  and once as a native executable that was built by the DCM.  The two
#  outputs have to be the same.
#
#  Use:   powershell -ExecutionPolicy Bypass -File tests\run_tests.ps1
#------------------------------------------------------------------------------

#  The exit codes are looked at by hand, so a message on the error output
#  must not stop the script.
$ErrorActionPreference = 'Continue'

$Root    = Split-Path -Parent $PSScriptRoot
$Dcm     = Join-Path $Root 'bin\dcm_main.exe'
$Work    = Join-Path $Root 'tests\_work'
$Examples = Join-Path $Root 'examples'
$Gnat    = 'C:\msys64\ucrt64\bin\gnatmake.exe'

$Passed = 0
$Failed = 0

function Report ($Name, $Ok, $Detail) {
    if ($Ok) {
        Write-Host ("  [ ok ] " + $Name) -ForegroundColor Green
        $script:Passed++
    } else {
        Write-Host ("  [FAIL] " + $Name) -ForegroundColor Red
        if ($Detail) { Write-Host ("         " + $Detail) -ForegroundColor Red }
        $script:Failed++
    }
}

Write-Host ''
Write-Host 'DCM test suite' -ForegroundColor Cyan
Write-Host '---------------'

if (-not (Test-Path $Dcm)) {
    Write-Host 'The DCM is not built yet: run gprbuild -P dash.gpr first.' -ForegroundColor Red
    exit 1
}

if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory -Path $Work | Out-Null

#------------------------------------------------------------------------------
#  The programs that must run.
#------------------------------------------------------------------------------

$Programs = @('hello', 'fib', 'strings', 'control')

foreach ($Name in $Programs) {
    $Source = Join-Path $Examples ($Name + '.dh')

    #  The analyser must accept the program.
    $Check = & $Dcm check $Source 2>&1
    Report ("$Name : analysed") ($LASTEXITCODE -eq 0) ($Check -join "`n")

    #  The virtual machine must run it.
    $Vm = & $Dcm run $Source 2>&1
    $Vm_Ok = $LASTEXITCODE -eq 0
    Report ("$Name : run on the virtual machine") $Vm_Ok ($Vm -join "`n")

    #  The DCM must build a native executable.
    $Exe = Join-Path $Work ($Name + '.exe')
    $Build = & $Dcm build $Source -o $Exe 2>&1
    $Build_Ok = ($LASTEXITCODE -eq 0) -and (Test-Path $Exe)
    Report ("$Name : built to a native executable") $Build_Ok ($Build -join "`n")

    if ($Build_Ok) {
        $Native = & $Exe 2>&1
        $Native_Ok = $LASTEXITCODE -eq 0
        Report ("$Name : the native executable runs") $Native_Ok ($Native -join "`n")

        $Same = (($Vm -join "`n") -eq ($Native -join "`n"))
        Report ("$Name : the two agree") $Same "vm:`n$($Vm -join "`n")`nnative:`n$($Native -join "`n")"
    }
}

#------------------------------------------------------------------------------
#  The diagnostics must work.
#------------------------------------------------------------------------------

$Bad = @(
    @{ Name = 'unknown variable'; Source = "fs main is`nbegin`n    x = 1`nend`n" },
    @{ Name = 'missing main';     Source = "fs other is`nbegin`nend`n" },
    @{ Name = 'type mismatch';    Source = "fs main is`n    let a : int = ""text""`nbegin`nend`n" },
    @{ Name = 'wrong arity';      Source = "fs f ( a : int ) : int is`nbegin`n    ret ( a )`nend`nfs main is`nbegin`n    println ( f ( 1 2 ) )`nend`n" }
)

foreach ($Case in $Bad) {
    $File = Join-Path $Work 'bad.dh'
    Set-Content -Path $File -Value $Case.Source -Encoding ascii
    $Out = & $Dcm check $File 2>&1
    $Ok = $LASTEXITCODE -ne 0
    Report ("error reported: " + $Case.Name) $Ok ($Out -join "`n")
}

#------------------------------------------------------------------------------
#  Reading from the standard input.
#------------------------------------------------------------------------------

$Input_File = Join-Path $Work 'input.txt'
Set-Content -Path $Input_File -Value "Merhaba`n42" -Encoding ascii

$Vm_In = cmd /c "bin\dcm_main.exe run examples\echo.dh < `"$Input_File`" 2>&1"
$Vm_In_Ok = $LASTEXITCODE -eq 0
Report ("echo : reads from the standard input") $Vm_In_Ok ($Vm_In -join "`n")

$Echo_Exe = Join-Path $Work 'echo.exe'
$Build_In = & $Dcm build (Join-Path $Examples 'echo.dh') -o $Echo_Exe 2>&1
if ($Build_In -and $LASTEXITCODE -eq 0) {
    $Native_In = cmd /c "`"$Echo_Exe`" < `"$Input_File`" 2>&1"
    $Native_In_Ok = $LASTEXITCODE -eq 0
    Report ("echo : the native executable reads the input") $Native_In_Ok ($Native_In -join "`n")
    Report ("echo : the two agree") (($Vm_In -join "`n") -eq ($Native_In -join "`n")) `
        "vm:`n$($Vm_In -join "`n")`nnative:`n$($Native_In -join "`n")"
} else {
    Report ("echo : built to a native executable") $False ($Build_In -join "`n")
}

Write-Host ''
Write-Host ("passed: $Passed   failed: $Failed") -ForegroundColor Cyan

if ($Failed -gt 0) { exit 1 }
exit 0
