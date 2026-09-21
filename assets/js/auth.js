(function () {
  window.UniLinkAuth = {
    async requireUser() {
      try {
        const result = await UniLinkAPI.get('/auth/me');
        window.currentUser = result.user;
        document.querySelectorAll('[data-current-user]').forEach(el => { el.textContent = result.user.full_name || 'Account'; });
        return result.user;
      } catch (err) {
        if (err.status === 401) {
          const next = encodeURIComponent(location.pathname + location.search);
          location.replace('login.html?next=' + next);
          return null;
        }
        throw err;
      }
    },
    async logout() {
      try { await UniLinkAPI.logout(); }
      finally { location.replace('login.html'); }
    }
  };

  document.querySelectorAll('[data-logout]').forEach(el => {
    el.addEventListener('click', e => { e.preventDefault(); UniLinkAuth.logout(); });
  });

  if (!document.body.dataset.publicPage) {
    UniLinkAuth.ready = UniLinkAuth.requireUser();
  }
})();
