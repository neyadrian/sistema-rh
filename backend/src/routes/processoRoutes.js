const express = require("express");
const usuarioFake = require("../middlewares/usuarioFake.js");
const processoController = require("../controllers/processoController.js");

const router = express.Router();

router.post(
  "/api/processos/cadastrar",
  usuarioFake,
  // rbacMiddleware(["servidor_comum", "operador_setor", "gestor_setor", "admin_sistema"]),
  processoController.cadastrar
);

router.patch(
  "/api/processos/atualizar/:id",
  usuarioFake,
  // rbacMiddleware(["servidor_comum", "operador_setor", "gestor_setor", "admin_sistema"]),
  processoController.atualizar
);

router.get(
  "/api/processos/listar/caixa-entrada",
  usuarioFake,
  // rbacMiddleware(["operador_setor", "gestor_setor", "admin_sistema"]),
  processoController.listarCaixaEntrada
);

router.get(
  "/api/processos/listar/caixa-acompanhamento",
  usuarioFake,
  // rbacMiddleware(["operador_setor", "gestor_setor", "admin_sistema"]),
  processoController.listarCaixaAcompanhamento
);

router.get(
  "/api/processos/listar/todos-do-setor",
  usuarioFake,
  // authMiddleware,
  // rbacMiddleware(["operador_setor", "gestor_setor", "admin_sistema"]),
  processoController.listarTodosDoSetor
);

router.get(
  "/api/processos/listar/meus-processos",
  usuarioFake,
  // authMiddleware,
  // rbacMiddleware(["servidor_comum", "operador_setor", "gestor_setor", "admin_sistema"]),
  processoController.listarMeusProcessos
);

router.get(
  "/api/processos/detalhar/:id",
  usuarioFake,
  // rbacMiddleware(["servidor_comum", "operador_setor", "gestor_setor", "admin_sistema"]),
  processoController.detalharProcesso
);

module.exports = router;