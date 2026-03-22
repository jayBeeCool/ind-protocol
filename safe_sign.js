const fs = require('fs');
const readline = require('readline');
const { Wallet } = require('ethers');

const keystorePath = process.env.KEYSTORE;
const digest = process.env.SAFE_TX_HASH;

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

rl.question('Keystore password: ', async (password) => {
  try {
    const json = fs.readFileSync(keystorePath, 'utf8');
    const wallet = await Wallet.fromEncryptedJson(json, password);
    const sig = wallet.signingKey.sign(digest);
    console.log('\n' + sig.serialized);
  } catch (e) {
    console.error('\nERROR:', e.message || e);
    process.exit(1);
  } finally {
    rl.close();
  }
});
