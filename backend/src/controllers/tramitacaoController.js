const db = require("../db/db.js");

/* ------------------------------------------------------------------ */
/* Constantes                                                          */
/* ------------------------------------------------------------------ */

const PERFIS_TRAMITACAO = ["operador_setor", "gestor_setor", "admin_sistema"];
const OBSERVACAO_MAX = 255; // mesmo limite aplicado pela procedure tramitar_processo
const SQLSTATE_REGRA_NEGOCIO = "45000"; // SIGNAL SQLSTATE '45000' das procedures e gatilhos

/* ------------------------------------------------------------------ */
/* Helpers de validação (substituem, por enquanto, os middlewares)     */
/* ------------------------------------------------------------------ */

const criarErro = (statusCode, message) => {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
};

// Aceita 5 ou "5". Rejeita "", null, true, 1.5, -1, "abc", "5; DROP...".
const isIdValido = (valor) => {
  if (valor === null || valor === undefined || typeof valor === "boolean") return false;
  if (typeof valor !== "number" && typeof valor !== "string") return false;
  return /^\d+$/.test(String(valor).trim()) && Number(valor) > 0;
};

const toId = (valor) => Number(String(valor).trim());

const isObjetoSimples = (valor) =>
  valor !== null && typeof valor === "object" && !Array.isArray(valor);

const isVazio = (valor) => valor === undefined || valor === null || valor === "";

// Normaliza manter_visivel para 0 ou 1. Retorna null se o valor for inválido.
const normalizarFlag = (valor) => {
  if (isVazio(valor)) return 0;
  if (valor === 0 || valor === "0" || valor === false) return 0;
  if (valor === 1 || valor === "1" || valor === true) return 1;
  return null;
};

// Confere o formato YYYY-MM-DD e se a data existe de verdade (rejeita 2026-02-31).
const isDataISOValida = (valor) => {
  if (typeof valor !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(valor)) return false;
  const [ano, mes, dia] = valor.split("-").map(Number);
  const data = new Date(ano, mes - 1, dia);
  return data.getFullYear() === ano && data.getMonth() === mes - 1 && data.getDate() === dia;
};

const hojeISO = () => {
  const agora = new Date();
  const mes = String(agora.getMonth() + 1).padStart(2, "0");
  const dia = String(agora.getDate()).padStart(2, "0");
  return `${agora.getFullYear()}-${mes}-${dia}`;
};

// Erro de regra de negócio levantado pelo banco (SIGNAL SQLSTATE '45000').
const isErroRegraNegocio = (err) =>
  Boolean(err) && err.sqlState === SQLSTATE_REGRA_NEGOCIO && Boolean(err.sqlMessage);

/**
 * Valida e normaliza o req.body do envio de processo.
 * Retorna { erro } em caso de falha ou { dados } com os campos já tratados.
 */
const validarBodyEnvio = (body) => {
  if (!isObjetoSimples(body)) {
    return { erro: { status: 400, message: "Corpo da requisição inválido ou ausente." } };
  }

  const { id_processo, setor_destino_id, observacao, manter_visivel, prazo_retorno } = body;

  // Campos obrigatórios
  const faltando = [];
  if (isVazio(id_processo)) faltando.push("id_processo");
  if (isVazio(setor_destino_id)) faltando.push("setor_destino_id");
  if (faltando.length) {
    return {
      erro: { status: 400, message: `Campos obrigatórios ausentes: ${faltando.join(", ")}.` }
    };
  }

  // Tipos e formatos
  if (!isIdValido(id_processo)) {
    return { erro: { status: 400, message: "id_processo deve ser um inteiro positivo." } };
  }
  if (!isIdValido(setor_destino_id)) {
    return { erro: { status: 400, message: "setor_destino_id deve ser um inteiro positivo." } };
  }

  // Observação (opcional)
  let observacaoTratada = null;
  if (!isVazio(observacao)) {
    if (typeof observacao !== "string") {
      return { erro: { status: 400, message: "observacao deve ser um texto." } };
    }
    observacaoTratada = observacao.trim() || null;
    if (observacaoTratada && observacaoTratada.length > OBSERVACAO_MAX) {
      return {
        erro: {
          status: 400,
          message: `observacao deve ter no máximo ${OBSERVACAO_MAX} caracteres.`
        }
      };
    }
  }

  // manter_visivel (opcional, padrão 0)
  const manterVisivel = normalizarFlag(manter_visivel);
  if (manterVisivel === null) {
    return { erro: { status: 400, message: "manter_visivel deve ser 0 ou 1." } };
  }

  // prazo_retorno (opcional, YYYY-MM-DD)
  let prazoRetorno = null;
  if (!isVazio(prazo_retorno)) {
    if (!isDataISOValida(prazo_retorno)) {
      return {
        erro: {
          status: 400,
          message: "prazo_retorno deve ser uma data válida no formato YYYY-MM-DD."
        }
      };
    }
    if (prazo_retorno < hojeISO()) {
      return {
        erro: { status: 400, message: "prazo_retorno não pode ser anterior à data de hoje." }
      };
    }
    prazoRetorno = prazo_retorno;
  }

  return {
    dados: {
      idProcesso: toId(id_processo),
      setorDestinoId: toId(setor_destino_id),
      observacao: observacaoTratada,
      manterVisivel,
      prazoRetorno
    }
  };
};

/* ------------------------------------------------------------------ */
/* Controllers                                                         */
/* ------------------------------------------------------------------ */

