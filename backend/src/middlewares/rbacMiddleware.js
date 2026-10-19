const checkRole = (papeisPermitidos = []) => {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({ erro: 'Usuário não autenticado.' });
    }

    const { papel } = req.user;

    // Confirma se o papel do usuário está na lista de permissões da rota
    if (!papeisPermitidos.includes(papel)) {
      return res.status(403).json({ 
        erro: 'Acesso negado. Você não possui permissão para acessar este recurso.' 
      });
    }

    next();
  };
};

module.exports = checkRole;