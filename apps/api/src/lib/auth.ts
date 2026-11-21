import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { config } from '../config.js';

export const hashPassword = (pw: string) => bcrypt.hash(pw, 12);
export const verifyPassword = (pw: string, hash: string) => bcrypt.compare(pw, hash);

export interface PortalClaims { sub: string; acc: string; typ: 'portal' }
export interface AdminClaims { sub: string; role: string; typ: 'admin' }

export const signPortal = (userId: string, accountId: string) =>
  jwt.sign({ acc: accountId, typ: 'portal' }, config.jwtSecret, { subject: userId, expiresIn: '12h', audience: 'portal' });
export const verifyPortal = (t: string) => jwt.verify(t, config.jwtSecret, { audience: 'portal' }) as PortalClaims;

export const signAdmin = (adminId: string, role: string) =>
  jwt.sign({ role, typ: 'admin' }, config.adminJwtSecret, { subject: adminId, expiresIn: '8h', audience: 'admin' });
export const verifyAdmin = (t: string) => jwt.verify(t, config.adminJwtSecret, { audience: 'admin' }) as AdminClaims;

const FREE_DOMAINS = new Set([
  'gmail.com', 'googlemail.com', 'yahoo.com', 'yahoo.co.id', 'ymail.com', 'hotmail.com', 'outlook.com',
  'live.com', 'icloud.com', 'me.com', 'aol.com', 'proton.me', 'protonmail.com', 'gmx.com', 'mail.com',
]);
export const isFreeEmail = (email: string) => FREE_DOMAINS.has(email.split('@')[1]?.toLowerCase() ?? '');
