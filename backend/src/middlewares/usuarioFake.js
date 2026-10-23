// APENAS PARA TESTE. Remover quando o middleware de autenticação existir.
const usuario1 = {
  id_usuario: 1,
  id_servidor: 1,
  id_setor: 1,
  perfil: "gestor_setor" // RH
};

const usuario2 = {
  id_usuario: 7,
  id_servidor: 7,
  id_setor: 3,
  perfil: "operador_setor" // SEDUC
};

const usuario3 = {
  id_usuario: 8,
  id_servidor: 8,
  id_setor: 3,
  perfil: "servidor_comum" // SEDUC
};

const usuarioFake = (req, res, next) => {
  req.usuario = usuario1; // Altere para usuario2 ou usuario3 para testar diferentes perfis
  next();
};

module.exports = usuarioFake;