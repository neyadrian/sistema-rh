const { Router } = require("express");
const bcrypt = require("bcrypt");
const db = require("../db/db");

const router = Router();

router.post("/login", async (req, res) => {
  try {
    const { matricula, senha } = req.body ?? {};

    if (!matricula || !senha) {
      return res.status(400).json({ mensagem: "Matrícula e senha são obrigatórias." });
    }

    const sql = `
      SELECT u.id_usuario, u.senha_hash, u.perfil, u.ativo,
             u.tentativas_falhas, u.bloqueado_ate,
             s.nome, st.sigla AS setor
      FROM servidores s
      JOIN usuarios u ON u.id_servidor = s.id_servidor
      JOIN setores st ON st.id_setor = s.id_setor
      WHERE s.matricula = ?`;

    const [rows] = await db.query(sql, [matricula]);

    if (rows.length === 0) {
      return res.status(401).json({ mensagem: "Matrícula ou senha inválidos." });
    }

    const u = rows[0];

    const ok = await bcrypt.compare(senha, u.senha_hash);

    if (!ok) {
      return res.status(401).json({ mensagem: "Matrícula ou senha inválidos." });
    }

    return res.json({
      usuario: { id_usuario: u.id_usuario, nome: u.nome, perfil: u.perfil, setor: u.setor },
    });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ mensagem: "Erro interno." });
  }
});

module.exports = router;