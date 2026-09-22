// Gallery lightbox on top of a native <dialog>; the gallery works as plain links without JS.
(() => {
  const dialog = document.querySelector('.lightbox');
  if (!dialog || typeof dialog.showModal !== 'function') return;
  const img = dialog.querySelector('img');
  const caption = dialog.querySelector('figcaption');
  let opener = null;

  document.querySelectorAll('[data-lightbox]').forEach((link) => {
    link.addEventListener('click', (event) => {
      event.preventDefault();
      opener = link;
      const source = link.querySelector('img');
      img.src = link.href;
      img.alt = source ? source.alt : '';
      caption.textContent = link.querySelector('.cap')?.textContent ?? '';
      dialog.showModal();
    });
  });

  const close = () => dialog.close();
  dialog.querySelector('.close').addEventListener('click', close);
  dialog.addEventListener('click', (event) => { if (event.target === dialog) close(); });
  dialog.addEventListener('close', () => { img.removeAttribute('src'); opener?.focus(); });
})();
