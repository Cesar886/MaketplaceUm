const db = require('./backend/src/database');
db.initDatabase();
const tokens = db.getDb().prepare('SELECT * FROM push_tokens').all();
console.log("Tokens:", tokens);
