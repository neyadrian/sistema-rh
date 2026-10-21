function rbacMiddleware(perfisPermitidos) {
  return (req, res, next) => {
    if (!req.usuario || !perfisPermitidos.includes(req.usuario.perfil)) {
      return res.status(403).json({ message: "Acesso negado para este perfil." });
    }
    return next();
  };
}

module.exports = rbacMiddleware;
