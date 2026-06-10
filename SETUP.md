# Configuración de Supabase — Bitácora de Lab

Esto se hace **una sola vez**. Toma ~10 minutos. Es gratis.

---

## Paso 1 — Crear la cuenta y el proyecto
1. Ve a **https://supabase.com** → **Start your project** → inicia sesión (puedes usar tu cuenta de GitHub o tu correo).
2. **New project**:
   - **Name:** `bitacora-lab` (o el que quieras)
   - **Database Password:** inventa una y **guárdala** (la pide solo si administras la base directamente; no va en la app).
   - **Region:** elige la más cercana (ej. *East US*).
3. Espera ~2 minutos a que el proyecto termine de crearse.

## Paso 2 — Crear las tablas y la seguridad
1. En el panel del proyecto, menú izquierdo → **SQL Editor** → **New query**.
2. Abre el archivo **`supabase-setup.sql`** (está en esta carpeta), **copia todo** y pégalo.
3. Presiona **Run** (abajo a la derecha). Debe decir *Success*. 
   - Esto crea las tablas (`profiles`, `labs`, `parts`, `assignments`, `photos`), las reglas de seguridad y el bucket de fotos `evidence`. No tienes que crear el bucket a mano.

## Paso 3 — Copiar las 2 llaves que necesito
1. Menú izquierdo → **Project Settings** (el engranaje) → **API**.
2. Copia estos dos valores:
   - **Project URL** → algo como `https://abcdxyz.supabase.co`
   - **Project API keys → `anon` `public`** → un texto largo que empieza con `eyJ...`
3. **Mándame esos dos valores.** 
   - ✅ La llave **anon public** es **segura de compartir**: está diseñada para vivir dentro de la página web. La seguridad real la dan las reglas que ya cargaste en el Paso 2.
   - ❌ NO me mandes la llave **`service_role`** (esa sí es secreta — no la usamos).

## Paso 4 — (Opcional) Quitar la confirmación por correo
Por defecto, Supabase pide confirmar el correo antes de poder entrar. Para que tus compañeros entren sin ese paso extra:
- **Authentication** → **Sign In / Providers** (o **Settings**) → **Email** → desactiva **"Confirm email"** → Save.
- Si prefieres mantenerlo, está bien; solo tendrán que abrir el correo de confirmación una vez.

## Paso 5 — (Después) Volverte administrador
La primera vez que entres a la app, **regístrate** con tu correo (el de siempre).
Luego, en **SQL Editor**, ejecuta esta línea una vez:

```sql
update public.profiles set role = 'admin'
where email = 'abrahandejesusaparicio@gmail.com';
```

Eso te convierte en admin (ver todo, crear labs, asignar gente, descargar fotos). Tus compañeros quedan como `member` automáticamente.

---

## ¿Qué sigue?
Cuando me mandes el **Project URL** y la **anon key** (Paso 3), yo:
1. Conecto la app a tu proyecto.
2. Reescribo el login para registro/inicio real.
3. Construimos por fases: labs → partes → asignaciones → subir fotos → panel admin con descarga.

Probamos cada fase contigo antes de seguir.

---

### Notas
- **Costo:** plan gratis = ~1 GB de fotos (≈150–300 fotos a resolución completa) + base de datos + usuarios ilimitados para tu grupo. El panel de admin tendrá un botón para **descargar las fotos de un lab y luego borrarlas**, liberando espacio para el siguiente.
- **Privacidad:** el bucket de fotos es **privado**; solo personas con sesión iniciada en tu app pueden ver las imágenes (mediante enlaces firmados temporales).
