const express = require("express");
const usuarioFake = require("../middlewares/usuarioFake.js");
const tramitacaoController = require("../controllers/tramitacaoController.js");

const router = express.Router();

router.post(
  "/api/tramitacoes/enviar",
  usuarioFake,
  // rbacMiddleware(["operador_setor", "gestor_setor", "admin_sistema"]),
  tramitacaoController.enviarProcesso
);

router.delete(
  "/api/tramitacoes/remover-acompanhamento/:id_processo",
  usuarioFake,
  // rbacMiddleware(["operador_setor", "gestor_setor", "admin_sistema"]),
  tramitacaoController.removerAcompanhamento
);

router.get(
  "/api/tramitacoes/historico/:id_processo",
  usuarioFake,
  // rbacMiddleware(["servidor_comum", "operador_setor", "gestor_setor", "admin_sistema"]),
  tramitacaoController.historicoTramitacoes
);

module.exports = router;