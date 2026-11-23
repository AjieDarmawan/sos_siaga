import { createApp } from './app.js';
import { config } from './config.js';
import { logger } from './logger.js';
import { pool } from './db.js';
import { startRealtime } from './lib/realtime.js';
import { startWebhookWorker } from './lib/webhooks.js';
import { startMaintenance } from './lib/maintenance.js';

const app = createApp();
startRealtime();
const worker = config.webhookWorker ? startWebhookWorker() : null;
const stopMaintenance = config.maintenanceWorker ? startMaintenance() : null;

const server = app.listen(config.port, () => logger.info(`SiagaSOS API listening on :${config.port}`));

async function shutdown(sig: string) {
  logger.info({ sig }, 'shutting down');
  if (worker) clearInterval(worker);
  stopMaintenance?.();
  server.close(() => pool.end().finally(() => process.exit(0)));
  setTimeout(() => process.exit(1), 10_000).unref();
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
