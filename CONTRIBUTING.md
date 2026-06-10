# Contribuir a Bitácora de Lab

¡Gracias por querer aportar! Esta guía cubre el flujo de trabajo. Para entender
**cómo está armado el sistema**, lee primero **[ARCHITECTURE.md](ARCHITECTURE.md)**.

## Antes de empezar
1. Lee `README.md` (qué es) y `ARCHITECTURE.md` (cómo funciona).
2. Levanta el entorno local siguiendo `ARCHITECTURE.md` §7 (proyecto de Supabase
   propio + scripts de `SQL/` + tus llaves).
3. Para ver las animaciones sin entrar a la app: `node tools/shoot.mjs`.

## Flujo de trabajo
1. Haz un **fork** (o una rama si tienes acceso). No trabajes directo sobre `main`.
2. Crea una rama descriptiva: `feat/intercambio-multiple`, `fix/blur-revelado`, etc.
3. Haz commits pequeños y claros. Un commit = un cambio entendible.
4. Abre un **Pull Request** hacia `main` describiendo **qué** cambia y **por qué**.
   Incluye capturas o GIFs si tocas la UI.
5. Cada push a `main` **se despliega solo** en Vercel, así que `main` debe quedar siempre sano.

## Estilo de código
- Frontend = un solo `index.html`, **JavaScript vanilla**, sin paso de build ni dependencias nuevas.
- Reutiliza los helpers existentes: `el()`, `ICON`, `toast()`, `openModal()`, `confettiBurst()`, etc.
- Colores y curvas vía **variables CSS en OKLCH** (`--primary`, `--accent`, `--ease-spring`…),
  no valores sueltos.
- **UI siempre en español.**
- Respeta `prefers-reduced-motion` en animaciones nuevas.
- Mantén el código parecido al de alrededor (nombres, comentarios, idioma de los comentarios).

## Cambios que tocan datos
Una feature con datos normalmente necesita, en este orden:
1. **Un script en `SQL/`** con la(s) tabla(s) + RLS (idempotente: `if not exists`, `drop policy if exists`).
2. **Loaders + render + realtime** en `index.html`.
3. A veces un **broadcast** para el "momento" compartido (revelados, celebraciones).

Si tu PR requiere correr SQL nuevo, **dilo claramente en la descripción** e incluye el archivo.

## Secretos
- La **anon key** de Supabase es pública por diseño y puede vivir en `index.html`.
- La **`ANTHROPIC_API_KEY`** es secreta: solo como variable de entorno en Vercel. **Nunca** la subas.
- No incluyas PDFs, fotos reales de clase ni datos personales en los commits
  (ya están ignorados en `.gitignore`).

## Reportar problemas / ideas
Abre un **issue** describiendo el comportamiento esperado vs. el real, con pasos para
reproducir y, si aplica, capturas. Las ideas de mejora también son bienvenidas.
