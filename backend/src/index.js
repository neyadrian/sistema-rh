const express = require('express');
const cors = require('cors');
const jwt = require('jsonwebtoken');
require('dotenv').config();

const authMiddleware = require('./middlewares/authMiddleware');
const checkRole = require('./middlewares/rbacMiddleware');

const app = express();
app.use(express.json());
app.use(cors());

// Rota pública de login (exemplo de geração do token)
app.post('/login', (req, res) => {
  const { email, senha } = req.body;

  // após validar a senha com bcrypt no banco:
  const usuarioFicticio = {
    id: 1,
    nome: 'Ney',
    papel: 'RH', // Pode ser 'RH', 'PGM', 'SEDUC', 'SESA', etc.
    setor: 'RH'
  };

  const token = jwt.sign(usuarioFicticio, process.env.JWT_SECRET, { expiresIn: '8h' });

  return res.json({ token });
});

// Rota protegida: Exige apenas token JWT válido
app.get('/perfil', authMiddleware, (req, res) => {
  res.json({ mensagem: 'Dados do perfil', usuario: req.user });
});

// Rota protegida por RBAC: Exige JWT e papel 'RH' ou 'ADMIN'
app.get('/rh/servidores', authMiddleware, checkRole(['RH', 'ADMIN']), (req, res) => {
  res.json({ mensagem: 'Acesso concedido aos dados do RH.' });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Servidor rodando na porta ${PORT}`));