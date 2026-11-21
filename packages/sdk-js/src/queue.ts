/**
 * Antrian offline: IndexedDB bila ada, fallback localStorage, lalu memori (SSR/test).
 * Item tetap ada sampai server membalas 2xx atau error permanen (4xx).
 */
export interface QueueItem {
  localId: string;
  idempotencyKey: string;
  createdAt: string;
  body: Record<string, unknown>;
}

export interface Queue {
  put(item: QueueItem): Promise<void>;
  remove(localId: string): Promise<void>;
  all(): Promise<QueueItem[]>;
}

const STORE = 'outbox';

function idbQueue(name: string): Queue | null {
  if (typeof indexedDB === 'undefined') return null;
  let dbp: Promise<IDBDatabase> | null = null;
  const open = () =>
    (dbp ??= new Promise((resolve, reject) => {
      const req = indexedDB.open(name, 1);
      req.onupgradeneeded = () => req.result.createObjectStore(STORE, { keyPath: 'localId' });
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    }));
  const run = <T>(mode: IDBTransactionMode, fn: (s: IDBObjectStore) => IDBRequest<T>) =>
    open().then(
      (db) =>
        new Promise<T>((resolve, reject) => {
          const r = fn(db.transaction(STORE, mode).objectStore(STORE));
          r.onsuccess = () => resolve(r.result);
          r.onerror = () => reject(r.error);
        }),
    );
  return {
    put: (item) => run('readwrite', (s) => s.put(item)).then(() => {}),
    remove: (id) => run('readwrite', (s) => s.delete(id)).then(() => {}),
    all: () => run<QueueItem[]>('readonly', (s) => s.getAll() as IDBRequest<QueueItem[]>).then((xs) => xs.sort((a, b) => a.createdAt.localeCompare(b.createdAt))),
  };
}

function storageQueue(name: string): Queue | null {
  let ls: Storage;
  try {
    ls = localStorage;
    ls.setItem(name + ':probe', '1');
    ls.removeItem(name + ':probe');
  } catch {
    return null;
  }
  const read = (): QueueItem[] => {
    try {
      return JSON.parse(ls.getItem(name) ?? '[]');
    } catch {
      return [];
    }
  };
  const write = (xs: QueueItem[]) => ls.setItem(name, JSON.stringify(xs));
  return {
    put: async (item) => write([...read().filter((x) => x.localId !== item.localId), item]),
    remove: async (id) => write(read().filter((x) => x.localId !== id)),
    all: async () => read(),
  };
}

function memoryQueue(): Queue {
  const m = new Map<string, QueueItem>();
  return {
    put: async (i) => void m.set(i.localId, i),
    remove: async (id) => void m.delete(id),
    all: async () => [...m.values()],
  };
}

export function createQueue(name: string): Queue {
  const primary = idbQueue(name) ?? storageQueue(name) ?? memoryQueue();
  const fallback = memoryQueue();
  // IndexedDB bisa gagal (mode privat Safari lama): jatuh ke memori, jangan lempar error saat darurat.
  const safe = <A extends unknown[], R>(f: (...a: A) => Promise<R>, g: (...a: A) => Promise<R>) =>
    (...a: A) => f(...a).catch(() => g(...a));
  return {
    put: safe(primary.put, fallback.put),
    remove: (id) => Promise.all([primary.remove(id).catch(() => {}), fallback.remove(id)]).then(() => {}),
    all: async () => {
      const [a, b] = await Promise.all([primary.all().catch(() => []), fallback.all()]);
      const seen = new Set(a.map((x) => x.localId));
      return [...a, ...b.filter((x) => !seen.has(x.localId))];
    },
  };
}
