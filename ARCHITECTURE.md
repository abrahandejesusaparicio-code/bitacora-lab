# Arquitectura — Bitácora de Lab

Guía técnica completa del sistema. Si vienes a contribuir, este documento explica
cómo está armado todo (frontend, base de datos, función serverless, despliegue) y
dónde tocar para agregar o cambiar cosas.

> El **README.md** describe *qué es* el proyecto. Este archivo describe *cómo funciona*.
> Las guías de contribución (flujo de ramas/PRs) están en **CONTRIBUTING.md**.

---

## 1. Visión general

```
                 ┌─────────────────────────────────────────────┐
   Navegador     │  index.html  (HTML + CSS + JS vanilla)       │
  (PC / móvil)   │  · estado en memoria + render manual         │
                 │  · cliente de Supabase (esm.sh)              │
                 └───────┬───────────────────────┬─────────────┘
                         │                        │
            Supabase JS / Realtime            fetch /api/parse-lab
                         │                        │
        ┌────────────────▼─────────┐   ┌──────────▼───────────────┐
        │   Supabase                │   │  Vercel Function          │
        │   · Auth                  │   │  api/parse-lab.js         │
        │   · Postgres + RLS        │   │  · llama a Anthropic      │
        │   · Storage (fotos)       │   │    (Claude Sonnet 4.6)    │
        │   · Realtime              │   │  · PDF → partes (JSON)    │
        └───────────────────────────┘   └───────────────────────────┘
```

- **No hay paso de build.** El frontend es un único `index.html` servido tal cual.
- **No hay backend propio:** la lógica de datos/seguridad vive en Supabase (Postgres + RLS).
- **La única función de servidor** es `api/parse-lab.js`, que existe solo para no exponer
  la API key de Anthropic en el navegador.
- **Hosting:** Vercel, con **despliegue automático** al hacer push a `main` en GitHub.

---

## 2. Stack

| Capa            | Tecnología                                                        |
|-----------------|-------------------------------------------------------------------|
| Frontend        | HTML + CSS (OKLCH) + JavaScript vanilla (módulo ES), sin framework |
| Cliente datos   | `@supabase/supabase-js@2` importado desde `https://esm.sh`         |
| Auth/DB/Storage | Supabase (Postgres 15, Row Level Security, Storage, Realtime)      |
| IA (PDF)        | Anthropic API — Claude **Sonnet 4.6** (`claude-sonnet-4-6`)        |
| Serverless      | Vercel Functions (Node.js)                                         |
| Hosting / CI    | Vercel (auto-deploy desde `main`)                                  |

---

## 3. Estructura del repositorio

```
.
├── index.html              # TODA la app (UI + estilos + lógica). ~2.6k líneas.
├── api/
│   └── parse-lab.js        # Vercel Function: PDF (base64) → partes estructuradas (Claude)
├── SQL/                    # Scripts para el SQL Editor de Supabase (ver §6)
│   ├── supabase-setup.sql        # 1) esquema base + RLS + bucket de fotos
│   ├── supabase-realtime.sql     # 2) publica tablas en Realtime
│   ├── supabase-add-steps.sql    # 3) columna 'steps' (instrucciones detalladas)
│   ├── supabase-photo-delete.sql # 4) política para borrar fotos
│   ├── supabase-fix-policies.sql # (reparación de RLS, si hace falta)
│   ├── teams_schema.sql          # 5) Equipos (teams, team_members, join_requests)
│   └── sections_schema.sql       # 6) Secciones (part_assignments, swap_requests, triggers)
├── tools/                  # Utilidades de desarrollo (NO se despliegan)
│   ├── gallery-body.html   # galería que reusa el CSS real para ver las animaciones
│   └── shoot.mjs           # Playwright: captura la galería en tools/shots/
├── README.md
├── ARCHITECTURE.md         # este archivo
├── CONTRIBUTING.md
├── .vercelignore           # solo publica index.html + api/
└── .gitignore              # ignora secretos, PDFs, imágenes, node_modules…
```

`.vercelignore` hace que Vercel publique **solo** `index.html` y `api/`. Todo lo demás
(SQL, tools, docs) vive en el repo pero no llega a producción.

---

## 4. Frontend (`index.html`)

Todo está en un archivo dentro de un `<script type="module">`. No hay framework: el
estado vive en memoria y la UI se redibuja a mano.

### 4.1 Patrón general
- **`state`** — objeto global con toda la información de sesión/vista
  (`view`, `tab`, `session`, `profile`, `labs`, `parts`, `teams`, `sectionParts`, …).
- **`render()`** — limpia `#root` y reconstruye la vista actual según `state`.
  Se llama después de cada cambio relevante de estado.
- **`el(tag, attrs, children)`** — helper que crea nodos del DOM (atributos, eventos
  con `onX`, estilos como objeto, `html`/`text`). Es el "JSX" casero del proyecto.
