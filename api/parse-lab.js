// Función serverless de Vercel: recibe un PDF (base64) y usa Claude (Sonnet 4.6)
// para extraer el nombre del laboratorio y dividirlo en partes estructuradas.
// La API key vive en process.env.ANTHROPIC_API_KEY (variable cifrada en Vercel).

// Guías largas (pasos copiados textualmente) pueden tardar > 60 s; damos margen.
export const config = { maxDuration: 300 };

const MODEL = "claude-sonnet-4-6";

export default async function handler(req, res) {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Método no permitido" });
    return;
  }
  // las API keys son ASCII imprimible; quitamos BOM/espacios/saltos invisibles
  const key = (process.env.ANTHROPIC_API_KEY || "").replace(/[^\x21-\x7e]/g, "");
  if (!key) {
    res.status(500).json({ error: "Falta ANTHROPIC_API_KEY en el servidor" });
    return;
  }

  try {
    const body = typeof req.body === "string" ? JSON.parse(req.body) : (req.body || {});
    const pdf_base64 = body.pdf_base64;
    if (!pdf_base64) { res.status(400).json({ error: "No se recibió el PDF" }); return; }

    // Saneamos el PDF: recortamos cualquier byte basura ANTES de "%PDF-"
    // (algunos PDFs traen un \r o BOM al inicio y Anthropic los rechaza).
    let pdfBuf;
    try { pdfBuf = Buffer.from(pdf_base64, "base64"); } catch (_) { res.status(400).json({ error: "PDF ilegible" }); return; }
    const at = pdfBuf.indexOf("%PDF-");
    if (at < 0) { res.status(400).json({ error: "El archivo no parece un PDF válido." }); return; }
    if (at > 0) pdfBuf = pdfBuf.subarray(at);
    const cleanB64 = pdfBuf.toString("base64");

    const tool = {
      name: "registrar_laboratorio",
      description: "Registra el laboratorio y la lista de sus partes extraídas del PDF.",
      input_schema: {
        type: "object",
        properties: {
          lab_name: { type: "string", description: "Nombre o título del laboratorio." },
          parts: {
            type: "array",
            description: "Las partes/secciones del laboratorio, en orden.",
            items: {
              type: "object",
              properties: {
                title: { type: "string", description: "Título corto de la parte (ej. 'Parte I — Cambios con sulfato de cobre', 'Fase A — Clasificación inicial'). Conserva la MISMA palabra y el MISMO identificador que use la guía: si dice 'FASE A' usa 'Fase A', si dice 'I. PARTE' usa 'Parte I', si dice 'Experimento' usa 'Experimento'." },
                description: { type: "string", description: "RESUMEN breve (1-3 frases) de qué se hace en esta parte. Aquí sí puedes resumir." },
                equipment: { type: "array", items: { type: "string" }, description: "Equipo/material que se usa, si se menciona." },
                steps: {
                  type: "array",
                  description: "Los pasos detallados/numerados de esta parte, en orden.",
                  items: {
                    type: "object",
                    properties: {
                      instruction: { type: "string", description: "La instrucción del paso copiada TEXTUALMENTE del PDF, palabra por palabra, SIN resumir ni reescribir (incluye cantidades, materiales y detalles tal cual)." },
                      questions: { type: "array", items: { type: "string" }, description: "Las preguntas de análisis de ese paso, copiadas textuales (ej. '¿Qué ocurrió?', '¿un cambio físico o un cambio químico?', '¿Cómo lo sabes?')." },
                    },
                    required: ["instruction"],
                  },
                },
              },
              required: ["title"],
            },
          },
        },
        required: ["lab_name", "parts"],
      },
    };

    const payload = {
      model: MODEL,
      max_tokens: 16000,
      tools: [tool],
      tool_choice: { type: "tool", name: "registrar_laboratorio" },
      messages: [{
        role: "user",
        content: [
          { type: "document", source: { type: "base64", media_type: "application/pdf", data: cleanB64 } },
          { type: "text", text:
            "Este es el PDF de una guía de laboratorio de química (probablemente en español). " +
            "Extrae el nombre del laboratorio y divídelo en sus PARTES o secciones del procedimiento. " +
            "Las guías usan varios formatos de encabezado: 'I. PARTE', 'II.PARTE' (número romano antes de la palabra), " +
            "'FASE A', 'FASE B' (letras), 'Parte 1', 'Fase 1', o un experimento por sección. Todos son secciones. " +
            "Conserva en el TÍTULO la misma palabra que use la guía (Parte / Fase / Experimento) y su número o letra. " +
            "NO conviertas en sección el cuestionario final ('Análisis de Resultados', 'Cuestionario'): sus preguntas " +
            "van como 'questions' del último paso al que correspondan, o simplemente omítelas si son generales. Para cada parte da:\n" +
            "1) un TÍTULO corto;\n" +
            "2) una DESCRIPCIÓN breve (1-3 frases) — aquí sí puedes resumir;\n" +
            "3) el EQUIPO/material que se usa, si aparece;\n" +
            "4) los STEPS (pasos): cada paso numerado del procedimiento con su instrucción copiada " +
            "TEXTUALMENTE del PDF, palabra por palabra, SIN resumir ni parafrasear (conserva cantidades, " +
            "volúmenes, materiales y todos los detalles tal cual), y sus preguntas de análisis también textuales. " +
            "Es MUY importante que el campo 'instruction' de cada paso sea el texto exacto de la guía, no un resumen. " +
            "Responde SOLO usando la herramienta registrar_laboratorio." },
        ],
      }],
    };

    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": key,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify(payload),
    });

    if (!r.ok) {
      const t = await r.text();
      res.status(502).json({ error: "Error de Anthropic: " + t.slice(0, 600) });
      return;
    }
    const data = await r.json();
    const toolUse = (data.content || []).find(c => c.type === "tool_use");
    if (!toolUse || !toolUse.input) {
      res.status(502).json({ error: "Claude no devolvió la estructura esperada." });
      return;
    }
    res.status(200).json(toolUse.input);
  } catch (e) {
    res.status(500).json({ error: String((e && e.message) || e) });
  }
}
