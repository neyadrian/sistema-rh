const db = require("../db/db.js");

/* ------------------------------------------------------------------ */
/* Constantes                                                          */
/* ------------------------------------------------------------------ */

const PERFIS_ABERTURA_TERCEIROS = ["operador_setor", "gestor_setor", "admin_sistema"];
const NIVEIS_ACESSO = ["PUBLICO", "PRIVADO"];
const VIEWS_PERMITIDAS = ["vw_caixa_entrada", "vw_caixa_acompanhamento", "vw_processos_do_setor"];

// Ajuste conforme o tamanho da coluna descricao_justificativa no banco.
const DESCRICAO_MIN = 5;
const DESCRICAO_MAX = 5000;

/* ------------------------------------------------------------------ */
/* Helpers de validação (substituem, por enquanto, os middlewares)     */
/* ------------------------------------------------------------------ */

const criarErro = (statusCode, message) => {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
};

const padNumero = (numero) => String(numero).padStart(4, "0");

// Aceita 5 ou "5". Rejeita "", null, true, 1.5, -1, "abc", "5; DROP...".
const isIdValido = (valor) => {
  if (valor === null || valor === undefined || typeof valor === "boolean") return false;
  if (typeof valor !== "number" && typeof valor !== "string") return false;
  return /^\d+$/.test(String(valor).trim()) && Number(valor) > 0;
};

const toId = (valor) => Number(String(valor).trim());

const isObjetoSimples = (valor) =>
  valor !== null && typeof valor === "object" && !Array.isArray(valor);

/**
 * Valida e normaliza o req.body do cadastro.
 * Retorna { erro } em caso de falha ou { dados } com os campos já tratados.
 */
const validarBodyCadastro = (body) => {
  if (!isObjetoSimples(body)) {
    return { erro: { status: 400, message: "Corpo da requisição inválido ou ausente." } };
  }

  const {
    id_tipo_processo,
    id_assunto,
    servidor_interessado_id,
    descricao_justificativa,
    nivel_acesso
  } = body;

  // Campos obrigatórios
  const faltando = [];
  if (id_tipo_processo === undefined || id_tipo_processo === null || id_tipo_processo === "") {
    faltando.push("id_tipo_processo");
  }
  if (id_assunto === undefined || id_assunto === null || id_assunto === "") {
    faltando.push("id_assunto");
  }
  if (descricao_justificativa === undefined || descricao_justificativa === null) {
    faltando.push("descricao_justificativa");
  }
  if (faltando.length) {
    return {
      erro: { status: 400, message: `Campos obrigatórios ausentes: ${faltando.join(", ")}.` }
    };
  }

  // Tipos e formatos
  if (!isIdValido(id_tipo_processo)) {
    return { erro: { status: 400, message: "id_tipo_processo deve ser um inteiro positivo." } };
  }
  if (!isIdValido(id_assunto)) {
    return { erro: { status: 400, message: "id_assunto deve ser um inteiro positivo." } };
  }

  const temInteressado =
    servidor_interessado_id !== undefined &&
    servidor_interessado_id !== null &&
    servidor_interessado_id !== "";
  if (temInteressado && !isIdValido(servidor_interessado_id)) {
    return {
      erro: { status: 400, message: "servidor_interessado_id deve ser um inteiro positivo." }
    };
  }

  if (typeof descricao_justificativa !== "string") {
    return { erro: { status: 400, message: "descricao_justificativa deve ser um texto." } };
  }
  const descricao = descricao_justificativa.trim();
  if (descricao.length < DESCRICAO_MIN) {
    return {
      erro: {
        status: 400,
        message: `descricao_justificativa deve ter pelo menos ${DESCRICAO_MIN} caracteres.`
      }
    };
  }
  if (descricao.length > DESCRICAO_MAX) {
    return {
      erro: {
        status: 400,
        message: `descricao_justificativa deve ter no máximo ${DESCRICAO_MAX} caracteres.`
      }
    };
  }

  let nivelAcesso = "PUBLICO";
  if (nivel_acesso !== undefined && nivel_acesso !== null && nivel_acesso !== "") {
    if (typeof nivel_acesso !== "string" || !NIVEIS_ACESSO.includes(nivel_acesso.trim().toUpperCase())) {
      return { erro: { status: 400, message: "nivel_acesso deve ser PUBLICO ou PRIVADO." } };
    }
    nivelAcesso = nivel_acesso.trim().toUpperCase();
  }

  return {
    dados: {
      idTipoProcesso: toId(id_tipo_processo),
      idAssunto: toId(id_assunto),
      servidorInteressadoId: temInteressado ? toId(servidor_interessado_id) : null,
      descricao,
      nivelAcesso
    }
  };
};

