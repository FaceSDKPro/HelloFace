const search = document.querySelector('input');
search.addEventListener('input', () => {
  const value = search.value.trim().toLowerCase();
  document.querySelectorAll('article').forEach(item => {
    item.hidden = !item.textContent.toLowerCase().includes(value);
  });
});
