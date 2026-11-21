import pino from 'pino';
import { config } from './config.js';

export const logger = pino({
  level: process.env.LOG_LEVEL ?? (config.isProd ? 'info' : 'debug'),
  redact: ['req.headers.authorization', 'req.headers["x-sos-key"]', 'req.headers.cookie'],
});