const enviarProcesso = async (req, res) => {
  // 1) Usuário autenticado (vem do middleware de autenticação)
  const usuario = req.usuario;
  if (!usuario || !usuario.perfil || !usuario.id_usuario) {
    return res.status(401).json({ message: "Usuário não autenticado." });
  }

  // 2) Permissão por perfil (enquanto o rbacMiddleware não existe)
  if (!PERFIS_TRAMITACAO.includes(usuario.perfil)) {
    return res.status(403).json({ message: "Perfil sem permissão para tramitar processos." });
  }

  // 3) Validação do corpo
  const { erro, dados } = validarBodyEnvio(req.body);
  if (erro) {
    return res.status(erro.status).json({ message: erro.message });
  }

  // 4) Persistência. A procedure faz SELECT ... FOR UPDATE e várias escritas,
  // então roda dentro de uma transação para ser atômica.
  const conn = await db.getConnection();
  try {
    await conn.beginTransaction();

    await conn.query("CALL tramitar_processo(?, ?, ?, ?, ?, ?)", [
      dados.idProcesso,
      Number(usuario.id_usuario),
      dados.setorDestinoId,
      dados.observacao,
      dados.manterVisivel,
      dados.prazoRetorno
    ]);

    await conn.commit();

    return res.status(200).json({ message: "Processo tramitado com sucesso." });
  } catch (err) {
    await conn.rollback();

    // Regras do banco (RN17, processo sem documentos etc.): devolve a mensagem da procedure
    if (isErroRegraNegocio(err)) {
      return res.status(400).json({ message: err.sqlMessage });
    }

    console.error(err);
    return res.status(err.statusCode || 500).json({
      message: err.statusCode ? err.message : "Erro ao tramitar processo."
    });
  } finally {
    conn.release();
  }
};

const removerAcompanhamento = async (req, res) => {
  // 1) Usuário autenticado
  const usuario = req.usuario;
  if (!usuario || !usuario.perfil || !usuario.id_usuario) {
    return res.status(401).json({ message: "Usuário não autenticado." });
  }

  // 2) Permissão por perfil (enquanto o rbacMiddleware não existe)
  if (!PERFIS_TRAMITACAO.includes(usuario.perfil)) {
    return res.status(403).json({
      message: "Perfil sem permissão para remover acompanhamento de processos."
    });
  }

  // 3) Validação do parâmetro
  const { id_processo } = req.params || {};
  if (!isIdValido(id_processo)) {
    return res.status(400).json({ message: "id_processo deve ser um inteiro positivo." });
  }

  // 4) Persistência
  const conn = await db.getConnection();
  try {
    await conn.beginTransaction();

    await conn.query("CALL remover_visibilidade_processo(?, ?)", [
      toId(id_processo),
      Number(usuario.id_usuario)
    ]);

    await conn.commit();

    return res.status(200).json({
      message: "Processo removido da caixa de acompanhamento com sucesso."
    });
  } catch (err) {
    await conn.rollback();

    if (isErroRegraNegocio(err)) {
      return res.status(400).json({ message: err.sqlMessage });
    }

    console.error(err);
    return res.status(err.statusCode || 500).json({
      message: err.statusCode ? err.message : "Erro ao remover acompanhamento do processo."
    });
  } finally {
    conn.release();
  }
};

const historicoTramitacoes = async (req, res) => {
  try {
    const usuario = req.usuario;
    if (!usuario || !usuario.perfil) {
      return res.status(401).json({ message: "Usuário não autenticado." });
    }

    const { id_processo } = req.params || {};
    if (!isIdValido(id_processo)) {
      return res.status(400).json({ message: "id_processo deve ser um inteiro positivo." });
    }
    const idProcesso = toId(id_processo);

    const [processos] = await db.query(
      "SELECT id_processo, servidor_interessado_id FROM processos WHERE id_processo = ?",
      [idProcesso]
    );
    if (!processos.length) {
      return res.status(404).json({ message: "Processo não encontrado." });
    }

    // Mesma regra do detalhamento: servidor comum só consulta os próprios processos.
    if (
      usuario.perfil === "servidor_comum" &&
      Number(processos[0].servidor_interessado_id) !== Number(usuario.id_servidor)
    ) {
      return res.status(403).json({ message: "Acesso restrito aos próprios processos." });
    }

    const [historico] = await db.query(
      `SELECT t.id_tramitacao,
              t.id_processo,
              t.setor_origem_id,
              so.sigla AS setor_origem_sigla,
              so.nome AS setor_origem_nome,
              t.setor_destino_id,
              sd.sigla AS setor_destino_sigla,
              sd.nome AS setor_destino_nome,
              t.usuario_envio_id,
              srv.nome AS usuario_envio_nome,
              t.manter_visivel,
              t.prazo_retorno,
              t.data_tramitacao
         FROM tramitacoes t
         JOIN setores so ON so.id_setor = t.setor_origem_id
         JOIN setores sd ON sd.id_setor = t.setor_destino_id
         JOIN usuarios u ON u.id_usuario = t.usuario_envio_id
         JOIN servidores srv ON srv.id_servidor = u.id_servidor
        WHERE t.id_processo = ?
        ORDER BY t.data_tramitacao DESC, t.id_tramitacao DESC`,
      [idProcesso]
    );

    return res.status(200).json(historico);
  } catch (err) {
    console.error(err);
    return res.status(500).json({ message: "Erro ao consultar histórico de tramitações." });
  }
};

module.exports = {
  enviarProcesso,
  removerAcompanhamento,
  historicoTramitacoes
};