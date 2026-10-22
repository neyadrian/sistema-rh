const { Router } = require('express');
const router = Router();

router.post('/login', async (req, res) => {
    try {
        return res.status(200).json({ message: 'login ok (placeholder)' });
    } catch (error) {
        console.error(error);
        return res.status(500).json({ error: 'Erro interno no login' });
    }
});

module.exports = router;