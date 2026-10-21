const jwt = require("jsonwebtoken");
const db = require("../db/db.js");

async function authMiddleware(req, res, next) {
  try {
    const header = req.headers.authorization;
    if (!header || !header.startsWith("Bearer ")) {
      return res.status(401).json({ message: "Token de autenticação não informado." });
    }

    const token = header.slice(7);
    const payload = jwt.verify(token, process.env.JWT_SECRET);

    const [rows] = await db.query(
      `SELECT u.id_usuario, u.id_servidor, u.perfil, u.ativo, s.id_setor
         FROM usuarios u
         JOIN servidores s ON s.id_servidor = u.id_servidor
        WHERE u.id_usuario = ?`,
      [payload.id_usuario]
    );

    if (!rows.length || !rows[0].ativo) {
      return res.status(401).json({ message: "Usuário inválido ou inativo." });
    }

    req.usuario = rows[0];
    return next();
  } catch (err) {
    return res.status(401).json({ message: "Token inválido ou expirado." });
  }
}

module.exports = authMiddleware;
