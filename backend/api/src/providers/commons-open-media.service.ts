import { BadRequestException, Injectable, ServiceUnavailableException } from '@nestjs/common';

/**
 * API-only discovery for re-usable media hosted by Wikimedia Commons.
 * Breezze does not proxy, cache, upload or hold the audio/video bytes.
 * Commons metadata is uploader-supplied: this is a conservative allowlist,
 * NOT a warranty that every file is free of third-party rights.
 */
type MediaKind = 'audio' | 'video';
type MetadataValue = { value?: string };
type Page = {
  title?: string;
  imageinfo?: Array<{
    url?: string;
    mime?: string;
    size?: number;
    extmetadata?: Record<string, MetadataValue>;
  }>;
};
type ApiResponse = {
  query?: { pages?: Page[] };
  error?: { code?: string };
};
const API = 'https://commons.wikimedia.org/w/api.php';
const MAX_RESPONSE = 350_000;
const LICENSE_URL = /^https:\/\/creativecommons\.org\/(?:publicdomain\/zero\/1\.0|licenses\/by(?:-sa)?\/(?:2\.0|2\.5|3\.0|4\.0))\/?$/i;
const SEARCH = /^[\p{L}\p{N} .,'_-]{2,80}$/u;
const FILE_TITLE = /^File:[^<>\r\n?#]{1,175}$/u;

export interface OpenMediaFile {
  provider: 'wikimedia_commons';
  kind: MediaKind;
  fileTitle: string;
  title: string;
  mimeType: string;
  bytes: number;
  streamUrl: string;
  downloadUrl: string;
  downloadAllowed: true;
  saveTarget: 'listener_device';
  sourcePage: string;
  license: string;
  licenseUrl: string;
  creator: string | null;
  attributionRequired: true;
  fullLengthVerified: false;
}

function plainText(raw: string | undefined): string | null {
  if (!raw) return null;
  const txt = raw.replace(/<[^>]*>/g, ' ')
    .replace(/&amp;/g, '&').replace(/&quot;/g, '"')
    .replace(/&nbsp;/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 220);
  return txt || null;
}

function trustedMediaUrl(input: string | undefined): string | null {
  if (!input) return null;
  try {
    const u = new URL(input);
    return u.protocol === 'https:' && u.hostname === 'upload.wikimedia.org' &&
      u.port === '' && !u.username && !u.password && !u.hash && !u.search &&
      u.pathname.startsWith('/wikipedia/commons/')
      ? u.toString() : null;
  } catch {
    return null;
  }
}

function convertPage(page: Page, kind: MediaKind): OpenMediaFile | null {
  const info = page.imageinfo?.[0];
  if (!page.title || !FILE_TITLE.test(page.title) || !info) return null;
  const url = trustedMediaUrl(info.url);
  const mime = info.mime?.toLowerCase() ?? '';
  const matchesKind = kind === 'audio'
    ? /^audio\/(?:mpeg|ogg|flac|x-flac|wav|x-wav|webm|mp4|aac)$/.test(mime)
    : /^video\/(?:webm|ogg|mp4)$/.test(mime);
  const maxBytes = kind === 'video' ? 1_000_000_000 : 250_000_000;
  if (!url || !matchesKind || !Number.isSafeInteger(info.size) ||
      (info.size ?? 0) <= 0 || (info.size ?? 0) > maxBytes) return null;
  const licenseUrl = info.extmetadata?.LicenseUrl?.value?.trim() ?? '';
  // Only specific CC licenses whose direct re-use and download terms are
  // inspectable. Unknown, missing, NC, ND and bespoke licenses fail closed.
  if (!LICENSE_URL.test(licenseUrl)) return null;
  const title = page.title.slice(5).replace(/_/g, ' ');
  const license = licenseUrl.includes('/zero/')
    ? 'CC0 1.0'
    : 'CC ' + (licenseUrl.includes('/by-sa/') ? 'BY-SA ' : 'BY ') +
      /\/(2\.0|2\.5|3\.0|4\.0)\/?$/.exec(licenseUrl)![1];
  return {
    provider: 'wikimedia_commons',
    kind,
    fileTitle: page.title,
    title,
    mimeType: mime,
    bytes: info.size!,
    streamUrl: url,
    downloadUrl: url,
    downloadAllowed: true,
    saveTarget: 'listener_device',
    sourcePage: 'https://commons.wikimedia.org/wiki/' +
      encodeURIComponent(page.title.replace(/ /g, '_')),
    license,
    licenseUrl,
    creator: plainText(info.extmetadata?.Artist?.value),
    // We always require a visible source/credit even for CC0.
    attributionRequired: true,
    // File MIME and size alone cannot prove that a song is complete.
    fullLengthVerified: false,
  };
}

@Injectable()
export class CommonsOpenMediaService {
  get enabled(): boolean {
    return process.env.BREEZZE_OPEN_MEDIA_ENABLED === 'true';
  }

  private kind(raw: string | undefined): MediaKind {
    if (raw === 'audio' || raw === 'video') return raw;
    throw new BadRequestException('OPEN_MEDIA_KIND_INVALID');
  }

  private async queryApi(params: Record<string, string>): Promise<Page[]> {
    const url = new URL(API);
    for (const [k, value] of Object.entries({
      action: 'query', format: 'json', formatversion: '2',
      prop: 'imageinfo', iiprop: 'url|mime|size|extmetadata',
      iiextmetadatafilter: 'LicenseUrl|LicenseShortName|Artist',
      ...params,
    })) url.searchParams.set(k, value);
    try {
      const response = await fetch(url.toString(), {
        headers: {
          accept: 'application/json',
          'user-agent': 'Breezze/8 (https://github.com/MetroKim/Breezze; open media search)',
        },
        redirect: 'error',
        signal: AbortSignal.timeout(6000),
      });
      if (!response.ok ||
          Number(response.headers.get('content-length') ?? 0) > MAX_RESPONSE) {
        throw new Error('UNEXPECTED_COMMONS_RESPONSE');
      }
      const raw = await response.text();
      if (raw.length > MAX_RESPONSE) throw new Error('COMMONS_RESPONSE_TOO_LARGE');
      const json = JSON.parse(raw) as ApiResponse;
      if (json.error || !Array.isArray(json.query?.pages)) {
        throw new Error('COMMONS_RESPONSE_INVALID');
      }
      return json.query.pages.slice(0, 12);
    } catch {
      throw new ServiceUnavailableException('OPEN_MEDIA_PROVIDER_UNAVAILABLE');
    }
  }

  async search(queryRaw: string | undefined, kindRaw: string | undefined) {
    if (!this.enabled) {
      return { provider: 'wikimedia_commons', enabled: false, items: [] };
    }
    const kind = this.kind(kindRaw);
    const query = (queryRaw ?? '').trim().replace(/\s+/g, ' ');
    if (!SEARCH.test(query)) {
      throw new BadRequestException('OPEN_MEDIA_SEARCH_INVALID');
    }
    const pages = await this.queryApi({
      generator: 'search',
      gsrsearch: query + ' filetype:' + kind,
      gsrnamespace: '6',
      gsrlimit: '12',
    });
    return {
      provider: 'wikimedia_commons', enabled: true,
      items: pages.map(page => convertPage(page, kind))
        .filter((file): file is OpenMediaFile => file !== null),
    };
  }

  async resolve(title: string | undefined, kindRaw: string | undefined) {
    if (!this.enabled) {
      throw new ServiceUnavailableException('OPEN_MEDIA_NOT_ENABLED');
    }
    const kind = this.kind(kindRaw);
    if (!title || !FILE_TITLE.test(title)) {
      throw new BadRequestException('OPEN_MEDIA_FILE_INVALID');
    }
    // Recheck the current license on every play and download request.
    // Never trust a previously returned URL or client-supplied file metadata.
    const pages = await this.queryApi({ titles: title });
    const page = pages.find(p => p.title === title);
    const file = page ? convertPage(page, kind) : null;
    if (!file) throw new BadRequestException('OPEN_MEDIA_FILE_UNAVAILABLE');
    return file;
  }
}
