const db = require("../db/db.js");

const PERFIS_ABERTURA_TERCEIROS = ["operador_setor", "gestor_setor", "admin_sistema"];

const padNumero = (numero) => String(numero).padStart(4, "0");

const obterSetorOrigem = async (conn, usuario) => {
  if (usuario.perfil === "servidor_comum") {
    const [rh] = await conn.query(
      "SELECT id_setor, sigla FROM setores WHERE sigla = 'RH' AND ativo = 1 LIMIT 1"
    );
    if (!rh.length) {
      const error = new Error("Setor RH não encontrado.");
      error.statusCode = 500;
      throw error;
    }
    return rh[0];
  }

  const [setor] = await conn.query(
    "SELECT id_setor, sigla FROM setores WHERE id_setor = ? AND ativo = 1 LIMIT 1",
    [usuario.id_setor]
  );
  if (!setor.length) {
    const error = new Error("Setor do usuário não encontrado ou inativo.");
    error.statusCode = 400;
    throw error;
  }
  return setor[0];
};

const gerarNumeroProtocolo = async (conn, idSetorOrigem, sigla, anoAtual) => {
  await conn.query("SET @n = 0");
  await conn.query("CALL proximo_numero('PROCESSO', ?, 0, ?, @n)", [idSetorOrigem, anoAtual]);
  const [rows] = await conn.query("SELECT @n AS numero");
  const numero = rows[0] && rows[0].numero;
  if (!numero) {
    const error = new Error("Não foi possível gerar o número de protocolo.");
    error.statusCode = 500;
    throw error;
  }
  return `${anoAtual}.${sigla}.${padNumero(numero)}`;
};

