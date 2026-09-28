(async function () {

  try {

    const admin = await UniLinkAdminAuth.ready;

    if (!admin) return;


    // Admin name
    document
      .querySelectorAll('[data-admin-name]')
      .forEach(el => {
        el.textContent =
          admin.full_name || 'Administrator';
      });


    // Logout
    const logout =
      document.getElementById('adminLogout');

    if (logout) {
      logout.addEventListener('click', function (e) {
        e.preventDefault();
        UniLinkAdminAuth.logout();
      });
    }


    // Get real dashboard statistics
    const result =
      await UniLinkAPI.get('/admin/stats');

    const stats = result.stats || {};

    const cards =
      document.querySelectorAll('.metric-card');

    const values = [
      stats.students,
      stats.clubs,
      stats.companies,
      stats.universities,
      stats.jobs,
      stats.resources
    ];

    cards.forEach((card, index) => {

      const value =
        card.querySelector('.metric-value');

      if (
        value &&
        values[index] !== undefined
      ) {
        value.textContent =
          Number(values[index]).toLocaleString();
      }

    });

  } catch (err) {

    console.error(
      'Admin dashboard error:',
      err
    );

  }

})();
