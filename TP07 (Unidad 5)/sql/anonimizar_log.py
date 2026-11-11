"""TP Unidad 5 · Parte C.3 — anonimiza un fragmento de log de PostgreSQL.

Mismo criterio que usuario_anon: reemplazo determinista (el mismo valor real
siempre produce el mismo sintético), para que la IA pueda correlacionar eventos
sin ver datos identificables.
  - mails             -> cliente_<n>@anon.example
  - rutas del sistema -> <PGDATA>
  - literales de contraseña en llamadas a fn_autenticar -> '<CLAVE_REDACTADA>'
  - nombres/apellidos sintéticos (Usuario<n>/Apellido<n>) -> Nombre_<n>/Apellido_<n>
Los nombres de rol, tablas, horas, PID e IP NO se tocan: son la evidencia.

Uso: python -I anonimizar_log.py entrada.log > salida_anonimizada.txt
"""
import re
import sys

MAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
RUTA = re.compile(r"[A-Za-z]:[/\\][^\"\s]*?pgdata", re.IGNORECASE)
CLAVE = re.compile(r"(fn_autenticar\(\s*'[^']*'\s*,\s*)'[^']*'")
NOMBRE = re.compile(r"\b(Usuario|Apellido)(\d+)\b")

def main(path: str) -> None:
    mapa: dict[str, str] = {}

    def mail_sintetico(m: re.Match) -> str:
        real = m.group(0).lower()
        if real.endswith("@anon.example"):
            return real
        if real not in mapa:
            mapa[real] = f"cliente_{len(mapa) + 1}@anon.example"
        return mapa[real]

    with open(path, encoding="utf-8", errors="replace") as f:
        for linea in f:
            linea = RUTA.sub("<PGDATA>", linea)
            linea = CLAVE.sub(r"\1'<CLAVE_REDACTADA>'", linea)
            linea = MAIL.sub(mail_sintetico, linea)
            linea = NOMBRE.sub(lambda m: ("Nombre_" if m.group(1) == "Usuario" else "Apellido_") + m.group(2), linea)
            sys.stdout.write(linea)

if __name__ == "__main__":
    main(sys.argv[1])