const cadastrar = async (req, res) => {
  const {
    id_tipo_processo,
    id_assunto,
    servidor_interessado_id,
    descricao_justificativa,
    nivel_acesso
  } = req.body || {};

  if (!id_tipo_processo || !id_assunto || !descricao_justificativa || !String(descricao_justificativa).trim()) {
    return res.status(400).json({
      message: "id_tipo_processo, id_assunto e descricao_justificativa são obrigatórios."
    });
  }

  const nivelAcesso = nivel_acesso || "PUBLICO";
  if (!["PUBLICO", "PRIVADO"].includes(nivelAcesso)) {
    return res.status(400).json({ message: "nivel_acesso deve ser PUBLICO ou PRIVADO." });
  }

  const perfil = req.usuario.perfil;
  let interessadoId = servidor_interessado_id;

  if (perfil === "servidor_comum") {
    if (
      servidor_interessado_id != null &&
      Number(servidor_interessado_id) !== Number(req.usuario.id_servidor)
    ) {
      return res.status(403).json({
        message: "RN14: servidor comum só pode abrir processo em nome próprio."
      });
    }
    interessadoId = req.usuario.id_servidor;
  } else if (PERFIS_ABERTURA_TERCEIROS.includes(perfil)) {
    interessadoId = servidor_interessado_id || req.usuario.id_servidor;
  }

  if (!interessadoId) {
    return res.status(400).json({ message: "servidor_interessado_id é obrigatório." });
  }

  const conn = await db.getConnection();
  try {
    await conn.beginTransaction();

    const [tipos] = await conn.query(
      "SELECT id_tipo_processo FROM tipos_processos WHERE id_tipo_processo = ? AND ativo = 1",
      [id_tipo_processo]
    );
    if (!tipos.length) {
      await conn.rollback();
      return res.status(400).json({ message: "Tipo de processo inválido ou inativo." });
    }

    const [assuntos] = await conn.query(
      `SELECT id_assunto FROM catalogos_assuntos
        WHERE id_assunto = ? AND id_tipo_processo = ? AND ativo = 1`,
      [id_assunto, id_tipo_processo]
    );
    if (!assuntos.length) {
      await conn.rollback();
      return res.status(400).json({ message: "Assunto inválido para o tipo de processo informado." });
    }

    const setorOrigem = await obterSetorOrigem(conn, req.usuario);
    const anoAtual = new Date().getFullYear();
    const numeroProtocolo = await gerarNumeroProtocolo(
      conn,
      setorOrigem.id_setor,
      setorOrigem.sigla,
      anoAtual
    );

    const [result] = await conn.query(
      `INSERT INTO processos (
         numero_protocolo, id_tipo_processo, id_assunto, servidor_interessado_id,
         usuario_abertura_id, setor_origem_id, setor_atual_id, descricao_justificativa, nivel_acesso
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        numeroProtocolo,
        id_tipo_processo,
        id_assunto,
        interessadoId,
        req.usuario.id_usuario,
        setorOrigem.id_setor,
        setorOrigem.id_setor,
        String(descricao_justificativa).trim(),
        nivelAcesso
      ]
    );

    const idProcesso = result.insertId;

    await conn.query(
      `INSERT INTO andamentos (id_processo, id_setor, id_usuario, tipo_evento, descricao)
       VALUES (?, ?, ?, 'PROCESSO_GERADO', ?)`,
      [
        idProcesso,
        setorOrigem.id_setor,
        req.usuario.id_usuario,
        `Processo ${numeroProtocolo} gerado.`
      ]
    );

    await conn.commit();

    return res.status(201).json({
      message: "Processo aberto com sucesso.",
      id_processo: idProcesso,
      numero_protocolo: numeroProtocolo
    });
  } catch (err) {
    await conn.rollback();
    console.error(err);
    return res.status(err.statusCode || 500).json({
      message: err.statusCode ? err.message : "Erro ao cadastrar processo."
    });
  } finally {
    conn.release();
  }
};

const listarPorView = async (req, res, viewName) => {
  try {
    const { id_setor, perfil, id_servidor } = req.usuario;
    let sql = `SELECT * FROM ${viewName} WHERE id_setor_caixa = ?`;
    const params = [id_setor];

    if (perfil === "servidor_comum") {
      sql += " AND servidor_interessado_id = ?";
      params.push(id_servidor);
    }

    sql += " ORDER BY data_abertura DESC";
    const [processos] = await db.query(sql, params);

    return res.status(200).json(processos);
    
  } catch (err) {
    console.error(err);
    return res.status(500).json({ message: "Erro ao listar processos." });
  }
};

const listarCaixaEntrada = async (req, res) => listarPorView(req, res, "vw_caixa_entrada");

const listarCaixaAcompanhamento = async (req, res) => listarPorView(req, res, "vw_caixa_acompanhamento");

const listarTodosDoSetor = async (req, res) => listarPorView(req, res, "vw_processos_do_setor");

const detalharProcesso = async (req, res) => {
  try {
    const { id } = req.params;

    const [processos] = await db.query(
      `SELECT p.*,
              s.nome AS interessado_nome,
              s.matricula AS interessado_matricula,
              s.cpf AS interessado_cpf,
              s.email AS interessado_email,
              ca.descricao AS assunto_descricao,
              ca.prazo_dias_padrao,
              tp.nome AS tipo_processo_nome,
              so.sigla AS setor_origem_sigla,
              so.nome AS setor_origem_nome,
              sa.sigla AS setor_atual_sigla,
              sa.nome AS setor_atual_nome
         FROM processos p
         JOIN servidores s ON s.id_servidor = p.servidor_interessado_id
         JOIN catalogos_assuntos ca ON ca.id_assunto = p.id_assunto
         JOIN tipos_processos tp ON tp.id_tipo_processo = p.id_tipo_processo
         JOIN setores so ON so.id_setor = p.setor_origem_id
         JOIN setores sa ON sa.id_setor = p.setor_atual_id
        WHERE p.id_processo = ?`,
      [id]
    );

    if (!processos.length) {
      return res.status(404).json({ message: "Processo não encontrado." });
    }

    const processo = processos[0];

    if (
      req.usuario.perfil === "servidor_comum" &&
      Number(processo.servidor_interessado_id) !== Number(req.usuario.id_servidor)
    ) {
      return res.status(403).json({ message: "Acesso restrito aos próprios processos." });
    }

    const [documentos] = await db.query(
      `SELECT d.*, td.nome AS tipo_documento_nome
         FROM documentos d
         JOIN tipos_documentos td ON td.id_tipo_documento = d.id_tipo_documento
        WHERE d.id_processo = ? AND d.status <> 'EXCLUIDO'
        ORDER BY d.numero_sequencial_processo ASC`,
      [id]
    );

    const [andamentos] = await db.query(
      `SELECT a.*,
              st.sigla AS setor_sigla,
              st.nome AS setor_nome,
              srv.nome AS usuario_nome
         FROM andamentos a
         JOIN setores st ON st.id_setor = a.id_setor
         JOIN usuarios u ON u.id_usuario = a.id_usuario
         JOIN servidores srv ON srv.id_servidor = u.id_servidor
        WHERE a.id_processo = ?
        ORDER BY a.data_hora ASC`,
      [id]
    );

    return res.status(200).json({
      processo,
      documentos,
      andamentos
    });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ message: "Erro ao detalhar processo." });
  }
};

module.exports = {
  cadastrar,
  listarCaixaEntrada,
  listarCaixaAcompanhamento,
  listarTodosDoSetor,
  detalharProcesso
};