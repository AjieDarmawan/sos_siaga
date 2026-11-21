import { DeleteObjectCommand, GetObjectCommand, HeadObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { config } from '../config.js';

/**
 * Object storage untuk media laporan (MinIO/S3). Bucket privat: unggah lewat presigned PUT langsung dari perangkat,
 * baca lewat presigned GET berumur pendek. Tidak ada byte file yang lewat API.
 */
export const mediaEnabled = () => !!(config.s3.endpoint && config.s3.accessKey && config.s3.secretKey);

let client: S3Client | null = null;
function s3() {
  client ??= new S3Client({
    endpoint: config.s3.endpoint,
    region: config.s3.region,
    forcePathStyle: config.s3.forcePathStyle,
    credentials: { accessKeyId: config.s3.accessKey, secretAccessKey: config.s3.secretKey },
  });
  return client;
}

export function presignPut(key: string, contentType: string, sizeBytes: number, expiresIn = config.media.uploadUrlTtlS) {
  // ContentLength ikut ditandatangani: klien tidak bisa mengunggah file lebih besar dari yang dideklarasikan.
  return getSignedUrl(s3(), new PutObjectCommand({ Bucket: config.s3.bucket, Key: key, ContentType: contentType, ContentLength: sizeBytes }), { expiresIn });
}

export function presignGet(key: string, opts: { filename?: string; expiresIn?: number } = {}) {
  return getSignedUrl(
    s3(),
    new GetObjectCommand({
      Bucket: config.s3.bucket,
      Key: key,
      ...(opts.filename ? { ResponseContentDisposition: `inline; filename="${opts.filename.replace(/"/g, '')}"` } : {}),
    }),
    { expiresIn: opts.expiresIn ?? config.media.viewUrlTtlS },
  );
}

/**
 * HEAD objek. MinIO bisa membalas 403 (bukan 404) untuk objek yang belum ada bila kredensial tidak punya ListBucket,
 * dan cluster di belakang load balancer kadang belum melihat objek sesaat setelah PUT. Jadi 403/404 = "belum ada",
 * diulang singkat (total ±3 dtk) sebelum menyerah.
 */
export async function headObject(key: string, retries = 4): Promise<{ size: number; contentType: string | null } | null> {
  for (let i = 0; ; i++) {
    try {
      const out = await s3().send(new HeadObjectCommand({ Bucket: config.s3.bucket, Key: key }));
      return { size: Number(out.ContentLength ?? 0), contentType: out.ContentType ?? null };
    } catch (e: any) {
      const status = e?.$metadata?.httpStatusCode;
      if (status !== 404 && status !== 403 && e?.name !== 'NotFound') throw e;
      if (i >= retries) return null;
      await new Promise((r) => setTimeout(r, 250 * 2 ** i));
    }
  }
}

export async function deleteObject(key: string) {
  await s3().send(new DeleteObjectCommand({ Bucket: config.s3.bucket, Key: key })).catch(() => {});
}
