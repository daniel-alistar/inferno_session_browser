'use strict';
(() => {
  const root = document.body.dataset.browserPath;
  const form = document.querySelector('#filters');
  const rowsElement = document.querySelector('#session-rows');
  const status = document.querySelector('#status');
  const error = document.querySelector('#error');
  const params = new URLSearchParams(window.location.search);
  const expanded = new Map();
  const labels = { never_run: 'Never run', queued: 'Queued', running: 'Running', waiting: 'Waiting', cancelling: 'Cancelling', idle: 'Idle' };
  let currentRows = [];
  let busy = false;
  let pending = false;
  let controller;
  let initialized = false;
  let optionsLoaded = false;

  function element(tag, text, className) {
    const node = document.createElement(tag);
    if (text !== undefined) node.textContent = text;
    if (className) node.className = className;
    return node;
  }
  function showError(message) { error.textContent = message; error.hidden = !message; }
  function value(key, fallback) { return params.get(key) || fallback; }
  function page() { return Number(value('page', '1')); }
  function saveUrl() { history.replaceState(null, '', `${location.pathname}${params.size ? `?${params}` : ''}`); }
  function localInput(iso) {
    if (!iso) return '';
    const date = new Date(iso);
    if (Number.isNaN(date.getTime())) return '';
    const offset = date.getTimezoneOffset() * 60000;
    return new Date(date.getTime() - offset).toISOString().slice(0, 19);
  }
  function restoreControls() {
    for (const control of form.elements) {
      if (!control.name) continue;
      control.value = ['from', 'to'].includes(control.name) ? localInput(params.get(control.name)) : value(control.name, control.name === 'date_field' ? 'created_at' : '');
    }
    document.querySelector('#sort').value = value('sort', 'latest_activity');
    document.querySelector('#direction').value = value('direction', 'desc');
    document.querySelector('#page-size').value = value('page_size', '25');
  }
  async function request(path, signal) {
    const response = await fetch(`${root}${path}`, { signal, headers: { Accept: 'application/json' }, cache: 'no-store' });
    let body;
    try { body = await response.json(); } catch (_) { throw new Error('The server returned an unexpected response.'); }
    if (!response.ok) throw new Error(body.error || 'Unable to load sessions.');
    return body;
  }
  async function loadOptions() {
    try {
      const choices = await request('/api/options');
      const suiteControl = form.elements.suite_id;
      const selectedSuite = optionsLoaded ? suiteControl.value : value('suite_id', '');
      suiteControl.replaceChildren(new Option('All suites', ''));
      for (const suite of choices.suites) suiteControl.add(new Option(suite.title, suite.id));
      if (selectedSuite && !choices.suites.some(suite => suite.id === selectedSuite)) suiteControl.add(new Option(selectedSuite, selectedSuite));
      suiteControl.value = selectedSuite;
      const optionContainer = document.querySelector('#option-filters');
      const oldSelections = new Map(Array.from(optionContainer.querySelectorAll('select')).map(control => [control.name, control.value]));
      optionContainer.replaceChildren();
      for (const option of choices.suite_options) {
        const label = element('label', option.title);
        const select = element('select');
        select.name = `suite_options[${option.id}]`;
        select.add(new Option('All versions / values', ''));
        for (const choice of option.values) select.add(new Option(choice.label, choice.value));
        select.value = oldSelections.get(select.name) ?? value(select.name, '');
        label.append(select); optionContainer.append(label);
      }
      document.querySelector('#options-error').textContent = '';
      optionsLoaded = true;
    } catch (_) { document.querySelector('#options-error').textContent = 'Filter choices could not be loaded. Refresh to retry.'; }
  }
  function dateCell(iso) {
    const cell = element('td', undefined, 'time');
    if (!iso) { cell.textContent = '—'; return cell; }
    const date = new Date(iso);
    const time = element('time', date.toLocaleDateString());
    time.dateTime = iso;
    time.title = date.toLocaleString();
    time.append(element('small', date.toLocaleTimeString()));
    cell.append(time); return cell;
  }
  function badge(text, type) { return element('span', text, `badge ${type || ''}`); }
  function countsCell(counts) {
    const cell = element('td');
    const container = element('div', undefined, 'counts');
    for (const [result, count] of Object.entries(counts)) if (count) container.append(badge(`${count} ${result}`, result));
    if (!container.childNodes.length) container.append(element('span', 'No results', 'muted'));
    cell.append(container); return cell;
  }
  function historyPanel(id) {
    const state = expanded.get(id);
    const panel = element('div');
    panel.append(element('p', 'Run history', 'history-title'));
    if (state.error) { const alert = element('p', state.error, 'history-error'); alert.setAttribute('role', 'alert'); panel.append(alert); }
    if (!state.data) { panel.append(element('p', state.error ? 'Use Refresh now to retry.' : 'Loading run history…', 'muted')); return panel; }
    if (!state.data.data.length) { panel.append(element('p', 'This session has no runs.', 'muted')); return panel; }
    const table = element('table', undefined, 'history-table');
    const head = element('thead'); const headRow = element('tr');
    for (const title of ['Run / target', 'Execution status', 'Created', 'Last update', 'Target outcome', 'Test results']) { const th = element('th', title); th.scope = 'col'; headRow.append(th); }
    head.append(headRow); table.append(head);
    const body = element('tbody');
    for (const run of state.data.data) {
      const row = element('tr');
      const target = element('td'); target.append(element('div', run.target.title, 'suite-title'), element('div', `${run.target.type} · ${run.id}`, 'muted')); row.append(target);
      const runState = element('td'); runState.append(badge(run.status, run.status)); row.append(runState, dateCell(run.created_at), dateCell(run.updated_at));
      const outcome = element('td'); outcome.append(run.outcome ? badge(run.outcome, run.outcome) : element('span', '—')); row.append(outcome, countsCell(run.result_counts)); body.append(row);
    }
    table.append(body); panel.append(table);
    const pagination = element('nav', undefined, 'history-pagination'); pagination.setAttribute('aria-label', `Run history pagination for ${id}`);
    const previous = element('button', 'Previous runs'); previous.type = 'button'; previous.disabled = state.page <= 1;
    previous.dataset.focusKey = `runs-previous-${id}`;
    previous.addEventListener('click', () => { state.page--; refresh(); });
    const next = element('button', 'Next runs'); next.type = 'button'; next.disabled = state.page * 25 >= state.data.pagination.total;
    next.dataset.focusKey = `runs-next-${id}`;
    next.addEventListener('click', () => { state.page++; refresh(); });
    pagination.append(previous, element('span', `Page ${state.page} · ${state.data.pagination.total} runs`, 'muted'), next); panel.append(pagination);
    return panel;
  }
  function renderRows() {
    const focusKey = document.activeElement?.dataset.focusKey;
    rowsElement.replaceChildren();
    if (!currentRows.length) { const row = element('tr'); const cell = element('td', 'No sessions match these filters.', 'empty-row'); cell.colSpan = 9; row.append(cell); rowsElement.append(row); return; }
    for (const session of currentRows) {
      const row = element('tr'); row.dataset.sessionId = session.id;
      row.append(element('td', session.id, 'session-id'));
      const suite = element('td'); suite.append(element('div', session.suite_title, 'suite-title'));
      for (const option of session.suite_options) suite.append(element('div', `${option.title}: ${option.label}`, 'suite-options'));
      if (!session.suite_available) suite.append(element('div', 'Suite unavailable', 'muted'));
      row.append(suite, element('td', session.fhir_url || '—', 'fhir-url'), dateCell(session.created_at), dateCell(session.latest_activity));
      const state = element('td'); state.append(badge(labels[session.state] || session.state, session.state)); row.append(state, element('td', session.run_count), countsCell(session.result_counts));
      const actions = element('td', undefined, 'actions');
      if (session.session_url) { const link = element('a', 'Open session'); link.href = session.session_url; actions.append(link); }
      const expand = element('button', expanded.has(session.id) ? 'Hide history' : 'Run history', 'expand-button');
      expand.type = 'button'; expand.dataset.focusKey = `expand-${session.id}`;
      expand.setAttribute('aria-expanded', String(expanded.has(session.id))); expand.setAttribute('aria-controls', `history-${session.id}`);
      expand.addEventListener('click', () => {
        if (expanded.has(session.id)) expanded.delete(session.id); else expanded.set(session.id, { page: 1, data: null, error: null });
        renderRows(); if (expanded.has(session.id)) refresh();
      });
      actions.append(expand); row.append(actions); rowsElement.append(row);
      if (expanded.has(session.id)) { const historyRow = element('tr'); const cell = element('td', undefined, 'history-cell'); cell.colSpan = 9; cell.id = `history-${session.id}`; cell.append(historyPanel(session.id)); historyRow.append(cell); rowsElement.append(historyRow); }
    }
    if (focusKey) rowsElement.querySelector(`[data-focus-key="${CSS.escape(focusKey)}"]`)?.focus({ preventScroll: true });
  }
  async function refresh() {
    if (busy) { pending = true; return; }
    busy = true; pending = false;
    controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15000);
    const query = params.toString();
    const table = document.querySelector('#sessions-table'); table.setAttribute('aria-busy', 'true');
    if (!initialized) status.textContent = 'Loading sessions…';
    try {
      const response = await request(`/api/sessions?${query}`, controller.signal);
      if (query !== params.toString()) { pending = true; return; }
      currentRows = response.data; initialized = true; showError('');
      const total = response.pagination.total;
      const start = total && currentRows.length ? (response.pagination.page - 1) * response.pagination.page_size + 1 : 0;
      status.textContent = `Showing ${start}–${start ? start + currentRows.length - 1 : 0} of ${total} sessions`;
      document.querySelector('#page-number').textContent = `Page ${response.pagination.page}`;
      document.querySelector('#previous-page').disabled = page() <= 1;
      document.querySelector('#next-page').disabled = page() * response.pagination.page_size >= total;
      renderRows();
      await Promise.all(currentRows.filter(session => expanded.has(session.id)).map(async session => {
        const state = expanded.get(session.id); const requestedPage = state.page;
        try {
          const result = await request(`/api/sessions/${encodeURIComponent(session.id)}/runs?page=${requestedPage}`, controller.signal);
          if (expanded.get(session.id) === state && state.page === requestedPage) { state.data = result; state.error = null; }
        } catch (failure) { if (expanded.get(session.id) === state) state.error = failure.name === 'AbortError' ? 'Run history refresh timed out.' : failure.message; }
      }));
      if (query === params.toString()) renderRows();
    } catch (failure) { showError(failure.name === 'AbortError' ? 'Refresh timed out. Use Refresh now to retry.' : failure.message); if (!initialized) status.textContent = 'Sessions could not be loaded.'; }
    finally { clearTimeout(timeout); busy = false; table.setAttribute('aria-busy', 'false'); if (pending && !document.hidden) refresh(); }
  }
  function change(key, selected, resetPage = true) {
    if (selected) params.set(key, selected); else params.delete(key);
    if (resetPage) params.set('page', '1');
    saveUrl(); restoreControls(); refresh();
  }
  form.addEventListener('submit', event => {
    event.preventDefault();
    const next = new URLSearchParams();
    for (const [key, entered] of new FormData(form)) {
      if (!entered) continue;
      next.set(key, ['from', 'to'].includes(key) ? new Date(entered).toISOString() : entered);
    }
    for (const key of ['sort', 'direction', 'page_size']) if (params.has(key)) next.set(key, params.get(key));
    next.set('page', '1');
    // Clear via a key snapshot: deleting while iterating URLSearchParams skips adjacent keys.
    for (const key of Array.from(params.keys())) params.delete(key);
    next.forEach((entry, key) => params.set(key, entry)); saveUrl(); refresh();
  });
  document.querySelector('#clear-filters').addEventListener('click', () => { for (const key of Array.from(params.keys())) params.delete(key); form.reset(); restoreControls(); saveUrl(); refresh(); });
  document.querySelector('#sort').addEventListener('change', event => change('sort', event.target.value));
  document.querySelector('#direction').addEventListener('change', event => change('direction', event.target.value));
  document.querySelector('#page-size').addEventListener('change', event => change('page_size', event.target.value));
  document.querySelector('#previous-page').addEventListener('click', () => change('page', String(page() - 1), false));
  document.querySelector('#next-page').addEventListener('click', () => change('page', String(page() + 1), false));
  document.querySelectorAll('[data-sort]').forEach(button => button.addEventListener('click', () => {
    params.set('direction', value('sort', 'latest_activity') === button.dataset.sort && value('direction', 'desc') === 'desc' ? 'asc' : 'desc');
    change('sort', button.dataset.sort);
  }));
  document.querySelector('#refresh').addEventListener('click', () => { loadOptions(); refresh(); });
  document.addEventListener('visibilitychange', () => { if (!document.hidden && document.querySelector('#auto-refresh').checked) refresh(); });
  window.addEventListener('popstate', () => { for (const key of Array.from(params.keys())) params.delete(key); new URLSearchParams(location.search).forEach((entry, key) => params.set(key, entry)); restoreControls(); refresh(); });
  setInterval(() => { if (!document.hidden && document.querySelector('#auto-refresh').checked) refresh(); }, 10000);
  restoreControls(); loadOptions(); refresh();
})();
