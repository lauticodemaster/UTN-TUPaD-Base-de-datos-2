# =============================================================================
# TP Unidad 6 · Programación del plan de mantenimiento (Programador de tareas de Windows)
#   - Respaldo diario 02:00           -> Parte2_Respaldo\backup_foodstore.ps1
#   - Mantenimiento semanal dom 03:00 -> Parte3_Monitoreo_Mantenimiento\maintenance.sql
#   - Prueba de restauración mensual (día 1, 04:00) -> Parte4_Simulacro\restore_test.ps1
#   - Retención: se borran los .dump con más de 14 días (dentro de la tarea diaria)
#
# Credenciales: la tarea corre con la cuenta del servicio y lee
# %APPDATA%\postgresql\pgpass.conf de esa cuenta. Nunca hay contraseñas en este archivo.
#
# Uso (PowerShell como administrador):
#   .\programar_mantenimiento.ps1 -WhatIf     # muestra qué registraría, sin registrar nada
#   .\programar_mantenimiento.ps1             # registra las tres tareas
#   .\programar_mantenimiento.ps1 -Quitar     # elimina las tres tareas
# Equivalente Linux (crontab del usuario postgres):
#   0 2 * * *  /ruta/Parte2_Respaldo/backup_foodstore.sh && find /ruta/Parte2_Respaldo/backups -name '*.dump' -mtime +14 -delete
#   0 3 * * 0  psql -d foodstore -f /ruta/Parte3_Monitoreo_Mantenimiento/maintenance.sql >> /ruta/logs/maintenance.log 2>&1
#   0 4 1 * *  /ruta/Parte4_Simulacro/restore_test.sh
# =============================================================================
[CmdletBinding(SupportsShouldProcess)]
param([switch]$Quitar)

$Raiz  = Split-Path $PSScriptRoot -Parent
$PgBin = 'C:\Program Files\PostgreSQL\17\bin'
$Ps    = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

$tareas = @(
    @{ Nombre  = 'FoodStore-Respaldo-Diario'
       Accion  = "-NoProfile -ExecutionPolicy Bypass -Command `"`$env:PATH='$PgBin;'+`$env:PATH; & '$Raiz\Parte2_Respaldo\backup_foodstore.ps1'; if (`$LASTEXITCODE -eq 0) { Get-ChildItem '$Raiz\Parte2_Respaldo\backups\*.dump' | Where-Object LastWriteTime -lt (Get-Date).AddDays(-14) | Remove-Item }`""
       Disparo = New-ScheduledTaskTrigger -Daily -At '02:00' },
    @{ Nombre  = 'FoodStore-Mantenimiento-Semanal'
       Accion  = "-NoProfile -ExecutionPolicy Bypass -Command `"& '$PgBin\psql.exe' -w -h localhost -U postgres -d foodstore -f '$Raiz\Parte3_Monitoreo_Mantenimiento\maintenance.sql' *>> '$Raiz\Parte3_Monitoreo_Mantenimiento\maintenance_programado.log'`""
       Disparo = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '03:00' },
    @{ Nombre  = 'FoodStore-Prueba-Restauracion-Mensual'
       Accion  = "-NoProfile -ExecutionPolicy Bypass -Command `"`$env:PATH='$PgBin;'+`$env:PATH; & '$Raiz\Parte4_Simulacro\restore_test.ps1'`""
       # el Programador no tiene disparo "mensual" nativo en este cmdlet: diario + filtro día 1
       Disparo = New-ScheduledTaskTrigger -Daily -At '04:00' }
)
$tareas[2].Accion = $tareas[2].Accion -replace '^(-NoProfile -ExecutionPolicy Bypass -Command ")', '$1if ((Get-Date).Day -ne 1) { exit 0 }; '

foreach ($t in $tareas) {
    if ($Quitar) {
        if ($PSCmdlet.ShouldProcess($t.Nombre, 'Unregister-ScheduledTask')) {
            Unregister-ScheduledTask -TaskName $t.Nombre -Confirm:$false -ErrorAction SilentlyContinue
        }
        continue
    }
    $accion = New-ScheduledTaskAction -Execute $Ps -Argument $t.Accion
    if ($PSCmdlet.ShouldProcess($t.Nombre, "Register-ScheduledTask ($($t.Accion))")) {
        Register-ScheduledTask -TaskName $t.Nombre -Action $accion -Trigger $t.Disparo `
            -Description 'TPI Food Store - plan de mantenimiento U6' -Force | Out-Null
        Write-Host "Registrada: $($t.Nombre)"
    }
}
