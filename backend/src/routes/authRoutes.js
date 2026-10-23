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
             (u.bloqueado_ate IS NOT NULL AND u.bloqueado_ate > NOW()) AS bloqueado,
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

    if (u.bloqueado) {
      return res.status(401).json({ mensagem: "Matrícula ou senha inválidos." });
    }

    const ok = await bcrypt.compare(senha, u.senha_hash);

    if (!ok) {
      await db.query(
        `UPDATE usuarios
            SET bloqueado_ate = IF(tentativas_falhas + 1 >= 5, DATE_ADD(NOW(), INTERVAL 15 MINUTE), bloqueado_ate),
                tentativas_falhas = tentativas_falhas + 1
          WHERE id_usuario = ?`,
        [u.id_usuario]
      );
      return res.status(401).json({ mensagem: "Matrícula ou senha inválidos." });
    }

    await db.query(
      `UPDATE usuarios
          SET tentativas_falhas = 0, bloqueado_ate = NULL, data_ultimo_acesso = NOW()
        WHERE id_usuario = ?`,
      [u.id_usuario]
    );

    return res.json({
      usuario: { id_usuario: u.id_usuario, nome: u.nome, perfil: u.perfil, setor: u.setor },
    });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ mensagem: "Erro interno." });
  }
});

module.exports = router;