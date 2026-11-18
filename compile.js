const solc = require('solc');
const fs = require('fs');
const path = require('path');
const sources = {};
for (const f of ['AgentArena.sol', 'MockAgentID.sol']) {
  sources[f] = { content: fs.readFileSync(path.join('contracts', f), 'utf8') };
}
const input = { language: 'Solidity', sources,
  settings: { optimizer: { enabled: true, runs: 200 },
    outputSelection: { '*': { '*': ['abi', 'evm.bytecode.object'] } } } };
const out = JSON.parse(solc.compile(JSON.stringify(input)));
if (out.errors) for (const e of out.errors) {
  console.log(e.severity.toUpperCase(), e.formattedMessage.split('\n')[0]);
  if (e.severity === 'error') process.exit(1);
}
fs.mkdirSync('build', { recursive: true });
for (const [file, contracts] of Object.entries(out.contracts))
  for (const [name, c] of Object.entries(contracts)) {
    fs.writeFileSync(`build/${name}.json`, JSON.stringify({ abi: c.abi, bytecode: '0x' + c.evm.bytecode.object }, null, 2));
    console.log('compiled', name, 'bytecode bytes:', c.evm.bytecode.object.length / 2);
  }
