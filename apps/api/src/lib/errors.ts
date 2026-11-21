import type { ErrorRequestHandler, RequestHandler } from 'express';
import { ZodError, type ZodTypeAny, type z } from 'zod';
import { logger } from '../logger.js';

export class ApiError extends Error {
  constructor(public status: number, public code: string, message: string, public details?: unknown) {
    super(message);
  }
}

export const notFound = (what = 'resource') => new ApiError(404, 'not_found', `${what} tidak ditemukan`);
export const forbidden = (code: string, message: string) => new ApiError(403, code, message);

export function parse<S extends ZodTypeAny>(schema: S, data: unknown): z.output<S> {
  const r = schema.safeParse(data);
  if (!r.success) throw new ApiError(422, 'validation_failed', 'Data tidak valid', r.error.flatten());
  return r.data;
}

export const notFoundHandler: RequestHandler = (_req, _res, next) => next(new ApiError(404, 'route_not_found', 'Endpoint tidak ada'));

export const errorHandler: ErrorRequestHandler = (err, req, res, _next) => {
  if (err instanceof ZodError) err = new ApiError(422, 'validation_failed', 'Data tidak valid', err.flatten());
  if (err?.type === 'entity.parse.failed') err = new ApiError(400, 'invalid_json', 'Body bukan JSON valid');
  if (err?.name === 'MulterError') {
    err = new ApiError(err.code === 'LIMIT_FILE_SIZE' ? 413 : 400, 'upload_invalid', err.message);
  }
  if (err instanceof ApiError) {
    res.status(err.status).json({ error: { code: err.code, message: err.message, details: err.details } });
    return;
  }
  // pg unique violation
  if (err?.code === '23505') {
    res.status(409).json({ error: { code: 'conflict', message: 'Data sudah ada', details: err.constraint } });
    return;
  }
  (req as any).log?.error({ err }, 'unhandled error') ?? logger.error({ err }, 'unhandled error');
  res.status(500).json({ error: { code: 'internal_error', message: 'Terjadi kesalahan server' } });
};
