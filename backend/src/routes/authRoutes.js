const { Router } = require('express');
const router = Router();

router.post('/login', async (req, res) => {
    try {
        const { matricula, senha } = req.body; //extrair matrícula e senha do corpo da requisição

        //devolver 400 se faltar algum
        if(!matricula || !senha) {
            return res.status(400).json({
                error: 'Matrícula e senha são obrigatórios'
            });
        }

        //buscar usuário com a conslta
        const usuario = await Usuario.findOne({ where: { matricula } });

        //devolver 401 se não encontrar o usuário
        if (!usuario) {
            return res.status(401).json({
                error: 'Matrícula ou senha inválidos'
            });
        }

        return res.status(200).json({
            message: 'login ok (placeholder)',
            usuario: { id: usuario.id, matricula: usuario.matricula }
        });
        
    } catch (error) {
        console.error(error);
        return res.status(500).json({ error: 'Erro interno no login' });
    }
});

module.exports = router;