/* ------------------------------------------------------------------ */
/* Helpers de negócio                                                  */
/* ------------------------------------------------------------------ */

const obterSetorOrigem = async (conn, usuario) => {
  if (usuario.perfil === "servidor_comum") {
    const [rh] = await conn.query(
      "SELECT id_setor, sigla FROM setores WHERE sigla = 'RH' AND ativo = 1 LIMIT 1"
    );
    if (!rh.length) {
      throw criarErro(500, "Setor RH não encontrado.");
    }
    return rh[0];
  }

  const [setor] = await conn.query(
    "SELECT id_setor, sigla FROM setores WHERE id_setor = ? AND ativo = 1 LIMIT 1",
    [usuario.id_setor]
  );
  if (!setor.length) {
    throw criarErro(400, "Setor do usuário não encontrado ou inativo.");
  }
  return setor[0];
};

const gerarNumeroProtocolo = async (conn, idSetorOrigem, sigla, anoAtual) => {
  await conn.query("SET @n = 0");
  await conn.query("CALL proximo_numero('PROCESSO', ?, 0, ?, @n)", [idSetorOrigem, anoAtual]);
  const [rows] = await conn.query("SELECT @n AS numero");
  const numero = rows[0] && rows[0].numero;
  if (!numero) {
    throw criarErro(500, "Não foi possível gerar o número de protocolo.");
  }
  return `${anoAtual}.${sigla}.${padNumero(numero)}`;
};

/* ------------------------------------------------------------------ */
/* Controllers                                                         */
/* ------------------------------------------------------------------ */

