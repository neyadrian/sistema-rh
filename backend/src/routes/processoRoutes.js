const express = require("express");
const authMiddleware = require("../middlewares/authMiddleware.js");
const rbacMiddleware = require("../middlewares/rbacMiddleware.js");
const processoController = require("../controllers/processoController.js");

const router = express.Router();

router.post(
  "/api/processos/cadastrar",
  // authMiddleware,
  // rbacMiddleware(["servidor_comum", "operador_setor", "gestor_setor", "admin_sistema"]),
  processoController.cadastrar
);

router.get(
  "/api/processos/listar/caixa-entrada",
  // authMiddleware,
  // rbacMiddleware(["operador_setor", "gestor_setor", "admin_sistema"]),
  processoController.listarCaixaEntrada
);

router.get(
  "/api/processos/listar/caixa-acompanhamento",
  // authMiddleware,
  // rbacMiddleware(["operador_setor", "gestor_setor", "admin_sistema"]),
  processoController.listarCaixaAcompanhamento
);

router.get(
  "/api/processos/listar/todos-do-setor",
  // authMiddleware,
  // rbacMiddleware(["operador_setor", "gestor_setor", "admin_sistema"]),
  processoController.listarTodosDoSetor
);

router.get(
  "/api/processos/detalhar/:id",
  // authMiddleware,
  // rbacMiddleware(["servidor_comum", "operador_setor", "gestor_setor", "admin_sistema"]),
  processoController.detalharProcesso
);

module.exports = router;