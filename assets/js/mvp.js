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
    try { return await fn(); }
    catch (e) { showNotice(e.message || 'Something went wrong.'); return null; }
  };
  const el = (tag, text, parent = app, className = '') => {
    const n = document.createElement(tag);
    if (text !== undefined && text !== null) n.textContent = text;
    if (className) n.className = className;
    parent.append(n);
    return n;
  };
  const button = (text, parent, fn, className='') => {
    const b = el('button', text, parent, className);
    b.type = 'button';
    b.addEventListener('click', () => run(async () => {
      b.disabled = true;
      try { await fn(); } finally { b.disabled = false; }
    }));
    return b;
  };
  const field = (form, name, title, value = '', type = 'text') => {
    const label = el('label', title, form);
    const n = document.createElement(type === 'textarea' ? 'textarea' : 'input');
    n.name = name;
    n.value = value ?? '';
    if (type !== 'textarea') n.type = type;
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
        try { await fn(Object.fromEntries(new FormData(f)), f); }
        finally { submit.disabled = false; }
      });
    });
    return f;
  };
  const list = async (box, path, empty, render) => {
    box.replaceChildren();
    const result = await api.get(path);
    const items = Array.isArray(result.items) ? result.items : [];
    if (!items.length) el('p', empty, box, 'empty-state');
    items.forEach(item => render(item, el('article', undefined, box)));
    return items;
  };
  const formatDate = value => {
    if (!value) return '';
    const d = new Date(String(value).replace(' ', 'T') + (String(value).includes('Z') ? '' : 'Z'));
    return Number.isNaN(d.getTime()) ? String(value) : d.toLocaleString();
  };

  let me;
  try { me = await UniLinkAuth.ready; }
  catch (e) { showNotice(e.message); return; }
  if (!me) return;
  showNotice('');

  const page = document.body.dataset.page;

  if (page === 'feed') {
    const intro = el('section', undefined);
    el('h2', `Welcome, ${me.full_name}`, intro);
    el('p', 'Share an update with your campus community. Posts are stored in the database.', intro);
    const f = makeForm(app, 'Publish post', async (data, form) => {
      await api.post('/posts', data);
      form.reset();
      showNotice('Post published.', 'success');
      await refresh();
    });
    const input = field(f, 'content', 'What would you like to share?', '', 'textarea');
    input.required = true; input.maxLength = 5000;
    const box = el('div');
    const refresh = () => list(box, '/posts', 'No posts yet. Be the first to post.', (p, c) => {
      el('strong', p.author_name || 'Student', c);
      el('p', p.content, c);
      el('small', formatDate(p.created_at), c);
    });
    await run(refresh);
  }

  if (page === 'profile') {
    const result = await run(() => api.get('/profile'));
    if (!result) return;
    const p = result.profile || {};
    const summary = el('section');
    el('h2', p.full_name || me.full_name, summary);
    el('p', p.email || me.email, summary);
    el('p', `Student ID: ${p.student_id || '—'}`, summary);
    const f = makeForm(app, 'Save profile', async data => {
      await api.patch('/profile', data);
      showNotice('Profile saved.', 'success');
    });
    const fields = [
      ['department','Department'],['semester','Semester'],['location','Location'],['bio','Bio','textarea'],
      ['github_url','GitHub URL'],['linkedin_url','LinkedIn URL'],['portfolio_url','Portfolio URL']
    ];
    fields.forEach(([key,label,type]) => field(f,key,label,p[key] || '',type || 'text'));
  }

  if (page === 'partners') {
    const searchForm = makeForm(app, 'Search students', async data => search(data.q || ''));
    const q = field(searchForm, 'q', 'Search by name, student ID or department');
    q.placeholder = 'e.g. CSE, 2026-123, Samira';
    const results = el('div');
    el('h2', 'Incoming requests');
    const requests = el('div');
    el('h2', 'Your connections');
    const connections = el('div');

    const message = async id => {
      const c = await api.post('/conversations', { user_id: id });
      location.href = 'unilink_direct_messaging.html?conversation=' + encodeURIComponent(c.conversation_id);
    };
    const search = term => list(results, '/users/search?q=' + encodeURIComponent(term), 'No students found.', (p, c) => {
      el('strong', p.full_name || 'Student', c);
      el('p', [p.student_id, p.department, p.semester].filter(Boolean).join(' · '), c);
      if (p.bio) el('p', p.bio, c);
      button('Connect', c, async () => {
        await api.post('/connections/request', { user_id: p.user_id });
        showNotice(`Connection request sent to ${p.full_name}.`, 'success');
        await refreshConnections();
      });
      button('Message', c, () => message(p.user_id));
    });
    const refreshConnections = async () => {
      await list(requests, '/connections/requests', 'No incoming requests.', (p, c) => {
        el('strong', p.sender_name || 'Student', c);
        if (p.message) el('p', p.message, c);
        button('Accept', c, async () => {
          await api.patch('/connections/' + p.request_id, { status: 'accepted' });
          showNotice('Connection accepted.', 'success');
          await refreshConnections();
        });
        button('Reject', c, async () => {
          await api.patch('/connections/' + p.request_id, { status: 'declined' });
          showNotice('Request rejected.', 'success');
          await refreshConnections();
        });
      });
      await list(connections, '/connections', 'No connections yet.', (p, c) => {
        el('strong', p.full_name || 'Student', c);
        button('Message', c, () => message(p.user_id));
      });
    };
    await run(() => search(''));
    await run(refreshConnections);
  }

  if (page === 'messages') {
    el('p', 'Start a conversation from Study Partners, or choose one below. Messages persist after refresh.');
    const layout = el('div', undefined, app, 'message-layout');
    const left = el('section', undefined, layout);
    const right = el('section', undefined, layout);
    el('h2', 'Conversations', left);
    const conversations = el('div', undefined, left);
    const title = el('h2', 'Choose a conversation', right);
    const messages = el('div', undefined, right, 'message-thread');
    let active = new URLSearchParams(location.search).get('conversation');

    const f = makeForm(right, 'Send message', async (data, form) => {
      if (!active) throw new Error('Choose a conversation first.');
      await api.post('/conversations/' + active + '/messages', data);
      form.reset();
      await loadMessages();
    });
    const body = field(f, 'body', 'Message', '', 'textarea');
    body.required = true; body.maxLength = 10000;

    const loadMessages = async () => {
      if (!active) { messages.replaceChildren(); el('p', 'Select a conversation to view messages.', messages, 'empty-state'); return; }
      await list(messages, '/conversations/' + active + '/messages', 'No messages yet.', (m, c) => {
        const mine = Number(m.sender_id) === Number(me.user_id);
        c.classList.add(mine ? 'message-mine' : 'message-other');
        el('strong', mine ? 'You' : (m.sender_name || 'Student'), c);
        el('p', m.body, c);
        el('small', formatDate(m.created_at), c);
      });
      messages.lastElementChild?.scrollIntoView({ block: 'nearest' });
    };
    const refreshConversations = () => list(conversations, '/conversations', 'No conversations yet.', (c, row) => {
      const b = button(c.participant_name || 'Conversation', row, async () => {
        active = String(c.conversation_id);
        title.textContent = c.participant_name || 'Conversation';
        history.replaceState(null, '', '?conversation=' + encodeURIComponent(active));
        await loadMessages();
      });
      if (String(c.conversation_id) === String(active)) b.setAttribute('aria-current','true');
    });
    await run(refreshConversations);
    await run(loadMessages);
    let polling = false;
    setInterval(async () => {
      if (document.hidden || polling) return;
      polling = true;
      try { await refreshConversations(); await loadMessages(); }
      catch (e) { showNotice(e.message); }
      finally { polling = false; }
    }, 4000);
  }

  if (page === 'resources') {
    const f = document.createElement('form');
    app.append(f);
    const title = field(f, 'title', 'Title'); title.required = true; title.maxLength = 200;
    field(f, 'description', 'Description', '', 'textarea');
    const file = field(f, 'file', 'PDF, DOCX or PPTX (maximum 4 MB online)', '', 'file');
    file.accept = '.pdf,.docx,.pptx'; file.required = true;
    const submit = el('button', 'Upload resource', f); submit.type = 'submit';
    f.addEventListener('submit', e => run(async () => {
      e.preventDefault(); submit.disabled = true;
      try {
        await api.post('/resources', new FormData(f));
        f.reset(); showNotice('Resource uploaded.', 'success'); await refresh();
      } finally { submit.disabled = false; }
    }));
    const box = el('div');
    const refresh = () => list(box, '/resources', 'No resources yet.', (r, c) => {
      el('h2', r.title, c);
      if (r.description) el('p', r.description, c);
      el('small', `${r.uploader || 'Student'} · ${r.course_code || 'GENERAL'} · ${formatDate(r.created_at)}`, c);
      const a = el('a', 'Download', c); a.href = api.url('/resources/' + encodeURIComponent(r.resource_id) + '/download');
    });
    await run(refresh);
  }
})();