- **`ICON` / `svg()`** — íconos SVG inline.
- **`toast()`**, **`openModal()`**, **`showLoading()`** — utilidades de UI compartidas.

### 4.2 Vistas y navegación
- `state.view`: `loading` → `auth` → `app`.
- Dentro de `app`, un **tab bar** con `state.tab`:
  - `labs` → **Bitácora de Lab** (`renderLabList` / `renderLabDetail`)
  - `teams` → **Equipos** (`renderTeams`)
  - `sections` → **Secciones** (`renderSections`)

### 4.3 Carga de datos (lecturas a Supabase)
`loadProfile`, `loadLabs`, `loadParts`, `loadProfiles`, `loadLabData`,
`loadTeams`, `loadSections`. Se invocan al iniciar sesión (`applySession`) y tras
cada cambio en tiempo real.

### 4.4 Tiempo real
Un solo canal `labtodo-rt` (`subscribeRealtime`):
- **`postgres_changes`** en todas las tablas → `onRealtimeChange` (recarga con rebote).
- **`broadcast`** para momentos compartidos:
  `lab_done`, `teams_generated`, `member_joined`, `sections_assigned`, `section_swapped`.

### 4.5 Animaciones (todas ligeras: CSS + Canvas, sin librerías)
| Función                       | Qué es                                                |
|-------------------------------|-------------------------------------------------------|
| `flaskLoader()`               | Matraz Erlenmeyer llenándose (cargador por defecto)   |
| `playIntro()`                 | Escena de laboratorio tras el login                   |
| `playBasketReveal()`          | Canasta "lootbox" → reparte equipos → zoom a tu equipo|
| `playVolcanoReveal()`         | Volcán → reparte secciones → zoom a tu sección        |
| `showLoading()` / `startClipWriting()` | Tablilla + pluma redactando → "¡Laboratorio listo!" |
| `celebrate()` / `celebrateJoin()` / `celebrateSwap()` | Tarjetas de celebración con confeti |
| `confettiBurst()`             | Confeti de átomos en Canvas                           |
| `initBackgroundFX()`          | Fondo de elementos que rebotan, se fusionan y se **arrastran** |
| `initClickRipple()`           | Onda de color al hacer clic/tocar                     |

Para **ver/iterar** las animaciones sin entrar a la app, corre la galería
(ver §8) — reusa el CSS real, así que lo que ves es lo que sale en producción.

### 4.6 Cámara y fotos
- Cámara dentro de la app vía `getUserMedia` (con autoenfoque/toca-para-enfocar),
  más fallback a la cámara nativa (`<input capture>`). Las fotos se suben a Supabase Storage.

### 4.7 Configuración del cliente
Al inicio del `<script>` están **`SUPABASE_URL`** y **`SUPABASE_ANON_KEY`**.
La anon key es pública por diseño (la seguridad real la da RLS). Para apuntar a tu
propio proyecto de Supabase, cambia esos dos valores.

---

## 5. Backend serverless (`api/parse-lab.js`)

Única función de servidor. Recibe `{ pdf_base64, filename }`, sanea el PDF, y llama a
la API de Anthropic con **tool use** (esquema `registrar_laboratorio`) para obtener
`{ lab_name, parts[] }` ya estructurado. Devuelve ese JSON al frontend.

- Modelo: `claude-sonnet-4-6` (constante `MODEL`).
- Secreto: **`ANTHROPIC_API_KEY`** vía `process.env` (variable de entorno de Vercel,
  **nunca** en el código ni en el repo).
- `maxDuration: 60` s.

---

## 6. Base de datos (Supabase / Postgres + RLS)

### 6.1 Orden para montar el esquema
En **Supabase → SQL Editor**, pega y corre cada archivo en este orden (todos son
idempotentes / seguros de re-ejecutar):

1. `SQL/supabase-setup.sql` — esquema base, RLS y bucket de fotos.
2. `SQL/supabase-realtime.sql` — publica las tablas base en Realtime.
3. `SQL/supabase-add-steps.sql` — agrega la columna `steps` a `parts`.
4. `SQL/supabase-photo-delete.sql` — política para borrar fotos.
5. `SQL/teams_schema.sql` — Equipos (crea `is_admin()`, `teams`, `team_members`, `join_requests`).
6. `SQL/sections_schema.sql` — Secciones (requiere el paso 5).

`SQL/supabase-fix-policies.sql` es opcional: re-crea las políticas RLS si algo se desconfigura.

### 6.2 Modelo de datos

