import { spawn } from 'child_process';
import { promisify } from 'util';
import * as fs from 'fs/promises';
import * as path from 'path';

// Plan §10.2 — one stage per function. FFmpeg/FFprobe are the real
// tools; nothing is faked. Output layout:
//   media/<jobId>/master.m3u8 + segment .ts files + audio-only variants

const exec = promisify(spawn as never) as never; // unused; kept for parity

export interface ProbeResult {
  durationSec: number;
  codec: string;
  sampleRateHz: number;
  bitrateKbps: number;
}

export async function probe(inputPath: string): Promise<ProbeResult> {
  const out = await run('ffprobe', [
    '-v', 'error',
    '-print_format', 'json',
    '-show_format',
    inputPath,
  ]);
  const parsed = JSON.parse(out) as {
    format: { duration: string; bit_rate: string };
    streams?: { codec_name: string; sample_rate?: string }[];
  };
  const audio = parsed.streams?.find((s) => !!s.sample_rate);
  return {
    durationSec: Number(parsed.format.duration),
    codec: audio?.codec_name ?? 'unknown',
    sampleRateHz: Number(audio?.sample_rate ?? 0),
    bitrateKbps: Math.round(Number(parsed.format.bit_rate) / 1000),
  };
}

export async function validate(jobId: string, inputPath: string): Promise<ProbeResult> {
  const result = await probe(inputPath).catch(() => null);
  if (!result || !Number.isFinite(result.durationSec) || result.durationSec <= 0) {
    throw new Error('PROBE_FAILED_NOT_PLAYABLE');
  }
  return result;
}

export async function transcodeToHls(
  jobId: string,
  inputPath: string,
  outDir: string,
  variants: { label: string; kbps: number }[] = [
    { label: 'aac_128', kbps: 128 },
    { label: 'aac_256', kbps: 256 },
  ],
): Promise<string> {
  await fs.mkdir(outDir, { recursive: true });
  const master = path.join(outDir, 'master.m3u8');
  await run('ffmpeg', [
    '-y',
    '-i', inputPath,
    ...variants.flatMap((v) => [
      '-c:a', 'aac', '-b:a', `${v.kbps}k`,
      '-hls_time', '6',
      '-hls_playlist_type', 'vbr',
      '-hls_segment_filename', path.join(outDir, `${v.label}_%03d.ts`),
      path.join(outDir, `${v.label}.m3u8`),
    ]),
  ]);
  return master;
}

function run(cmd: string, args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    child.stdout.on('data', (d: Buffer) => (stdout += d.toString()));
    child.on('error', reject);
    child.on('close', (code) => {
      if (code === 0) resolve(stdout);
      else reject(new Error(`${cmd} exited with code ${code}`));
    });
  });
}
