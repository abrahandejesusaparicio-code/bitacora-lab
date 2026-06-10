# Bitácora de Lab 🧪

**Bitácora de Lab** es una aplicación web colaborativa para grupos de laboratorio de química. Un grupo registra en tiempo real las **partes** de cada práctica, sube **evidencia fotográfica** desde el celular, se organiza en **equipos** y reparte las **secciones** del laboratorio — todo en un solo lugar, sincronizado entre todos los dispositivos.

Está pensada para una clase real: el administrador (profesor o líder) arma la práctica y recopila la evidencia, mientras cada equipo trabaja su parte y documenta lo que hizo.

🔗 **En vivo:** https://lab4cambiosmateria.vercel.app

---

## Qué es

Una bitácora de laboratorio multi-dispositivo con cuentas reales y dos roles —**admin** y **equipo**— donde todo lo que pasa (una parte marcada como hecha, una foto subida, un equipo formado, una sección intercambiada) aparece al instante en las pantallas de los demás.

## Lo que hace

**Bitácora**
- Cuentas reales con registro e inicio de sesión; roles **admin** y **equipo**.
- El admin crea **laboratorios** divididos en **partes** y asigna compañeros a cada una.
- Cada persona marca su parte como **hecha** y sube una **foto** de evidencia (cámara en vivo dentro de la app o desde la galería).
- **Instrucciones detalladas** por parte: pasos textuales y preguntas de análisis, con seguimiento de progreso.
- **Importar desde PDF**: se sube la guía de la práctica y la IA separa las partes y extrae los pasos automáticamente.
- El admin **ve y descarga** toda la evidencia (por foto, por parte o el laboratorio completo).

**Equipos**
- Un **repartidor de equipos** estilo "lootbox": el admin elige a los presentes, agita una **canasta animada** y se forman las parejas (un trío si son impares).
- Cada equipo recibe el nombre de un **elemento de la tabla periódica** (Equipo Cobre, Oro, Plata…).
- Quien no quedó donde quería puede **solicitar unirse** a otro equipo; el admin aprueba y aparece una celebración con confeti.

**Secciones**
- Un **repartidor de secciones** con un **volcán animado** (burbujea, sube la presión y hace erupción) que asigna los equipos a las partes del laboratorio.
- Al terminar, las secciones se revelan como burbujas y la pantalla hace **zoom a la sección de tu equipo**.
- Los equipos pueden **intercambiar secciones por mutuo acuerdo**: uno propone el cambio y el otro lo acepta, sin pasar por el admin. El admin también puede reasignar manualmente.

**Detalles de la experiencia**
- **Tiempo real** en toda la app (indicador "EN VIVO").
- Fondo animado de **elementos químicos** que rebotan, se fusionan en compuestos (H₂O, NaCl, CO₂…) y se pueden **arrastrar** con mouse o dedo.
- Animaciones de carga (matraz Erlenmeyer), transición de entrada, celebraciones con confeti de átomos y una onda de color al tocar la pantalla.

## Con qué está hecho

- **Frontend:** un solo `index.html` en JavaScript vanilla, sin build, con un tema cálido en OKLCH y animaciones en CSS + Canvas.
- **Backend:** [Supabase](https://supabase.com) — autenticación, base de datos Postgres con Row Level Security, almacenamiento de fotos y Realtime.
- **IA:** una función serverless en Vercel que usa la API de Anthropic (**Claude**) para leer los PDF de las guías.
- **Hosting:** Vercel, con despliegue automático desde GitHub.

---
Hecho por **Abrahan Aparicio** · Universidad Latina de Panamá