const cadastrar = async (req, res) => {
  // 1) Usuário autenticado (vem do middleware de autenticação)
  const usuario = req.usuario;
  if (!usuario || !usuario.perfil || !usuario.id_usuario) {
    return res.status(401).json({ message: "Usuário não autenticado." });
  }

  // 2) Validação do corpo
  const { erro, dados } = validarBodyCadastro(req.body);
  if (erro) {
    return res.status(erro.status).json({ message: erro.message });
  }

  const { idTipoProcesso, idAssunto, descricao, nivelAcesso } = dados;
  let interessadoId = dados.servidorInteressadoId;

  // 3) Regras de negócio sobre o interessado
  if (usuario.perfil === "servidor_comum") {
    if (interessadoId !== null && interessadoId !== Number(usuario.id_servidor)) {
      return res.status(403).json({
        message: "RN14: servidor comum só pode abrir processo em nome próprio."
      });
    }
    interessadoId = Number(usuario.id_servidor);
  } else if (PERFIS_ABERTURA_TERCEIROS.includes(usuario.perfil)) {
    interessadoId = interessadoId !== null ? interessadoId : Number(usuario.id_servidor);
  } else {
    return res.status(403).json({ message: "Perfil sem permissão para abrir processos." });
  }

  if (!interessadoId) {
    return res.status(400).json({ message: "servidor_interessado_id é obrigatório." });
  }

  // 4) Persistência
  const conn = await db.getConnection();
  try {
    await conn.beginTransaction();

    const [tipos] = await conn.query(
      "SELECT id_tipo_processo FROM tipos_processos WHERE id_tipo_processo = ? AND ativo = 1",
      [idTipoProcesso]
    );
    if (!tipos.length) {
      await conn.rollback();
      return res.status(400).json({ message: "Tipo de processo inválido ou inativo." });
    }

    const [assuntos] = await conn.query(
      `SELECT id_assunto FROM catalogos_assuntos
        WHERE id_assunto = ? AND id_tipo_processo = ? AND ativo = 1`,
      [idAssunto, idTipoProcesso]
    );
    if (!assuntos.length) {
      await conn.rollback();
      return res.status(400).json({ message: "Assunto inválido para o tipo de processo informado." });
    }

    const [servidores] = await conn.query(
      "SELECT id_servidor FROM servidores WHERE id_servidor = ?",
      [interessadoId]
    );
    if (!servidores.length) {
      await conn.rollback();
      return res.status(400).json({ message: "Servidor interessado não encontrado." });
    }

    const setorOrigem = await obterSetorOrigem(conn, usuario);
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
        idTipoProcesso,
        idAssunto,
        interessadoId,
        usuario.id_usuario,
        setorOrigem.id_setor,
        setorOrigem.id_setor,
        descricao,
        nivelAcesso
      ]
    );

    const idProcesso = result.insertId;

    await conn.query(
      `INSERT INTO andamentos (id_processo, id_setor, id_usuario, tipo_evento, descricao)
       VALUES (?, ?, ?, 'PROCESSO_GERADO', ?)`,
      [idProcesso, setorOrigem.id_setor, usuario.id_usuario, `Processo ${numeroProtocolo} gerado.`]
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
    // O nome da view é interpolado no SQL, então só aceitamos nomes conhecidos.
    if (!VIEWS_PERMITIDAS.includes(viewName)) {
      return res.status(500).json({ message: "Erro ao listar processos." });
    }

    const usuario = req.usuario;
    if (!usuario || !usuario.perfil) {
      return res.status(401).json({ message: "Usuário não autenticado." });
    }

    const { id_setor, perfil, id_servidor } = usuario;
    if (!isIdValido(id_setor)) {
      return res.status(400).json({ message: "Usuário sem setor válido associado." });
    }

    let sql = `SELECT * FROM ${viewName} WHERE id_setor_caixa = ?`;
    const params = [Number(id_setor)];

    if (perfil === "servidor_comum") {
      if (!isIdValido(id_servidor)) {
        return res.status(400).json({ message: "Usuário sem servidor válido associado." });
      }
      sql += " AND servidor_interessado_id = ?";
      params.push(Number(id_servidor));
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

const listarCaixaAcompanhamento = async (req, res) =>
  listarPorView(req, res, "vw_caixa_acompanhamento");

const listarTodosDoSetor = async (req, res) => listarPorView(req, res, "vw_processos_do_setor");

const detalharProcesso = async (req, res) => {
  try {
    const usuario = req.usuario;
    if (!usuario || !usuario.perfil) {
      return res.status(401).json({ message: "Usuário não autenticado." });
    }

    const { id } = req.params || {};
    if (!isIdValido(id)) {
      return res.status(400).json({ message: "id do processo deve ser um inteiro positivo." });
    }
    const idProcesso = toId(id);

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
      [idProcesso]
    );

    if (!processos.length) {
      return res.status(404).json({ message: "Processo não encontrado." });
    }

    const processo = processos[0];

    if (
      usuario.perfil === "servidor_comum" &&
      Number(processo.servidor_interessado_id) !== Number(usuario.id_servidor)
    ) {
      return res.status(403).json({ message: "Acesso restrito aos próprios processos." });
    }

    const [documentos] = await db.query(
      `SELECT d.*, td.nome AS tipo_documento_nome
         FROM documentos d
         JOIN tipos_documentos td ON td.id_tipo_documento = d.id_tipo_documento
        WHERE d.id_processo = ? AND d.status <> 'EXCLUIDO'
        ORDER BY d.numero_sequencial_processo ASC`,
      [idProcesso]
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
      [idProcesso]
    );

    return res.status(200).json({ processo, documentos, andamentos });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ message: "Erro ao detalhar processo." });
  }
};

 
/* ------------------------------------------------------------------ */
/* Atualização de processo                                             */
/* ------------------------------------------------------------------ */
 
// Campos que esta rota pode alterar. Qualquer outro campo no body é recusado
// (numero_protocolo, status, setor_atual_id, id_tipo_processo etc. têm fluxo próprio).
const CAMPOS_ATUALIZAVEIS = ["id_assunto", "descricao_justificativa", "nivel_acesso"];
const PERFIS_EDICAO = ["operador_setor", "gestor_setor", "admin_sistema"];
 
