# TP Unidad 4 — FNBC y Desnormalización Controlada en Food Store
## Parte 1 — `control_lote_almacen`

---

## a) Dependencias funcionales

A partir de la regla de negocio relevada con el área de logística:

- **R1** — "Para un lote y un depósito interviniente dados, el responsable de
  control queda unívocamente determinado":

  **{LoteID, DepositoID} → ResponsableControlID**

- **R2** — "Cada responsable de control pertenece a un único depósito: no
  controla lotes coordinados desde depósitos distintos":

  **ResponsableControlID → DepositoID**

---

## b) Clausuras y claves candidatas

Atributos del esquema: `{LoteID, DepositoID, ResponsableControlID}`

### Candidata 1 — clausura de {LoteID, DepositoID}

```
{LoteID, DepositoID}⁺
  aplico F1: {LoteID, DepositoID} → ResponsableControlID
{LoteID, DepositoID, ResponsableControlID}⁺  →  es TODO el esquema
```

`{LoteID, DepositoID}` determina todo el esquema.

**¿Es mínima?** `{LoteID}` solo no determina nada (ninguna FD lo tiene como
determinante único); `{DepositoID}` solo tampoco.
→ **Es clave candidata.**

### Candidata 2 — clausura de {LoteID, ResponsableControlID}

```
{LoteID, ResponsableControlID}⁺
  aplico F2: ResponsableControlID → DepositoID
{LoteID, ResponsableControlID, DepositoID}⁺  →  es TODO el esquema
```

`{LoteID, ResponsableControlID}` también determina todo el esquema.

**¿Es mínima?** `{LoteID}` solo no alcanza; `{ResponsableControlID}` solo da,
por F2, `{ResponsableControlID, DepositoID}` — le falta `LoteID`.
→ **Es clave candidata.**

### Conjunto completo de claves candidatas

```
{LoteID, DepositoID}
{LoteID, ResponsableControlID}
```

### Atributos primos vs. no primos

| Atributo | ¿Participa de alguna clave candidata? | Condición |
|---|---|---|
| LoteID | Sí (en las dos) | ✅ Primo |
| DepositoID | Sí (en la primera) | ✅ Primo |
| ResponsableControlID | Sí (en la segunda) | ✅ Primo |

**Los tres atributos son primos** — no hay ningún atributo no primo en este
esquema. Este dato es clave para el punto c): como `ResponsableControlID`
(el determinante de F2) no es superclave pero sí es primo, la 3FN lo deja
pasar por su cláusula de excepción, mientras que la BCNF no.
