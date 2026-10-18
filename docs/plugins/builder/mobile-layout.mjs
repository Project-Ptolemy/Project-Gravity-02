/** Keep touch editing within the visible screen, including the software keyboard. */
export function createMobileLayout(onInspectorTab) {
  const media = matchMedia('(max-width: 1024px)');
  const workspace = document.querySelector('.workspace');
  const navigation = document.getElementById('mobile-navigation');
  const left = document.querySelector('.left-panel');
  const right = document.querySelector('.right-panel');
  let panel = 'scene';
  const scrollPositions = new Map();

  function show(next, focus = false) {
    if (!['preview', 'scene', 'properties', 'controls'].includes(next)) return;
    const previous = panel;
    scrollPositions.set(previous, previous === 'scene' ? left.scrollTop : right.scrollTop);
    panel = next;
    workspace.dataset.mobilePanel = panel;
    for (const button of navigation.querySelectorAll('[data-panel]')) {
      button.setAttribute('aria-pressed', String(button.dataset.panel === panel));
    }
    left.inert = media.matches && panel !== 'scene';
    right.inert = media.matches && !['properties', 'controls'].includes(panel);
    if (media.matches && previous !== panel) {
      const target = panel === 'scene' ? left : right;
      target.scrollTop = scrollPositions.get(panel) || 0;
      if (focus && panel !== 'preview') target.focus({ preventScroll: true });
    }
  }
  navigation.addEventListener('click', event => {
    const button = event.target.closest('[data-panel]');
    if (!button) return;
    if (['properties', 'controls'].includes(button.dataset.panel)) onInspectorTab(button.dataset.panel);
    else show(button.dataset.panel);
  });
  media.addEventListener('change', () => show(panel));

  function resize() {
    const visual = window.visualViewport;
    // Preserve pinch-to-zoom accessibility: browser zoom must not shrink the app.
    const height = visual && visual.scale === 1 ? visual.height : window.innerHeight;
    document.documentElement.style.setProperty('--app-height', `${height}px`);
    document.body.classList.toggle('keyboard-open', media.matches && window.innerHeight - height > 120);
  }
  window.visualViewport?.addEventListener('resize', resize);
  window.addEventListener('resize', resize);
  show(panel);
  resize();
  return { show, get active() { return media.matches; } };
}
