require("dotenv").config();   //1: carrega o .env antes de tudo

const express = require("express");
const cors = require("cors");
const db = require("./db/db");

const app = express();

app.use(cors());    //perite o front chamar a API
app.use(express.json());  //convete o body JSON em req.body (@RequestBody)

app.get("/health", async (req, res) => {
  try{
    const [rows] = await db.query("SELECT 1 + 1 AS resultado");   
    res.json({ status: "ok", banco: rows[0].resultado });
  } catch (err) {
    console.error(err);   //mostra o erro no terminal
    res.status(500).json({ status: "erro", mensagem: err.message });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Servidor rodando na porta ${PORT}`);
});