const validarBodyAtualizacao = (body) => {
  if (!isObjetoSimples(body)) {
    return { erro: { status: 400, message: "Corpo da requisição inválido ou ausente." } };
  }
 
  const naoPermitidos = Object.keys(body).filter((campo) => !CAMPOS_ATUALIZAVEIS.includes(campo));
  if (naoPermitidos.length) {
    return {
      erro: {
        status: 400,
        message: `Campos não permitidos na atualização: ${naoPermitidos.join(", ")}.`
      }
    };
  }
 
  const informados = CAMPOS_ATUALIZAVEIS.filter((campo) => body[campo] !== undefined);
  if (!informados.length) {
    return {
      erro: {
        status: 400,
        message: `Informe ao menos um campo para atualizar: ${CAMPOS_ATUALIZAVEIS.join(", ")}.`
      }
    };
  }
 
  const dados = {};
 
  if (body.id_assunto !== undefined) {
    if (!isIdValido(body.id_assunto)) {
      return { erro: { status: 400, message: "id_assunto deve ser um inteiro positivo." } };
    }
    dados.idAssunto = toId(body.id_assunto);
  }
 
  if (body.descricao_justificativa !== undefined) {
    if (typeof body.descricao_justificativa !== "string") {
      return { erro: { status: 400, message: "descricao_justificativa deve ser um texto." } };
    }
    const descricao = body.descricao_justificativa.trim();
    if (descricao.length < DESCRICAO_MIN || descricao.length > DESCRICAO_MAX) {
      return {
        erro: {
          status: 400,
          message: `descricao_justificativa deve ter entre ${DESCRICAO_MIN} e ${DESCRICAO_MAX} caracteres.`
        }
      };
    }
    dados.descricao = descricao;
  }
 
  if (body.nivel_acesso !== undefined) {
    const nivel = typeof body.nivel_acesso === "string" ? body.nivel_acesso.trim().toUpperCase() : "";
    if (!NIVEIS_ACESSO.includes(nivel)) {
      return { erro: { status: 400, message: "nivel_acesso deve ser PUBLICO ou PRIVADO." } };
    }
    dados.nivelAcesso = nivel;
  }
 
  return { dados };
};
 
const atualizar = async (req, res) => {
  // 1) Usuário autenticado
  const usuario = req.usuario;
  if (!usuario || !usuario.perfil || !usuario.id_usuario) {
    return res.status(401).json({ message: "Usuário não autenticado." });
  }
 
  // 2) Permissão por perfil (servidor comum não edita processos)
  if (!PERFIS_EDICAO.includes(usuario.perfil)) {
    return res.status(403).json({ message: "Perfil sem permissão para atualizar processos." });
  }
 
  // 3) Validação do parâmetro e do corpo
  const { id } = req.params || {};
  if (!isIdValido(id)) {
    return res.status(400).json({ message: "id do processo deve ser um inteiro positivo." });
  }
  const idProcesso = toId(id);
 
  const { erro, dados } = validarBodyAtualizacao(req.body);
  if (erro) {
    return res.status(erro.status).json({ message: erro.message });
  }
 
  // 4) Persistência
  const conn = await db.getConnection();
  try {
    await conn.beginTransaction();
 
    // Trava a linha para evitar atualização concorrente ou tramitação no meio da edição
    const [processos] = await conn.query(
      `SELECT id_processo, numero_protocolo, id_tipo_processo, id_assunto, setor_atual_id,
              descricao_justificativa, nivel_acesso, status
         FROM processos
        WHERE id_processo = ?
          FOR UPDATE`,
      [idProcesso]
    );
    if (!processos.length) {
      throw criarErro(404, "Processo não encontrado.");
    }
    const processo = processos[0];
 
    // RN17: só o setor que detém a posse atualiza (admin_sistema é exceção)
    if (
      usuario.perfil !== "admin_sistema" &&
      Number(processo.setor_atual_id) !== Number(usuario.id_setor)
    ) {
      throw criarErro(403, "RN17: só o setor que detém a posse do processo pode atualizá-lo.");
    }
 
    if (processo.status !== "EM_ANDAMENTO") {
      throw criarErro(409, "Só é possível atualizar processo em andamento.");
    }
 
    // Descobre o que realmente mudou
    const alteracoes = {}; // coluna -> novo valor
    const camposAlterados = [];
    let nivelAcessoAnterior = null;
 
    if (dados.idAssunto !== undefined && dados.idAssunto !== Number(processo.id_assunto)) {
      const [assuntos] = await conn.query(
        `SELECT id_assunto FROM catalogos_assuntos
          WHERE id_assunto = ? AND id_tipo_processo = ? AND ativo = 1`,
        [dados.idAssunto, processo.id_tipo_processo]
      );
      if (!assuntos.length) {
        throw criarErro(400, "Assunto inválido para o tipo de processo.");
      }
      alteracoes.id_assunto = dados.idAssunto;
      camposAlterados.push("assunto");
    }
 
    if (dados.descricao !== undefined && dados.descricao !== processo.descricao_justificativa) {
      alteracoes.descricao_justificativa = dados.descricao;
      camposAlterados.push("descrição/justificativa");
    }
 
    if (dados.nivelAcesso !== undefined && dados.nivelAcesso !== processo.nivel_acesso) {
      nivelAcessoAnterior = processo.nivel_acesso;
      alteracoes.nivel_acesso = dados.nivelAcesso;
    }
 
    const colunas = Object.keys(alteracoes);
    if (!colunas.length) {
      await conn.rollback();
      return res.status(200).json({
        message: "Nenhuma alteração: os valores informados são iguais aos atuais.",
        id_processo: idProcesso,
        campos_alterados: []
      });
    }
 
    // Os nomes das colunas vêm só das chaves montadas acima (nunca do body direto)
    const setSql = colunas.map((coluna) => `${coluna} = ?`).join(", ");
    await conn.query(`UPDATE processos SET ${setSql} WHERE id_processo = ?`, [
      ...colunas.map((coluna) => alteracoes[coluna]),
      idProcesso
    ]);
 
    // Andamentos (linha do tempo imutável, RF24)
    if (camposAlterados.length) {
      await conn.query(
        `INSERT INTO andamentos (id_processo, id_setor, id_usuario, tipo_evento, descricao)
         VALUES (?, ?, ?, 'OUTRO', ?)`,
        [
          idProcesso,
          processo.setor_atual_id,
          usuario.id_usuario,
          `Dados do processo atualizados: ${camposAlterados.join(", ")}.`
        ]
      );
    }
 
    if (alteracoes.nivel_acesso) {
      await conn.query(
        `INSERT INTO andamentos (id_processo, id_setor, id_usuario, tipo_evento, descricao)
         VALUES (?, ?, ?, 'NIVEL_ACESSO_ALTERADO', ?)`,
        [
          idProcesso,
          processo.setor_atual_id,
          usuario.id_usuario,
          `Nível de acesso alterado de ${nivelAcessoAnterior} para ${alteracoes.nivel_acesso}.`
        ]
      );
      camposAlterados.push("nível de acesso");
    }
 
    await conn.commit();
 
    return res.status(200).json({
      message: "Processo atualizado com sucesso.",
      id_processo: idProcesso,
      numero_protocolo: processo.numero_protocolo,
      campos_alterados: camposAlterados
    });
  } catch (err) {
    await conn.rollback();
    console.error(err);
    return res.status(err.statusCode || 500).json({
      message: err.statusCode ? err.message : "Erro ao atualizar processo."
    });
  } finally {
    conn.release();
  }
};

