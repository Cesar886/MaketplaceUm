const db = require('./backend/src/database');
db.initDatabase();
const convs = db.getDb().prepare('SELECT * FROM conversations LIMIT 1').all();
console.log("Conversations:", convs);
if (convs.length > 0) {
  const msgs = db.getMessages(convs[0].id);
  console.log("Messages for conv:", msgs);
}
