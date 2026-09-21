(() => {
  const currentScript = document.currentScript;
  let appBase = '';
  try {
    const scriptUrl = new URL(currentScript?.src || 'assets/js/api.js', window.location.href);
    const marker = '/assets/js/api.js';
    const pathname = scriptUrl.pathname.replace(/\\/g, '/');
    const markerIndex = pathname.lastIndexOf(marker);
    appBase = markerIndex >= 0 ? pathname.slice(0, markerIndex) : '';
    if (appBase === '/') appBase = '';
  } catch (_) {
    appBase = '';
  }

  const apiUrl = path => `${appBase}/api${path}`;

  window.UniLinkAPI = {
    basePath: appBase,
    url(path) { return apiUrl(path); },
    async request(path, options = {}) {
      const opts = { credentials: 'include', headers: {}, ...options };
      if (opts.body && !(opts.body instanceof FormData)) {
        opts.headers = { ...opts.headers, 'Content-Type': 'application/json' };
        opts.body = JSON.stringify(opts.body);
      }
      let response;
      try {
        response = await fetch(apiUrl(path), opts);
      } catch (_) {
        throw new Error('Cannot reach the UniLink server. Check that the backend is running.');
      }
      const type = response.headers.get('content-type') || '';
      let data = {};
      if (type.includes('application/json')) {
        try { data = await response.json(); } catch (_) {}
      }
      if (!response.ok) {
        const error = new Error(data.error || data.message || `Request failed (${response.status})`);
        error.status = response.status;
        throw error;
      }
      return data;
    },
    get(path) { return this.request(path); },
    post(path, body) { return this.request(path, { method: 'POST', body }); },
    patch(path, body) { return this.request(path, { method: 'PATCH', body }); },
    put(path, body) { return this.request(path, { method: 'PUT', body }); },
    logout() { return this.post('/auth/logout', {}); }
  };
})();
