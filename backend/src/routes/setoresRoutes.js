const express = require("express");
const db = require("../db/db");

const router = express.Router();   // um mini app só para as rotas de setores

router.get("/", async (req, res) => {
  try {
    const [rows] = await db.query("SELECT * FROM setores WHERE ativo = 1 ORDER BY nome");
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ status: "erro", mensagem: err.message });
  }
});

module.exports = router;