/**
 * Lista os processos em que o usuário logado é o servidor interessado,
 * em qualquer setor e com qualquer status. Não usa as views de caixa,
 * porque elas filtram por setor (id_setor_caixa).
 * Filtro opcional: ?status=EM_ANDAMENTO|CONCLUIDO|CANCELADO|ARQUIVADO
 */
const listarMeusProcessos = async (req, res) => {
  try {
    const usuario = req.usuario;
    if (!usuario || !usuario.perfil) {
      return res.status(401).json({ message: "Usuário não autenticado." });
    }
    if (!isIdValido(usuario.id_servidor)) {
      return res.status(400).json({ message: "Usuário sem servidor válido associado." });
    }
 
    const STATUS_VALIDOS = ["EM_ANDAMENTO", "CONCLUIDO", "CANCELADO", "ARQUIVADO"];
    const params = [Number(usuario.id_servidor)];
    let filtroStatus = "";
 
    const { status } = req.query || {};
    if (status !== undefined) {
      const statusNormalizado = String(status).trim().toUpperCase();
      if (!STATUS_VALIDOS.includes(statusNormalizado)) {
        return res.status(400).json({
          message: `status deve ser um de: ${STATUS_VALIDOS.join(", ")}.`
        });
      }
      filtroStatus = " AND p.status = ?";
      params.push(statusNormalizado);
    }
 
    const [processos] = await db.query(
      `SELECT p.*,
              tp.nome AS tipo_processo_nome,
              ca.descricao AS assunto_descricao,
              sa.sigla AS setor_atual_sigla,
              sa.nome AS setor_atual_nome
         FROM processos p
         JOIN tipos_processos tp ON tp.id_tipo_processo = p.id_tipo_processo
         JOIN catalogos_assuntos ca ON ca.id_assunto = p.id_assunto
         JOIN setores sa ON sa.id_setor = p.setor_atual_id
        WHERE p.servidor_interessado_id = ?${filtroStatus}
        ORDER BY p.data_abertura DESC`,
      params
    );
 
    return res.status(200).json(processos);
  } catch (err) {
    console.error(err);
    return res.status(500).json({ message: "Erro ao listar processos." });
  }
};
 
module.exports = {
  cadastrar,
  listarCaixaEntrada,
  listarCaixaAcompanhamento,
  listarMeusProcessos,
  listarTodosDoSetor,
  detalharProcesso,
  atualizar
};