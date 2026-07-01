// Función serverless de Vercel: recibe un PDF (base64) y usa Claude (Haiku 4.5)
// para extraer el nombre del laboratorio y dividirlo en partes estructuradas.
// La API key vive en process.env.ANTHROPIC_API_KEY (variable cifrada en Vercel).

// Guías largas (pasos copiados textualmente) pueden tardar > 60 s; damos margen.
export const config = { maxDuration: 300 };

const MODEL = "claude-haiku-4-5";

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
                  description: "Los pasos/prompts de esta parte, en orden: instrucciones del procedimiento, enunciados de hipótesis a completar, indicaciones de registro de datos, cálculos a realizar, etc.",
                  items: {
                    type: "object",
                    properties: {
                      instruction: { type: "string", description: "El texto del paso copiado TEXTUALMENTE del PDF, palabra por palabra, SIN resumir ni reescribir (incluye cantidades, materiales, enunciados de hipótesis y detalles tal cual)." },
                      questions: { type: "array", items: { type: "string" }, description: "Las preguntas de análisis de ese paso, copiadas textuales (ej. '¿Qué ocurrió?', '¿un cambio físico o un cambio químico?', '¿Cómo lo sabes?')." },
                      table: {
                        type: "object",
                        description: "Si este paso incluye un cuadro o tabla para LLENAR (ej. 'Cuadro 1', tabla de observaciones, tabla de datos), captura su ESTRUCTURA VACÍA aquí para que el alumno no tenga que volver al PDF. Omite este campo si el paso no tiene tabla.",
                        properties: {
                          title: { type: "string", description: "Título del cuadro si lo tiene (ej. 'Cuadro 1 — KClO₃')." },
                          columns: { type: "array", items: { type: "string" }, description: "Encabezados de columna en orden (ej. ['Dato','Valor'] o ['Observación','Descripción'])." },
                          rows: { type: "array", items: { type: "array", items: { type: "string" } }, description: "Filas de la tabla. Cada fila es un arreglo de celdas EN EL MISMO ORDEN que 'columns'. Rellena las celdas de etiqueta (ej. 'Masa KClO₃') y deja como cadena vacía '' las celdas que el alumno debe completar. NUNCA inventes valores numéricos." },
                        },
                        required: ["columns", "rows"],
                      },
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
            "Este es el PDF de una guía de laboratorio de ciencias (probablemente en español). " +
            "Extrae el nombre del laboratorio y divídelo en PARTES accionables, en orden.\n\n" +
            "Una PARTE es cualquier sección donde el estudiante debe HACER, REGISTRAR, CALCULAR o RESPONDER algo. Incluye, según aparezcan:\n" +
            "• las partes del procedimiento ('I. PARTE', 'II.PARTE', 'FASE A', 'Parte 1', 'Experimento', 'Procedimiento experimental');\n" +
            "• formulación de hipótesis;\n" +
            "• registro de datos / cuadros a llenar;\n" +
            "• análisis o interpretación de resultados (incluidos 'niveles');\n" +
            "• aplicación del conocimiento / cálculos;\n" +
            "• pensamiento crítico, desafíos o retos de investigación;\n" +
            "• conclusión y reflexión final.\n\n" +
            "NO crees partes para el material introductorio que no exige acción del estudiante: pregunta generadora, " +
            "contexto, objetivos de aprendizaje, competencias científicas ni las notas de seguridad. " +
            "Los MATERIALES y REACTIVOS van en el campo 'equipment' de la parte donde se usan, no como una parte aparte.\n\n" +
            "Las guías usan varios formatos de encabezado (número romano antes de la palabra, letras, etc.); todos son secciones. " +
            "Conserva en el TÍTULO la MISMA palabra e identificador que use la guía (si dice 'FASE A' usa 'Fase A', si dice 'I. PARTE' usa 'Parte I', si dice 'Experimento' usa 'Experimento').\n\n" +
            "Para cada parte da:\n" +
            "1) un TÍTULO corto;\n" +
            "2) una DESCRIPCIÓN breve (1-3 frases) — aquí sí puedes resumir;\n" +
            "3) el EQUIPO/material que se usa, si aparece;\n" +
            "4) los STEPS (pasos): cada instrucción del procedimiento, enunciado de hipótesis a completar o prompt de cálculo, " +
            "con el texto copiado TEXTUALMENTE del PDF (palabra por palabra, SIN resumir ni parafrasear: conserva cantidades, " +
            "volúmenes, materiales y todos los detalles). Las preguntas de análisis textuales van en 'questions' del paso al que correspondan. " +
            "Es MUY importante que 'instruction' sea el texto exacto de la guía, no un resumen.\n" +
            "5) las TABLAS: si una sección tiene un cuadro/tabla para llenar (ej. 'Cuadro 1', tabla de observaciones, registro de datos), " +
            "captura su ESTRUCTURA VACÍA en el campo 'table' del paso correspondiente ('columns' con los encabezados y 'rows' con cada fila, " +
            "rellenando las etiquetas y dejando '' en las celdas que el alumno debe completar). Así el alumno no tiene que volver al PDF. " +
            "Cuando un cuadro pertenezca a una parte del procedimiento (ej. el Cuadro de datos del KClO₃ pertenece a la parte donde se descompone el KClO₃), adjúntalo a esa parte.\n\n" +
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
