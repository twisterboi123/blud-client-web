try {
  module.exports = require('./discord-key-bot/index.js');
} catch (error) {
  console.error('Failed to start app from discord-key-bot:', error.message);
  process.exit(1);
}
