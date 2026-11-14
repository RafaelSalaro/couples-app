// W3 motion engine (docs/09 §10). One small script for the whole site:
//   --s on .sky            page scroll progress, 0 to 1 (drives the two lights and the ambient warmth)
//   --t on [data-scrub]    progress of that element through the viewport, 0 to 1
//   .is-in on [data-inview] added once when the element is on screen (one-shot entrances)
//   --mx / --my on [data-light] pointer position for the soft light on cards (mouse only)
// Without JavaScript, or with reduced motion, CSS shows every element in its finished state.
const root = document.documentElement;
const reduced = matchMedia('(prefers-reduced-motion: reduce)');

function start() {
  const sky = document.querySelector<HTMLElement>('.sky');
  const scrubs = new Set<HTMLElement>();
  let ticking = false;

  const update = () => {
    ticking = false;
    const vh = innerHeight;
    const max = root.scrollHeight - vh;
    const y = scrollY;
    sky?.style.setProperty('--s', (max > 0 ? Math.min(1, Math.max(0, y / max)) : 0).toFixed(4));
    root.toggleAttribute('data-scrolled', y > 12);
    for (const el of scrubs) {
      const rect = el.getBoundingClientRect();
      const t = (vh - rect.top) / (vh + rect.height);
      el.style.setProperty('--t', Math.min(1, Math.max(0, t)).toFixed(4));
    }
  };
  const request = () => {
    if (!ticking) {
      ticking = true;
      requestAnimationFrame(update);
    }
  };

  if (!reduced.matches) {
    root.classList.add('motion');
    const near = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          const el = entry.target as HTMLElement;
          if (entry.isIntersecting) scrubs.add(el);
          else scrubs.delete(el);
        }
        request();
      },
      { rootMargin: '10% 0px' },
    );
    document.querySelectorAll<HTMLElement>('[data-scrub]').forEach((el) => near.observe(el));
    addEventListener('scroll', request, { passive: true });
    addEventListener('resize', request, { passive: true });
    update();

    if (matchMedia('(hover: hover) and (pointer: fine)').matches) {
      document.addEventListener(
        'pointermove',
        (event) => {
          const el = (event.target as Element | null)?.closest<HTMLElement>('[data-light], .card');
          if (!el) return;
          const rect = el.getBoundingClientRect();
          el.style.setProperty('--mx', `${event.clientX - rect.left}px`);
          el.style.setProperty('--my', `${event.clientY - rect.top}px`);
        },
        { passive: true },
      );
    }
  } else {
    addEventListener('scroll', () => root.toggleAttribute('data-scrolled', scrollY > 12), { passive: true });
  }

  const seen = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-in');
          seen.unobserve(entry.target);
        }
      }
    },
    { threshold: 0.25 },
  );
  document.querySelectorAll('[data-inview], .reveal').forEach((el) => seen.observe(el));
}

start();

// Theme switch (decision B10): follow the device until the visitor chooses, then remember.
const toggle = document.querySelector<HTMLButtonElement>('[data-theme-toggle]');
if (toggle) {
  const label = () => {
    const dark = root.dataset.theme === 'dark';
    toggle.setAttribute('aria-label', dark ? 'Switch to light theme' : 'Switch to dark theme');
    toggle.title = dark ? 'Light theme' : 'Dark theme';
  };
  label();
  new MutationObserver(label).observe(root, { attributes: true, attributeFilter: ['data-theme'] });
  toggle.addEventListener('click', () => {
    const next = root.dataset.theme === 'dark' ? 'light' : 'dark';
    const apply = () => {
      root.dataset.theme = next;
      try {
        localStorage.setItem('theme', next);
      } catch {
        // Private mode: the choice lasts for this page only.
      }
      document
        .querySelector('meta[name="theme-color"]')
        ?.setAttribute('content', next === 'dark' ? '#191513' : '#FBF6F0');
    };
    if (!document.startViewTransition || reduced.matches) {
      apply();
      return;
    }
    const rect = toggle.getBoundingClientRect();
    root.style.setProperty('--vt-x', `${rect.left + rect.width / 2}px`);
    root.style.setProperty('--vt-y', `${rect.top + rect.height / 2}px`);
    root.classList.add('theme-vt');
    document.startViewTransition(apply).finished.finally(() => root.classList.remove('theme-vt'));
  });
}
