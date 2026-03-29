(function () {
  var SUPPORTED = ['uk-ua', 'en-us'];
  var DEFAULT_LOCALE = 'uk-ua';
  var STORAGE_KEY = 'lumyn_locale';

  function normalizePath(pathname) {
    var clean = (pathname || '/').replace(/\/+$/, '');
    return clean === '' ? '/' : clean;
  }

  function preferredLocale() {
    try {
      var saved = localStorage.getItem(STORAGE_KEY);
      if (saved && SUPPORTED.indexOf(saved) !== -1) return saved;
    } catch (_) {}

    var lang = (navigator.language || '').toLowerCase();
    return lang.indexOf('en') === 0 ? 'en-us' : DEFAULT_LOCALE;
  }

  function stripLocale(pathname) {
    var path = normalizePath(pathname);
    var seg = path.split('/').filter(Boolean);
    if (seg.length > 0 && SUPPORTED.indexOf(seg[0].toLowerCase()) !== -1) {
      var rest = '/' + seg.slice(1).join('/');
      return normalizePath(rest);
    }
    return path;
  }

  function toRoute(pathname) {
    var p = stripLocale(pathname).toLowerCase();
    if (p === '/' || p === '/index' || p === '/index.html' || p === '/en' || p === '/en.html') return '/';
    if (p === '/download' || p === '/download.html') return '/download';
    if (p === '/faq' || p === '/faq.html') return '/faq';
    if (p === '/support' || p === '/support.html') return '/support';
    return '/';
  }

  function withLocale(route, locale) {
    if (route === '/') return '/' + locale;
    return '/' + locale + route;
  }

  function currentLocale(pathname) {
    var path = normalizePath(pathname);
    var seg = path.split('/').filter(Boolean);
    if (seg.length > 0) {
      var maybe = seg[0].toLowerCase();
      if (SUPPORTED.indexOf(maybe) !== -1) return maybe;
    }
    return null;
  }

  var pathname = window.location.pathname;
  var localeInPath = currentLocale(pathname);
  var route = toRoute(pathname);

  if (!localeInPath) {
    var desired = preferredLocale();
    window.location.replace(withLocale(route, desired));
    return;
  }

  try { localStorage.setItem(STORAGE_KEY, localeInPath); } catch (_) {}

  var html = document.documentElement;
  if (html) html.lang = localeInPath === 'en-us' ? 'en' : 'uk';

  function setupAntiCopyProtection() {
    var styleId = 'lumyn-anti-copy-style';
    if (!document.getElementById(styleId)) {
      var style = document.createElement('style');
      style.id = styleId;
      style.textContent = [
        'html, body { -webkit-touch-callout: none; }',
        'body { user-select: none; -webkit-user-select: none; }',
        'input, textarea, [contenteditable="true"] { user-select: text; -webkit-user-select: text; }'
      ].join('\n');
      document.head.appendChild(style);
    }

    function isEditableTarget(target) {
      if (!target || !target.closest) return false;
      return !!target.closest('input, textarea, [contenteditable="true"]');
    }

    function blockIfNonEditable(e) {
      if (isEditableTarget(e.target)) return;
      e.preventDefault();
    }

    document.addEventListener('copy', blockIfNonEditable);
    document.addEventListener('cut', blockIfNonEditable);
    document.addEventListener('contextmenu', blockIfNonEditable);
    document.addEventListener('selectstart', blockIfNonEditable);
    document.addEventListener('dragstart', blockIfNonEditable);
  }

  function syncActiveNavLinks() {
    var navLinks = document.querySelectorAll('nav a[href], #mobile-dropdown a[href]');
    for (var i = 0; i < navLinks.length; i++) {
      var link = navLinks[i];
      var cls = link.className || '';
      if (cls.indexOf('btn-outline') !== -1) continue;

      var href = link.getAttribute('href');
      if (!href) continue;

      var url;
      try {
        url = new URL(href, window.location.origin);
      } catch (_) {
        continue;
      }

      var linkRoute = toRoute(url.pathname);
      if (linkRoute === route) {
        if (link.classList) link.classList.add('active');
      } else {
        if (link.classList) link.classList.remove('active');
      }
    }
  }

  function rewriteLink(a) {
    var rawHref = a.getAttribute('href');
    if (!rawHref || rawHref.indexOf('http://') === 0 || rawHref.indexOf('https://') === 0 || rawHref.indexOf('mailto:') === 0 || rawHref.indexOf('tel:') === 0 || rawHref.indexOf('#') === 0) {
      return;
    }

    var url;
    try {
      url = new URL(rawHref, window.location.origin);
    } catch (_) {
      return;
    }

    var baseRoute = toRoute(url.pathname);

    var isLanguageSwitch = false;
    var txt = (a.textContent || '').trim();
    if ((a.className || '').indexOf('btn-outline') !== -1) {
      isLanguageSwitch = true;
    } else if (/\b(EN|UA|English|Ukrainian)\b/i.test(txt)) {
      isLanguageSwitch = true;
    }

    if (isLanguageSwitch) {
      var opposite = localeInPath === 'uk-ua' ? 'en-us' : 'uk-ua';
      a.setAttribute('href', withLocale(route, opposite));

      if ((a.className || '').indexOf('btn-outline') !== -1) {
        a.textContent = localeInPath === 'uk-ua' ? 'EN' : 'UA';
      } else {
        a.textContent = localeInPath === 'uk-ua' ? 'EN (English)' : 'UA (Ukrainian)';
      }
      return;
    }

    a.setAttribute('href', withLocale(baseRoute, localeInPath));
  }

  var links = document.querySelectorAll('a[href]');
  for (var i = 0; i < links.length; i++) {
    rewriteLink(links[i]);
  }

  syncActiveNavLinks();
  setupAntiCopyProtection();
})();
