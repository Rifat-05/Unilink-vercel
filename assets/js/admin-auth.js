(function () {

  window.UniLinkAdminAuth = {

    async requireAdmin() {
      try {
        const result = await UniLinkAPI.get('/admin/me');

        window.currentAdmin = result.user;

        document
          .querySelectorAll('[data-admin-name]')
          .forEach(el => {
            el.textContent =
              result.user.full_name || 'Administrator';
          });

        return result.user;

      } catch (err) {

        if (err.status === 401 || err.status === 403) {
          location.replace('login.html');
          return null;
        }

        throw err;
      }
    },

    async logout() {
      try {
        await UniLinkAPI.logout();
      } finally {
        location.replace('login.html');
      }
    }

  };

  UniLinkAdminAuth.ready =
    UniLinkAdminAuth.requireAdmin();

})();
