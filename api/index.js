const app = require('../discord-key-bot/index.js');
module.exports = async function handler(req, res) {
  return app(req, res);
};
