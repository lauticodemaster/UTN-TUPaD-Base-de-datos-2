# Simulacro de restauración sobre foodstore_restore_test (NUNCA sobre foodstore).
# Sin contraseñas: usar $env:PGPASSWORD o pgpass.conf.
# Uso: .\restore_test.ps1 [-Dump ruta\al\archivo.dump]   (por defecto, el último de ..\Parte2_Respaldo\backups)
param([string]$Dump)
$ErrorActionPreference = 'Stop'

$PgHost = if ($env:PGHOST) { $env:PGHOST } else { 'localhost' }
$Port   = if ($env:PGPORT) { $env:PGPORT } else { '5432' }
$User   = if ($env:PGUSER) { $env:PGUSER } else { 'postgres' }
$TestDb = 'foodstore_restore_test'

if (-not $Dump) {
    $last = Get-ChildItem (Join-Path $PSScriptRoot '..\Parte2_Respaldo\backups\foodstore_*.dump') |
            Sort-Object LastWriteTime | Select-Object -Last 1
    if (-not $last) { throw 'No hay respaldos .dump disponibles.' }
    $Dump = $last.FullName
}
if (-not (Test-Path $Dump)) { throw "No existe el respaldo: $Dump" }

$LogDir = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Log = Join-Path $LogDir ("restore_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
function Write-Log($m) { $l = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m; Write-Host $l; Add-Content $Log $l }

$ageMin = [math]::Round(((Get-Date) - (Get-Item $Dump).LastWriteTime).TotalMinutes, 1)
Write-Log "Respaldo: $Dump (antiguedad = $ageMin min -> RPO observado)"

$sw = [System.Diagnostics.Stopwatch]::StartNew()   # cronometro: justo antes de crear la base

# Recrear solo la base descartable (guarda: nombre fijo, jamas foodstore)
& dropdb -h $PgHost -p $Port -U $User -w --if-exists $TestDb
& createdb -h $PgHost -p $Port -U $User -w $TestDb
if ($LASTEXITCODE -ne 0) { throw 'createdb fallo' }

& pg_restore -h $PgHost -p $Port -U $User -w -d $TestDb --no-owner --no-privileges --exit-on-error $Dump 2>> $Log
if ($LASTEXITCODE -ne 0) { throw "pg_restore fallo (codigo $LASTEXITCODE)" }

$out = & psql -h $PgHost -p $Port -U $User -w -d $TestDb -v ON_ERROR_STOP=1 -f (Join-Path $PSScriptRoot 'validacion.sql')
if ($LASTEXITCODE -ne 0) { throw 'validacion.sql fallo' }
$out | Tee-Object -FilePath $Log -Append

$sw.Stop()
Write-Log ("RTO observado = {0:N1} s" -f $sw.Elapsed.TotalSeconds)
Write-Log 'Verificar: productos_invalidos = 0, detalles_invalidos = 0 y conteos iguales a los previos al respaldo.'
