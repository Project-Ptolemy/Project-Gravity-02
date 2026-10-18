/** Keep touch editing within the visible screen, including the software keyboard. */
export function createMobileLayout(onInspectorTab) {
  const media = matchMedia('(max-width: 1024px)');
  const workspace = document.querySelector('.workspace');
  const navigation = document.getElementById('mobile-navigation');
  const left = document.querySelector('.left-panel');
  const right = document.querySelector('.right-panel');
  const status = document.querySelector('.statusbar');
  const statusHome = document.createComment('Desktop project status');
  status.before(statusHome);
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
    // Keep project tools available in Layers without reserving a second footer
    // on a small screen. Moving the original preserves its controls and status.
    if (media.matches && status.parentElement !== left) left.append(status);
    else if (!media.matches && status.parentElement === left) statusHome.after(status);
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

  let layoutWidth = window.innerWidth;
  let layoutHeight = window.innerHeight;
  function resize() {
    const visual = window.visualViewport;
    // Preserve pinch-to-zoom accessibility: browser zoom must not shrink the app.
    const height = visual && visual.scale === 1 ? visual.height : window.innerHeight;
    // Android can resize the layout viewport as well as the visual viewport.
    // A width change starts a new orientation; a keyboard only reduces height.
    if (Math.abs(window.innerWidth - layoutWidth) > 80) layoutHeight = window.innerHeight;
    layoutWidth = window.innerWidth;
    layoutHeight = Math.max(layoutHeight, window.innerHeight);
    const typing = document.activeElement?.matches('input, textarea, [contenteditable=true]');
    const keyboard = window.innerHeight - height > 120 || (typing && layoutHeight - height > 120);
    document.documentElement.style.setProperty('--app-height', `${height}px`);
    document.body.classList.toggle('keyboard-open', media.matches && (!visual || visual.scale === 1) && Boolean(keyboard));
  }
  window.visualViewport?.addEventListener('resize', resize);
  window.addEventListener('resize', resize);
  document.addEventListener('focusin', resize);
  document.addEventListener('focusout', () => queueMicrotask(resize));
  show(panel);
  resize();
  return { show, get active() { return media.matches; } };
}
