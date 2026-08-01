const db = require('./backend/src/database');
db.initDatabase();
const { sendPush } = require('./backend/src/push');
async function run() {
  const result = await sendPush(['u_prueba_gbl2'], 'Test Title', 'Test Body', { test: '123' });
  console.log("Send Push Result:", result);
}
run();
