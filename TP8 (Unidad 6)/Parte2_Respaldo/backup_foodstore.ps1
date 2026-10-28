# Respaldo custom de foodstore. La contraseña NO se guarda aquí:
# usar $env:PGPASSWORD en la sesión o %APPDATA%\postgresql\pgpass.conf.
$ErrorActionPreference = 'Stop'

$PgHost = if ($env:PGHOST) { $env:PGHOST } else { 'localhost' }
$Port   = if ($env:PGPORT) { $env:PGPORT } else { '5432' }
$User   = if ($env:PGUSER) { $env:PGUSER } else { 'postgres' }
$Db     = 'foodstore'

$BackupDir = Join-Path $PSScriptRoot 'backups'
$LogDir    = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force -Path $BackupDir, $LogDir | Out-Null

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$File  = Join-Path $BackupDir "${Db}_${Stamp}.dump"
$Log   = Join-Path $LogDir "backup_${Stamp}.log"

function Write-Log($msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Write-Host $line
    Add-Content -Path $Log -Value $line
}

Write-Log "Inicio respaldo de $Db -> $File"
& pg_dump -h $PgHost -p $Port -U $User -d $Db -Fc -w -f $File 2>> $Log
if ($LASTEXITCODE -ne 0) {
    Write-Log "ERROR: pg_dump fallo (codigo $LASTEXITCODE)"
    Remove-Item -Force -ErrorAction SilentlyContinue $File
    exit $LASTEXITCODE
}
& pg_restore --list $File *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Log "ERROR: el archivo generado no es legible por pg_restore"
    Remove-Item -Force -ErrorAction SilentlyContinue $File
    exit 2
}
Write-Log ("OK tamano={0} bytes archivo={1}" -f (Get-Item $File).Length, $File)
