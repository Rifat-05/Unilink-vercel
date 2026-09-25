(async () => {
  const api = UniLinkAPI;
  const app = document.getElementById('app');
  const notice = document.getElementById('notice');
  if (!app || !notice) return;

  const showNotice = (message = '', kind = 'error') => {
    notice.textContent = message;
    notice.dataset.kind = message ? kind : '';
  };

  const run = async fn => {
    showNotice('');
    try {
      return await fn();
    } catch (e) {
      showNotice(e.message || 'Something went wrong.');
      return null;
    }
  };

  const el = (tag, text, parent = app, className = '') => {
    const n = document.createElement(tag);

    if (text !== undefined && text !== null) {
      n.textContent = text;
    }

    if (className) {
      n.className = className;
    }

    parent.append(n);
    return n;
  };

  const button = (text, parent, fn, className = '') => {
    const b = el('button', text, parent, className);
    b.type = 'button';

    b.addEventListener('click', () =>
      run(async () => {
        b.disabled = true;

        try {
          await fn();
        } finally {
          b.disabled = false;
        }
      })
    );

    return b;
  };

  const field = (
    form,
    name,
    title,
    value = '',
    type = 'text'
  ) => {
    const label = el('label', title, form);

    const n = document.createElement(
      type === 'textarea' ? 'textarea' : 'input'
    );

    n.name = name;
    n.value = value ?? '';

    if (type !== 'textarea') {
      n.type = type;
    }

    label.append(n);

    return n;
  };

  const makeForm = (parent, caption, fn) => {
    const f = el('form', undefined, parent);

    const submit = el('button', caption, f);
    submit.type = 'submit';

    f.addEventListener('submit', e => {
      e.preventDefault();

      run(async () => {
        submit.disabled = true;

        try {
          await fn(
            Object.fromEntries(new FormData(f)),
            f
          );
        } finally {
          submit.disabled = false;
        }
      });
    });

    return f;
  };

  const list = async (
    box,
    path,
    empty,
    render
  ) => {
    box.replaceChildren();

    const result = await api.get(path);

    const items = Array.isArray(result.items)
      ? result.items
      : [];

    if (!items.length) {
      el('p', empty, box, 'empty-state');
    }

    items.forEach(item =>
      render(
        item,
        el('article', undefined, box)
      )
    );

    return items;
  };

  const formatDate = value => {
    if (!value) return '';

    const d = new Date(
      String(value).replace(' ', 'T') +
      (String(value).includes('Z') ? '' : 'Z')
    );

    return Number.isNaN(d.getTime())
      ? String(value)
      : d.toLocaleString();
  };

  let me;

  try {
    me = await UniLinkAuth.ready;
  } catch (e) {
    showNotice(e.message);
    return;
  }

  if (!me) return;

  showNotice('');

  const page = document.body.dataset.page;

  // =========================================================
  // FEED
  // =========================================================

  if (page === 'feed') {
    const intro = el('section', undefined);

    el(
      'h2',
      `Welcome, ${me.full_name}`,
      intro
    );

    el(
      'p',
      'Share an update with your campus community. Posts are stored in the database.',
      intro
    );

    const f = makeForm(
      app,
      'Publish post',
      async (data, form) => {
        await api.post('/posts', data);

        form.reset();

        showNotice(
          'Post published.',
          'success'
        );

        await refresh();
      }
    );

    const input = field(
      f,
      'content',
      'What would you like to share?',
      '',
      'textarea'
    );

    input.required = true;
    input.maxLength = 5000;

    const box = el('div');

    const refresh = () =>
      list(
        box,
        '/posts',
        'No posts yet. Be the first to post.',
        (p, c) => {
          el(
            'strong',
            p.author_name || 'Student',
            c
          );

          el('p', p.content, c);

          el(
            'small',
            formatDate(p.created_at),
            c
          );
        }
      );

    await run(refresh);
  }

  // =========================================================
  // PROFILE
  // =========================================================

  if (page === 'profile') {
    const result = await run(() =>
      api.get('/profile')
    );

    if (!result) return;

    const p = result.profile || {};

    const summary = el('section');

    el(
      'h2',
      p.full_name || me.full_name,
      summary
    );

    el(
      'p',
      p.email || me.email,
      summary
    );

    el(
      'p',
      `Student ID: ${p.student_id || '—'}`,
      summary
    );

    const f = makeForm(
      app,
      'Save profile',
      async data => {
        await api.patch(
          '/profile',
          data
        );

        showNotice(
          'Profile saved.',
          'success'
        );
      }
    );

    const fields = [
      ['department', 'Department'],
      ['semester', 'Semester'],
      ['location', 'Location'],
      ['bio', 'Bio', 'textarea'],
      ['github_url', 'GitHub URL'],
      ['linkedin_url', 'LinkedIn URL'],
      ['portfolio_url', 'Portfolio URL']
    ];

    fields.forEach(
      ([key, label, type]) =>
        field(
          f,
          key,
          label,
          p[key] || '',
          type || 'text'
        )
    );
  }

  // =========================================================
  // STUDY PARTNERS
  // =========================================================

  if (page === 'partners') {
    const searchForm = makeForm(
      app,
      'Search students',
      async data =>
        search(data.q || '')
    );

    const q = field(
      searchForm,
      'q',
      'Search by name, student ID or department'
    );

    q.placeholder =
      'e.g. CSE, 2026-123, Samira';

    const results = el('div');

    el('h2', 'Incoming requests');

    const requests = el('div');

    el('h2', 'Your connections');

    const connections = el('div');

    const message = async id => {
      const c = await api.post(
        '/conversations',
        {
          user_id: id
        }
      );

      location.href =
        'unilink_direct_messaging.html?conversation=' +
        encodeURIComponent(
          c.conversation_id
        );
    };

    const search = term =>
      list(
        results,
        '/users/search?q=' +
        encodeURIComponent(term),
        'No students found.',
        (p, c) => {
          el(
            'strong',
            p.full_name || 'Student',
            c
          );

          el(
            'p',
            [
              p.student_id,
              p.department,
              p.semester
            ]
              .filter(Boolean)
              .join(' · '),
            c
          );

          if (p.bio) {
            el('p', p.bio, c);
          }

          button(
            'Connect',
            c,
            async () => {
              await api.post(
                '/connections/request',
                {
                  user_id: p.user_id
                }
              );

              showNotice(
                `Connection request sent to ${p.full_name}.`,
                'success'
              );

              await refreshConnections();
            }
          );

          button(
            'Message',
            c,
            () => message(p.user_id)
          );
        }
      );

    const refreshConnections =
      async () => {
        await list(
          requests,
          '/connections/requests',
          'No incoming requests.',
          (p, c) => {
            el(
              'strong',
              p.sender_name || 'Student',
              c
            );

            if (p.message) {
              el('p', p.message, c);
            }

            button(
              'Accept',
              c,
              async () => {
                await api.patch(
                  '/connections/' +
                  p.request_id,
                  {
                    status: 'accepted'
                  }
                );

                showNotice(
                  'Connection accepted.',
                  'success'
                );

                await refreshConnections();
              }
            );

            button(
              'Reject',
              c,
              async () => {
                await api.patch(
                  '/connections/' +
                  p.request_id,
                  {
                    status: 'declined'
                  }
                );

                showNotice(
                  'Request rejected.',
                  'success'
                );

                await refreshConnections();
              }
            );
          }
        );

        await list(
          connections,
          '/connections',
          'No connections yet.',
          (p, c) => {
            el(
              'strong',
              p.full_name || 'Student',
              c
            );

            button(
              'Message',
              c,
              () => message(p.user_id)
            );
          }
        );
      };

    await run(() => search(''));

    await run(
      refreshConnections
    );
  }

  // =========================================================
  // MESSAGES
  // =========================================================

  if (page === 'messages') {
    el(
      'p',
      'Start a conversation from Study Partners, or choose one below. Messages persist after refresh.'
    );

    const layout = el(
      'div',
      undefined,
      app,
      'message-layout'
    );

    const left = el(
      'section',
      undefined,
      layout
    );

    const right = el(
      'section',
      undefined,
      layout
    );

    el(
      'h2',
      'Conversations',
      left
    );

    const conversations = el(
      'div',
      undefined,
      left
    );

    const title = el(
      'h2',
      'Choose a conversation',
      right
    );

    const messages = el(
      'div',
      undefined,
      right,
      'message-thread'
    );

    let active =
      new URLSearchParams(
        location.search
      ).get('conversation');

    let polling = false;

    // -------------------------------------------------------
    // RENDER MESSAGE
    // -------------------------------------------------------

    const renderMessage = (
      m,
      temporary = false
    ) => {
      const c = el(
        'article',
        undefined,
        messages
      );

      if (
        m.message_id !== undefined &&
        m.message_id !== null
      ) {
        c.dataset.messageId =
          String(m.message_id);
      }

      if (temporary) {
        c.dataset.temporary = 'true';
      }

      const mine =
        Number(m.sender_id) ===
        Number(me.user_id);

      c.classList.add(
        mine
          ? 'message-mine'
          : 'message-other'
      );

      el(
        'strong',
        mine
          ? 'You'
          : (
              m.sender_name ||
              'Student'
            ),
        c
      );

      el(
        'p',
        m.body,
        c
      );

      el(
        'small',
        temporary
          ? 'Sending...'
          : formatDate(
              m.created_at
            ),
        c
      );

      return c;
    };

    // -------------------------------------------------------
    // LOAD MESSAGES
    // -------------------------------------------------------

    const loadMessages =
      async () => {
        if (!active) {
          messages.replaceChildren();

          el(
            'p',
            'Select a conversation to view messages.',
            messages,
            'empty-state'
          );

          return;
        }

        const requestedConversation =
          String(active);

        const result =
          await api.get(
            '/conversations/' +
            encodeURIComponent(
              requestedConversation
            ) +
            '/messages'
          );

        // Prevent an old request from overwriting
        // a conversation the user just switched to.
        if (
          String(active) !==
          requestedConversation
        ) {
          return;
        }

        const items =
          Array.isArray(result.items)
            ? result.items
            : [];

        messages.replaceChildren();

        if (!items.length) {
          el(
            'p',
            'No messages yet.',
            messages,
            'empty-state'
          );
        } else {
          items.forEach(m =>
            renderMessage(m)
          );
        }

        messages
          .lastElementChild
          ?.scrollIntoView({
            block: 'nearest'
          });
      };

    // -------------------------------------------------------
    // SEND MESSAGE - INSTANT DISPLAY
    // -------------------------------------------------------

    const f = makeForm(
      right,
      'Send message',
      async (data, form) => {
        if (!active) {
          throw new Error(
            'Choose a conversation first.'
          );
        }

        const text =
          String(
            data.body || ''
          ).trim();

        if (!text) {
          throw new Error(
            'Message is required.'
          );
        }

        // Remember which conversation
        // this message belongs to.
        const conversationAtSend =
          String(active);

        // Remove empty message notice.
        const empty =
          messages.querySelector(
            '.empty-state'
          );

        if (empty) {
          empty.remove();
        }

        // Temporary ID used until MySQL
        // confirms the real message.
        const tempId =
          'temp-' +
          Date.now() +
          '-' +
          Math.random()
            .toString(36)
            .slice(2);

        // Display immediately.
        const tempMessage =
          renderMessage(
            {
              message_id: tempId,
              sender_id: me.user_id,
              sender_name: me.full_name,
              body: text,
              created_at:
                new Date()
                  .toISOString()
            },
            true
          );

        const status =
          tempMessage.querySelector(
            'small'
          );

        // Clear textarea immediately.
        form.reset();

        tempMessage.scrollIntoView({
          block: 'nearest',
          behavior: 'smooth'
        });

        try {
          // Save to MySQL.
          const result =
            await api.post(
              '/conversations/' +
              encodeURIComponent(
                conversationAtSend
              ) +
              '/messages',
              {
                body: text
              }
            );

          // Replace temporary ID with
          // database message ID.
          if (
            result.message_id !==
              undefined &&
            result.message_id !== null
          ) {
            tempMessage.dataset.messageId =
              String(
                result.message_id
              );
          }

          delete tempMessage
            .dataset.temporary;

          if (status) {
            status.textContent =
              'Sent';
          }
        } catch (e) {
          // Remove optimistic message
          // if saving failed.
          tempMessage.remove();

          // Restore text if user is still
          // in the same conversation.
          if (
            String(active) ===
            conversationAtSend
          ) {
            const input =
              form.querySelector(
                '[name="body"]'
              );

            if (input) {
              input.value = text;
              input.focus();
            }
          }

          throw e;
        }
      }
    );

    const body = field(
      f,
      'body',
      'Message',
      '',
      'textarea'
    );

    body.required = true;
    body.maxLength = 10000;

    // -------------------------------------------------------
    // CONVERSATION LIST
    // -------------------------------------------------------

    const refreshConversations =
      () =>
        list(
          conversations,
          '/conversations',
          'No conversations yet.',
          (c, row) => {
            const b = button(
              c.participant_name ||
              'Conversation',
              row,
              async () => {
                active =
                  String(
                    c.conversation_id
                  );

                title.textContent =
                  c.participant_name ||
                  'Conversation';

                history.replaceState(
                  null,
                  '',
                  '?conversation=' +
                  encodeURIComponent(
                    active
                  )
                );

                await loadMessages();
              }
            );

            if (
              String(
                c.conversation_id
              ) ===
              String(active)
            ) {
              b.setAttribute(
                'aria-current',
                'true'
              );
            }
          }
        );

    // -------------------------------------------------------
    // CHECK FOR NEW INCOMING MESSAGES
    // -------------------------------------------------------

    const checkNewMessages =
      async () => {
        if (
          !active ||
          document.hidden ||
          polling
        ) {
          return;
        }

        polling = true;

        const requestedConversation =
          String(active);

        try {
          const result =
            await api.get(
              '/conversations/' +
              encodeURIComponent(
                requestedConversation
              ) +
              '/messages'
            );

          // Conversation changed while
          // request was running.
          if (
            String(active) !==
            requestedConversation
          ) {
            return;
          }

          const items =
            Array.isArray(
              result.items
            )
              ? result.items
              : [];

          // Collect IDs already displayed.
          const existingIds =
            new Set(
              Array.from(
                messages
                  .querySelectorAll(
                    '[data-message-id]'
                  )
              ).map(
                node =>
                  String(
                    node.dataset
                      .messageId
                  )
              )
            );

          let added = false;

          items.forEach(m => {
            const id =
              String(
                m.message_id
              );

            // Already displayed.
            if (
              existingIds.has(id)
            ) {
              return;
            }

            const empty =
              messages
                .querySelector(
                  '.empty-state'
                );

            if (empty) {
              empty.remove();
            }

            // Append ONLY the new message.
            renderMessage(m);

            existingIds.add(id);

            added = true;
          });

          // Scroll only when a new
          // message actually arrived.
          if (added) {
            messages
              .lastElementChild
              ?.scrollIntoView({
                block: 'nearest',
                behavior: 'smooth'
              });
          }
        } catch (e) {
          console.error(
            'Message polling failed:',
            e
          );
        } finally {
          polling = false;
        }
      };

    // Initial page load.
    await run(
      refreshConversations
    );

    await run(
      loadMessages
    );

    // Check for incoming messages every 2 seconds.
    // This DOES NOT rebuild the whole thread.
    setInterval(
      checkNewMessages,
      2000
    );
  }

  // =========================================================
  // RESOURCES
  // =========================================================

  if (page === 'resources') {
    const f =
      document.createElement(
        'form'
      );

    app.append(f);

    const title = field(
      f,
      'title',
      'Title'
    );

    title.required = true;
    title.maxLength = 200;

    field(
      f,
      'description',
      'Description',
      '',
      'textarea'
    );

    const file = field(
      f,
      'file',
      'PDF, DOCX or PPTX (maximum 4 MB online)',
      '',
      'file'
    );

    file.accept =
      '.pdf,.docx,.pptx';

    file.required = true;

    const submit = el(
      'button',
      'Upload resource',
      f
    );

    submit.type = 'submit';

    f.addEventListener(
      'submit',
      e =>
        run(async () => {
          e.preventDefault();

          submit.disabled = true;

          try {
            await api.post(
              '/resources',
              new FormData(f)
            );

            f.reset();

            showNotice(
              'Resource uploaded.',
              'success'
            );

            await refresh();
          } finally {
            submit.disabled =
              false;
          }
        })
    );

    const box = el('div');

    const refresh = () =>
      list(
        box,
        '/resources',
        'No resources yet.',
        (r, c) => {
          el(
            'h2',
            r.title,
            c
          );

          if (r.description) {
            el(
              'p',
              r.description,
              c
            );
          }

          el(
            'small',
            `${
              r.uploader ||
              'Student'
            } · ${
              r.course_code ||
              'GENERAL'
            } · ${formatDate(
              r.created_at
            )}`,
            c
          );

          const a = el(
            'a',
            'Download',
            c
          );

          a.href =
            api.url(
              '/resources/' +
              encodeURIComponent(
                r.resource_id
              ) +
              '/download'
            );
        }
      );

    await run(refresh);
  }
})();
