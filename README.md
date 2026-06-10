# Bitácora de Lab 🧪

App web para que un grupo de laboratorio de química registre las **partes** de cada práctica y suba **evidencia fotográfica** desde el celular (Android/iPhone). Pensada para que el administrador recopile todo y arme el reporte fácilmente.

🔗 **En vivo:** https://lab4cambiosmateria.vercel.app

---

## Qué hace
- **Cuentas reales** (registro / inicio de sesión) con Supabase Auth. Roles: **admin** y **equipo**.
- El admin crea **laboratorios** divididos en **partes** y **asigna** compañeros a cada parte (incluido él).
- Cada persona asignada marca su parte como **hecha** y sube una **foto** (cámara en vivo dentro de la app o desde la galería).
- **Instrucciones detalladas** por parte: pasos textuales del PDF + preguntas de análisis.
- **Importar desde PDF**: subes la guía y **Claude (Sonnet 4.6)** separa las partes y extrae los pasos automáticamente.
- El admin **ve y descarga** la evidencia (por foto, por parte, o todo el lab directo a una carpeta).
- **Tiempo real**: los cambios aparecen solos en todos los dispositivos.

## Stack
- **Frontend:** un solo `index.html` en JavaScript vanilla (sin build), tema "coffee-shop" en OKLCH.
- **Backend:** [Supabase](https://supabase.com) — Auth, Postgres con Row Level Security (RLS), Storage.
- **IA:** función serverless de Vercel `api/parse-lab.js` que llama a la API de Anthropic (Claude Sonnet 4.6) para leer PDFs.
- **Hosting:** Vercel.

## Estructura
```
index.html                  # toda la app (UI + lógica)
api/parse-lab.js            # función serverless: PDF -> partes (Claude)
SQL/                        # scripts de Supabase (correr en el SQL Editor)
  supabase-setup.sql            # esquema + seguridad (RLS) + bucket de fotos
  supabase-fix-policies.sql     # reparar políticas RLS
  supabase-realtime.sql         # activar tiempo real
  supabase-add-steps.sql        # columna de instrucciones detalladas
SETUP.md                    # guía paso a paso de Supabase
.vercelignore               # publica solo index.html + api/
```

## Configuración
1. Crear un proyecto en **Supabase** y correr los scripts de `SQL/` en el SQL Editor (ver `SETUP.md`).
2. Poner `SUPABASE_URL` y la `anon key` en `index.html`.
3. En **Vercel**, definir la variable de entorno **secreta** `ANTHROPIC_API_KEY` (para la función de PDF).
4. Desplegar: `vercel deploy --prod`.

## Seguridad
- La **anon key** de Supabase es pública por diseño (la seguridad real la dan las políticas RLS) — está bien que viva en `index.html`.
- La **`ANTHROPIC_API_KEY`** es **secreta**: vive solo como variable de entorno en Vercel, **nunca** en el código ni en este repositorio.

---
Hecho por **Abrahan Aparicio** · Universidad Latina de Panamá
