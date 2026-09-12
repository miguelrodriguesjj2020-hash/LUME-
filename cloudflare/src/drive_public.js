export function driveMediaMode() { return 'drive-public'; }

function forwardRequestHeaders(request) {
  const headers = new Headers();
  for (const name of ['range', 'if-range']) {
    const value = request.headers.get(name);
    if (value) headers.set(name, value);
  }
  return headers;
}

function mediaResponse(request, upstream) {
  const headers = new Headers();
  for (const name of ['content-type', 'content-length', 'content-range', 'accept-ranges', 'etag', 'last-modified', 'content-disposition']) {
    const value = upstream.headers.get(name);
    if (value) headers.set(name, value);
  }
  headers.set('cache-control', 'private, no-store');
  return new Response(request.method === 'HEAD' ? null : upstream.body, { status: upstream.status, headers });
}

export async function proxyDriveFile(request, _env, fileId) {
  const url = new URL('https://drive.usercontent.google.com/download');
  url.searchParams.set('id', fileId);
  url.searchParams.set('export', 'download');
  url.searchParams.set('confirm', 't');
  const headers = forwardRequestHeaders(request);
  if (request.method === 'HEAD' && !headers.has('range')) headers.set('range', 'bytes=0-0');
  const upstream = await fetch(url, { method: 'GET', headers, redirect: 'follow' });
  return mediaResponse(request, upstream);
}
