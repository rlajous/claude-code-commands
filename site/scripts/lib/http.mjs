/** Fetch one URL with a hard per-request deadline so retry loops cannot stall. */
export function fetchWithTimeout(url, timeoutMilliseconds, fetchImplementation = fetch) {
  return fetchImplementation(url, { signal: AbortSignal.timeout(timeoutMilliseconds) });
}
