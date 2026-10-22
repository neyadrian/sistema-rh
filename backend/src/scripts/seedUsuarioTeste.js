require("dotenv").config();            // carrega o .env (este script roda sozinho, fora do servidor)
const bcrypt = require("bcrypt");
const db = require("../db/db");

async function main() {
  const matricula = "TESTE001";
  const senha = "Sigape@Teste2026";    // 16 caracteres, atende o mínimo de 10 do SRS

  // 1. Se o usuário de teste já existe, não faz nada (dá para rodar várias vezes)
  const [existe] = await db.query(
    "SELECT id_servidor FROM servidores WHERE matricula = ?", [matricula]
  );
  if (existe.length > 0) {
    console.log("Usuário de teste já existe. Nada a fazer.");
    return;
  }

  // 2. Cria um cargo de teste (INSERT IGNORE: se já existir, ignora sem dar erro)
  await db.query(
    "INSERT IGNORE INTO cargos (nome, codigo_rh) VALUES (?, ?)",
    ["Cargo de Teste", "TESTE"]
  );
  const [cargos] = await db.query(
    "SELECT id_cargo FROM cargos WHERE nome = ?", ["Cargo de Teste"]
  );

  // 3. Cria o servidor (vínculo 4 = ESTATUTARIO, situação 1 = ATIVO, setor 1 = RH)
  const [servidor] = await db.query(
    `INSERT INTO servidores
       (nome, cpf, matricula, id_cargo, id_vinculo, id_situacao, data_admissao, email, id_setor)
     VALUES (?, ?, ?, ?, 4, 1, '2020-01-01', ?, 1)`,
    ["Servidor de Teste", "11144477735", matricula, cargos[0].id_cargo, "teste@exemplo.com"]
  );

  // 4. Cria o usuário, com a senha já em hash bcrypt de custo 12 (nunca a senha pura)
  const hash = await bcrypt.hash(senha, 12);
  await db.query(
    "INSERT INTO usuarios (id_servidor, senha_hash, perfil) VALUES (?, ?, 'admin_sistema')",
    [servidor.insertId, hash]
  );

  console.log("Usuário de teste criado. Matrícula:", matricula, "| Senha:", senha);
}

main()
  .catch((err) => console.error("Erro:", err.message))
  .finally(() => db.end());              // fecha o pool, senão o script nunca termina