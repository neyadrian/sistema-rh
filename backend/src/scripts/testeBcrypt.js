const bcrypt = require("bcrypt");

async function main() {
    const senha = "Senha@123";

    console.time("custo 10");
    await bcrypt.hash(senha, 10);
    console.timeEnd("custo 10");

    console.time("custo 12");
    await bcrypt.hash(senha, 12);
    console.timeEnd("custo 12");
}

main();