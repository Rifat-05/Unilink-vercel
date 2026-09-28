(async function () {

  let approvals = [];
  let currentFilter = 'all';

  try {

    // =====================================================
    // 1. VERIFY SUPER ADMIN
    // =====================================================

    const admin = await UniLinkAdminAuth.ready;

    if (!admin) return;


    // =====================================================
    // 2. ADMIN NAME
    // =====================================================

    document
      .querySelectorAll('[data-admin-name]')
      .forEach(el => {
        el.textContent =
          admin.full_name || 'Administrator';
      });


    // =====================================================
    // 3. LOGOUT
    // =====================================================

    const logout =
      document.getElementById('adminLogout');

    if (logout) {
      logout.addEventListener('click', function (e) {
        e.preventDefault();
        UniLinkAdminAuth.logout();
      });
    }


    // =====================================================
    // 4. LOAD REAL DASHBOARD STATISTICS
    // =====================================================

    await loadDashboardStats();


    // =====================================================
    // 5. LOAD REAL PENDING APPROVALS
    // =====================================================

    await loadApprovals();


    // =====================================================
    // 6. APPROVAL FILTER BUTTONS
    // =====================================================

    document
      .querySelectorAll('[data-approval-filter]')
      .forEach(button => {

        button.addEventListener('click', function () {

          currentFilter =
            button.dataset.approvalFilter || 'all';

          document
            .querySelectorAll('[data-approval-filter]')
            .forEach(btn => {
              btn.classList.remove('active');
            });

          button.classList.add('active');

          renderApprovals();
        });

      });
    // =====================================================
    // 7. APPROVE / REJECT BUTTONS
    // =====================================================

    const approvalList =
      document.getElementById('approvalList');

    if (approvalList) {

      approvalList.addEventListener('click', async function (e) {

        const approveButton =
          e.target.closest('[data-approve-id]');

        const rejectButton =
          e.target.closest('[data-reject-id]');


        // APPROVE
        if (approveButton) {

          const approvalId =
            Number(approveButton.dataset.approveId);

          await processApproval(
            approvalId,
            'approve',
            approveButton
          );

          return;
        }


        // REJECT
        if (rejectButton) {

          const approvalId =
            Number(rejectButton.dataset.rejectId);

          await processApproval(
            approvalId,
            'reject',
            rejectButton
          );

        }

      });

    }

  } catch (err) {

    console.error(
      'Admin dashboard error:',
      err
    );

  }



  // =======================================================
  // LOAD DASHBOARD STATISTICS
  // =======================================================

  async function loadDashboardStats() {

    try {

      const result =
        await UniLinkAPI.get('/admin/stats');

      const stats =
        result.stats || {};

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
            Number(values[index] || 0)
              .toLocaleString();

        }

      });

    } catch (err) {

      console.error(
        'Unable to load admin statistics:',
        err
      );

    }

  }



  // =======================================================
  // LOAD APPROVALS
  // =======================================================

  async function loadApprovals() {

    const list =
      document.getElementById('approvalList');

    try {

      const result =
        await UniLinkAPI.get('/admin/approvals');

      approvals =
        Array.isArray(result.items)
          ? result.items
          : [];

      updateApprovalCounts();

      renderApprovals();

    } catch (err) {

      console.error(
        'Unable to load approvals:',
        err
      );

      if (list) {

        list.innerHTML = `
          <div style="
            padding:20px;
            text-align:center;
            color:var(--danger);
          ">
            Unable to load pending approvals.
          </div>
        `;

      }

    }

  }



  // =======================================================
  // UPDATE COUNTS
  // =======================================================

  function updateApprovalCounts() {

    const total =
      approvals.length;

    const companies =
      approvals.filter(
        item => item.entity_type === 'company'
      ).length;

    const clubs =
      approvals.filter(
        item => item.entity_type === 'club'
      ).length;


    // Main action badge
    const actionCount =
      document.getElementById(
        'approvalActionCount'
      );

    if (actionCount) {

      actionCount.textContent =
        total === 1
          ? '1 Action Required'
          : `${total} Actions Required`;

    }


    // Sidebar badge
    const navBadge =
      document.getElementById(
        'approvalNavBadge'
      );

    if (navBadge) {

      navBadge.textContent = total;

      navBadge.style.display =
        total > 0
          ? 'inline-block'
          : 'none';

    }


    // Filter buttons
    const allButton =
      document.querySelector(
        '[data-approval-filter="all"]'
      );

    const companyButton =
      document.querySelector(
        '[data-approval-filter="company"]'
      );

    const clubButton =
      document.querySelector(
        '[data-approval-filter="club"]'
      );


    if (allButton) {
      allButton.textContent =
        `All (${total})`;
    }

    if (companyButton) {
      companyButton.textContent =
        `Companies (${companies})`;
    }

    if (clubButton) {
      clubButton.textContent =
        `Clubs (${clubs})`;
    }

  }



  // =======================================================
  // RENDER APPROVAL QUEUE
  // =======================================================

  function renderApprovals() {

    const list =
      document.getElementById(
        'approvalList'
      );

    if (!list) return;


    let filtered =
      approvals;

    if (currentFilter !== 'all') {

      filtered =
        approvals.filter(
          item =>
            item.entity_type === currentFilter
        );

    }


    // Empty queue
    if (filtered.length === 0) {

      list.innerHTML = `
        <div style="
          padding:24px;
          text-align:center;
          color:var(--text-muted);
          background:#f8fafc;
          border:1px solid var(--border-light);
          border-radius:var(--radius-md);
        ">
          No pending approvals.
        </div>
      `;

      return;

    }


    list.innerHTML =
      filtered
        .map(item => createApprovalCard(item))
        .join('');

  }



  // =======================================================
  // CREATE APPROVAL CARD
  // =======================================================

  function createApprovalCard(item) {

    const isCompany =
      item.entity_type === 'company';

    const categoryClass =
      isCompany
        ? 'tag-category-cyan'
        : 'tag-category-purple';

    const categoryText =
      isCompany
        ? 'Company Account'
        : 'Student Club';


    // Main detail line
    let detail = '';

    if (isCompany) {

      detail = [
        item.company_industry,
        item.description
      ]
        .filter(Boolean)
        .join(' • ');

    } else {

      detail = [
        item.club_category,
        item.university_name
          ? `University: ${item.university_name}`
          : null,
        item.requester_name
          ? `Requester: ${item.requester_name}`
          : null
      ]
        .filter(Boolean)
        .join(' • ');

    }


    // Contact / information line
    let contactInfo = '';

    if (isCompany) {

      const pieces = [];

      if (item.requester_email) {

        pieces.push(`
          ✉
          <a
            href="mailto:${escapeAttribute(item.requester_email)}"
            class="contact-link"
          >
            ${escapeHtml(item.requester_email)}
          </a>
        `);

      }

      if (item.company_website) {

        pieces.push(`
          🌐
          <a
            href="${escapeAttribute(item.company_website)}"
            target="_blank"
            rel="noopener noreferrer"
            class="contact-link"
          >
            ${escapeHtml(item.company_website)}
          </a>
        `);

      }

      if (item.company_location) {

        pieces.push(
          `📍 ${escapeHtml(item.company_location)}`
        );

      }

      contactInfo =
        pieces.join('<span>|</span>');

    } else {

      const pieces = [];

      if (item.requester_email) {

        pieces.push(`
          ✉
          <a
            href="mailto:${escapeAttribute(item.requester_email)}"
            class="contact-link"
          >
            ${escapeHtml(item.requester_email)}
          </a>
        `);

      }

      if (item.university_name) {

        pieces.push(
          `🏛 ${escapeHtml(item.university_name)}`
        );

      }

      contactInfo =
        pieces.join('<span>|</span>');

    }


    return `
      <div
        class="verification-item-card"
        data-approval-id="${Number(item.approval_id)}"
        data-entity-type="${escapeAttribute(item.entity_type)}"
      >

        <div class="item-left-col">

          <div class="item-tags-row">

            <span class="tag-pending-rev">
              ● Pending Review
            </span>

            <span class="${categoryClass}">
              ${categoryText}
            </span>

            <span class="time-subtext">
              ${formatTimeAgo(item.created_at)}
            </span>

          </div>

          <h3 class="item-entity-name">
            ${escapeHtml(
              item.entity_name || 'Unnamed Request'
            )}
          </h3>

          <p class="item-detail-info">
            ${escapeHtml(
              detail || item.description || ''
            )}
          </p>

          <div class="item-contact-bar">
            ${contactInfo}
          </div>

        </div>


        <div class="item-right-actions">

          <button
            class="btn-action-outline"
            type="button"
            data-review-id="${Number(item.approval_id)}"
          >
            Review Details
          </button>

          <button
            class="btn-action-approve"
            type="button"
            data-approve-id="${Number(item.approval_id)}"
          >
            ✓ Approve
          </button>

          <button
            class="btn-action-reject"
            type="button"
            data-reject-id="${Number(item.approval_id)}"
          >
            Reject
          </button>

        </div>

      </div>
    `;

  }



  // =======================================================
  // TIME FORMATTER
  // =======================================================

  function formatTimeAgo(dateValue) {

    if (!dateValue) {
      return '';
    }

    // MySQL DATETIME -> browser-friendly format
    const date =
      new Date(
        String(dateValue).replace(
          ' ',
          'T'
        ) + 'Z'
      );

    if (Number.isNaN(date.getTime())) {
      return '';
    }

    const seconds =
      Math.floor(
        (Date.now() - date.getTime()) / 1000
      );

    if (seconds < 60) {
      return 'Just now';
    }

    const minutes =
      Math.floor(seconds / 60);

    if (minutes < 60) {
      return `${minutes}m ago`;
    }

    const hours =
      Math.floor(minutes / 60);

    if (hours < 24) {
      return `${hours}h ago`;
    }

    const days =
      Math.floor(hours / 24);

    if (days < 30) {
      return `${days}d ago`;
    }

    return date.toLocaleDateString();

  }



  // =======================================================
  // HTML SAFETY
  // =======================================================

  function escapeHtml(value) {

    return String(value ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');

  }


  function escapeAttribute(value) {

    return escapeHtml(value);

  }

})();
