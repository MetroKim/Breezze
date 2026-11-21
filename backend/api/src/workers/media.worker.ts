import { Worker, Job } from 'bullmq';
import { PrismaClient } from '@prisma/client';
import {
  GetObjectCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { createWriteStream } from 'fs';
import * as fs from 'fs/promises';
import * as path from 'path';
import { Readable } from 'stream';
import { pipeline } from 'stream/promises';
import { MEDIA_QUEUE, MediaJobData } from './media.queue';
import { validate, transcodeAll } from './ffmpeg.stage';

function createR2Client(): S3Client {
  const accountId = process.env.R2_ACCOUNT_ID;
  const accessKeyId = process.env.R2_ACCESS_KEY_ID;
  const secretAccessKey = process.env.R2_SECRET_ACCESS_KEY;
  if (!accountId || !accessKeyId || !secretAccessKey) {
    throw new Error('R2_ACCOUNT_ID_AND_ACCESS_CREDENTIALS_REQUIRED');
  }
  return new S3Client({
    region: 'auto',
    endpoint: `https://${accountId}.r2.cloudflarestorage.com`,
    forcePathStyle: true,
    credentials: { accessKeyId, secretAccessKey },
  });
}

async function uploadDirectory(
  client: S3Client,
  bucket: string,
  localDirectory: string,
  objectPrefix: string,
): Promise<string[]> {
  const uploaded: string[] = [];
  const entries = await fs.readdir(localDirectory, { withFileTypes: true });
  for (const entry of entries) {
    const localPath = path.join(localDirectory, entry.name);
    const objectKey = `${objectPrefix}/${entry.name}`;
    if (entry.isDirectory()) {
      uploaded.push(...await uploadDirectory(client, bucket, localPath, objectKey));
      continue;
    }
    const extension = path.extname(entry.name).toLowerCase();
    const contentType = extension === '.m3u8'
      ? 'application/vnd.apple.mpegurl'
      : extension === '.ts' ? 'video/mp2t' : 'application/octet-stream';
    await client.send(new PutObjectCommand({
      Bucket: bucket,
      Key: objectKey,
      Body: await fs.readFile(localPath),
      ContentType: contentType,
      CacheControl: 'private, no-store',
    }));
    uploaded.push(objectKey);
  }
  return uploaded;
}

// R2 is the private source of truth. This worker downloads the user's
// quarantined object, validates/transcodes it locally, then writes
// processed outputs back to R2. Publishing to a canonical track key is
// a separate moderated catalog operation; processing alone never grants
// playback rights or makes a submission publicly playable.
export function startMediaWorker(redisUrl: string, databaseUrl: string) {
  const prisma = new PrismaClient({ datasources: { db: { url: databaseUrl } } });
  const r2 = createR2Client();
  const bucket = process.env.R2_BUCKET_NAME ?? 'breezze-media';
  const mediaRoot = process.env.MEDIA_ROOT ?? '/tmp/breezze-media';

  const worker = new Worker<MediaJobData>(
    MEDIA_QUEUE,
    async (job: Job<MediaJobData>) => {
      const { jobId } = job.data;
      const record = await prisma.mediaJob.findUnique({ where: { id: jobId } });
      if (!record) throw new Error('JOB_RECORD_NOT_FOUND');

      const filename = record.originalFilename.replace(/[^a-zA-Z0-9._-]/g, '_').slice(0, 120);
      const inputKey = `quarantine/${record.userId}/${jobId}/${filename}`;
      const workDir = path.join(mediaRoot, jobId);
      const inputPath = path.join(workDir, filename);
      const outDir = path.join(workDir, 'processed');
      await fs.mkdir(workDir, { recursive: true });

      await prisma.mediaJob.update({
        where: { id: jobId },
        data: { status: 'validating' },
      });

      const source = await r2.send(new GetObjectCommand({ Bucket: bucket, Key: inputKey }));
      if (!source.Body) throw new Error('R2_QUARANTINE_OBJECT_EMPTY');
      await pipeline(source.Body as Readable, createWriteStream(inputPath));

      const probe = await validate(inputPath);
      await prisma.mediaJob.update({
        where: { id: jobId },
        data: { status: 'processing' },
      });

      await transcodeAll(inputPath, outDir);
      const outputKeys = await uploadDirectory(
        r2,
        bucket,
        outDir,
        `processed/${jobId}`,
      );

      await prisma.mediaJob.update({
        where: { id: jobId },
        data: { status: 'processed' },
      });

      return {
        durationSec: probe.durationSec,
        bitrateKbps: probe.bitrateKbps,
        stagingPrefix: `processed/${jobId}`,
        outputKeys,
      };
    },
    {
      connection: { url: redisUrl },
      concurrency: 2,
    },
  );

  worker.on('failed', async (job, err) => {
    if (job) {
      await prisma.mediaJob
        .update({
          where: { id: job.data.jobId },
          data: { status: 'failed' },
        })
        .catch(() => undefined);
    }
    // eslint-disable-next-line no-console
    console.error(`media job failed: ${err.message}`);
  });

  return worker;
}