| Tabla              | Para qué                              | Notas de seguridad / relación                         |
|--------------------|---------------------------------------|-------------------------------------------------------|
| `profiles`         | 1 fila por usuario (`role` member/admin) | PK = `auth.users.id`                                |
| `labs`             | Laboratorios                          | admin escribe; todos leen                             |
| `parts`            | Partes de un lab (`steps` jsonb)      | `lab_id → labs`                                       |
| `assignments`      | Personas responsables por parte       | `(part_id, user_id)`                                  |
| `photos`           | Evidencia fotográfica (Storage path)  | `part_id`, `uploaded_by`                              |
| `teams`            | Equipos (nombre = elemento químico)   | admin escribe; todos leen                             |
| `team_members`     | Integrante → equipo (1 equipo/persona)| PK = `user_id`                                        |
| `join_requests`    | Solicitud de unión (la aprueba admin) | el usuario crea la suya; admin aprueba                |
| `part_assignments` | Parte → equipo (asignación de sección)| PK = `part_id`                                        |
| `swap_requests`    | Intercambio de secciones entre equipos| se opera vía funciones SECURITY DEFINER               |

### 6.3 Funciones y triggers clave (en los scripts de teams/sections)
- **`is_admin()`** — `SECURITY DEFINER`; evita recursión de RLS al leer `profiles`.
- **`sync_part_team()`** (trigger en `part_assignments`) — cuando una parte recibe equipo,
  reescribe `assignments` con los integrantes de ese equipo (sincroniza "quién es responsable").
- **`sync_team_member()`** / **`rebuild_team_parts()`** — si cambian los integrantes de un
  equipo, refrescan los `assignments` de las partes de ese equipo.
- **`request_section_swap` / `accept_section_swap` / `decline_section_swap`** — los intercambios
  de sección los hacen los equipos (sin admin); estas funciones validan permisos y hacen el swap.

### 6.4 RLS en pocas palabras
- Todos los autenticados **leen** casi todo.
- **Escriben** según rol: el admin gestiona labs/partes/equipos/asignaciones; cada usuario
  gestiona lo suyo (su solicitud de unión, sus fotos). Los intercambios pasan por funciones.

### 6.5 Storage
- Bucket de fotos (creado en `supabase-setup.sql`). Las rutas se guardan en `photos.storage_path`.

---

## 7. Entorno local y despliegue

### 7.1 Requisitos
- Cuenta de **Supabase** (gratis) y, para el import de PDF, una **API key de Anthropic**.
- **Node.js** y la **CLI de Vercel** (`npm i -g vercel`) si quieres correr la función en local.

### 7.2 Puesta en marcha (primera vez)
1. Crea un proyecto en Supabase y corre los scripts de `SQL/` en orden (§6.1).
2. En `index.html`, pon tu `SUPABASE_URL` y `SUPABASE_ANON_KEY`.
3. Crea un usuario, y en la tabla `profiles` ponle `role = 'admin'` para poder crear labs.
4. Para el import de PDF: define `ANTHROPIC_API_KEY` como variable de entorno
   (en Vercel, o en un `.env` local para `vercel dev`).

### 7.3 Correr en local
- **App + función:** `vercel dev` (sirve `index.html` y `/api/parse-lab`).
- **Solo la UI** (sin import de PDF): abre `index.html` con cualquier server estático;
  el resto (auth, datos, fotos, tiempo real) funciona contra tu Supabase.

### 7.4 Despliegue
- Push a `main` → **Vercel despliega solo** (CI conectado). También `vercel --prod`.
- En Vercel define la variable secreta **`ANTHROPIC_API_KEY`**.

---

## 8. Galería de animaciones (tooling de desarrollo)

Para revisar los diseños sin entrar a la app:

```bash
node tools/shoot.mjs      # genera PNGs en tools/shots/
```

`tools/shoot.mjs` arma una página (`tools/gallery-body.html`) inyectando el `<style>`
real de `index.html` y la captura con Playwright (usa el Chromium/Edge ya instalado).
Útil para ver cada animación en un cuadro fijo tras cambiar el CSS.

---

## 9. Convenciones

- **UI en español.** Todo lo visible al usuario va en español.
- **Tema en OKLCH** con variables CSS (`--primary`, `--surface`, `--accent`, …) y
  curvas de animación (`--ease-spring`, `--ease-out`). Reúsalas en vez de colores sueltos.
- **Sin dependencias de build.** Mantén el frontend como un solo `index.html` editable a mano.
- **Animaciones ligeras** (CSS + Canvas), respetando `prefers-reduced-motion`.
- **Secretos fuera del repo.** La anon key de Supabase puede vivir en `index.html`
  (es pública); la `ANTHROPIC_API_KEY` jamás.
- **Cada feature nueva con datos** suele necesitar: tabla(s) + RLS (un script en `SQL/`),
  loaders + render + realtime en `index.html`, y a veces un broadcast para el "momento" compartido.

---

¿Dudas? Abre un issue. Para el flujo de ramas y PRs, ve a **CONTRIBUTING.md**.
