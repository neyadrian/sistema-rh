require("dotenv").config();   // 1º: carrega o .env antes de tudo

const express = require("express");
const app = express();
const cors = require("cors");
const db = require("./db/db");

const processoRoutes = require("./routes/processoRoutes");
const setoresRoutes = require("./routes/setoresRoutes");

app.use(cors());

app.use(processoRoutes);
app.use(setoresRoutes);

app.get("/health", async (req, res) => {
  try {
    const [rows] = await db.query("SELECT 1 + 1 AS resultado");
    res.json({ status: "ok", banco: rows[0].resultado });
  } catch (err) {
    console.error(err);
    res.status(500).json({ status: "erro", mensagem: err.message });
  }
});

app.use("/setores", setoresRoutes);

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Servidor rodando na porta ${PORT}`);
});