require("dotenv").config();   // 1º: carrega o .env antes de tudo

const express = require("express");
const app = express();
const cors = require("cors");
const db = require("./db/db");
const swaggerUi = require("swagger-ui-express");
const YAML = require("yamljs");
const path = require("path");
const authRoutes = require('./routes/authRoutes');

const processoRoutes = require("./routes/processoRoutes");
const tramitacaoRoutes = require("./routes/tramitacaoRoutes");
const setoresRoutes = require("./routes/setoresRoutes");

app.use(cors());

app.use(express.json());

app.use(processoRoutes);
app.use(tramitacaoRoutes);
app.use(setoresRoutes);
app.use(authRoutes);
  
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
app.use('/auth', authRoutes);  


const openapiDoc = YAML.load(path.join(__dirname, "../docs/openapi.yaml"));
app.use("/docs", swaggerUi.serve, swaggerUi.setup(openapiDoc));

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Servidor rodando na porta ${PORT}`);
});