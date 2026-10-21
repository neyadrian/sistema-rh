const bcrypt = require("bcrypt");

async function main() {
  const senha = "Senha@123";

  const hash = await bcrypt.hash(senha, 10);
  console.log("Hash:", hash);

  const certa = await bcrypt.compare("Senha@123", hash);
  console.log("Senha certa:", certa);
}

main();