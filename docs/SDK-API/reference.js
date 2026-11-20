const search = document.querySelector('[data-api-search]');
const languageLink = document.querySelector('.language-switch a');
if (languageLink) {
  languageLink.addEventListener('click', () => { languageLink.hash = location.hash; });
}
if (search) {
  const entries = [...document.querySelectorAll('.api-entry')];
  const status = document.querySelector('[data-result-count]');
  const empty = document.querySelector('.search-empty');
  search.addEventListener('input', () => {
    const query = search.value.trim().toLowerCase();
    let count = 0;
    entries.forEach(entry => {
      entry.hidden = !entry.textContent.toLowerCase().includes(query);
      if (!entry.hidden) count++;
    });
    document.querySelectorAll('.api-group').forEach(group => {
      group.hidden = ![...group.querySelectorAll('.api-entry')].some(entry => !entry.hidden);
    });
    status.textContent = `${count} / ${entries.length} ${status.dataset.label}`;
    empty.hidden = count !== 0;
  });
  document.addEventListener('keydown', event => {
    if (event.key === '/' && !['INPUT','TEXTAREA'].includes(document.activeElement.tagName)) {
      event.preventDefault(); search.focus();
    }
  });
}
