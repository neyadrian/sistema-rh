const jwt = require('jsonwebtoken');

const authMiddleware = (req, res, next) => {
  const authHeader = req.headers.authorization;

  // Verifica se o cabeçalho Authorization foi enviado e se inicia com "Bearer "
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ erro: 'Acesso negado. Token não fornecido.' });
  }

  const token = authHeader.split(' ')[1];

  try {
    // Decodifica e valida o token com a chave secreta do .env
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    
    // Anexa os dados do usuário (ex: id, papel, setor) no objeto req
    req.user = decoded;
    
    next();
  } catch (error) {
    return res.status(403).json({ erro: 'Token inválido ou expirado.' });
  }
};

module.exports = authMiddleware;