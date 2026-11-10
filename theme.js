/**
 * Hyggshi OS Theme Switcher
 * Modern Dark/Light theme manager with SVG icons
 */

(function() {
    const THEME_KEY = 'hyggshi-theme';
    const DARK = 'dark';
    const LIGHT = 'light';

    const SUN_SVG = `<svg class="icon-sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="5"></circle><line x1="12" y1="1" x2="12" y2="3"></line><line x1="12" y1="21" x2="12" y2="23"></line><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"></line><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"></line><line x1="1" y1="12" x2="3" y2="12"></line><line x1="21" y1="12" x2="23" y2="12"></line><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"></line><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"></line></svg>`;
    const MOON_SVG = `<svg class="icon-moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"></path></svg>`;

    function getSavedTheme() {
        return localStorage.getItem(THEME_KEY) || DARK;
    }

    function applyTheme(theme) {
        if (theme === LIGHT) {
            document.documentElement.setAttribute('data-theme', 'light');
        } else {
            document.documentElement.removeAttribute('data-theme');
        }
    }

    function toggleTheme() {
        const current = getSavedTheme();
        const next = current === DARK ? LIGHT : DARK;
        localStorage.setItem(THEME_KEY, next);
        applyTheme(next);
    }

    function setupToggleButtons() {
        document.querySelectorAll('.theme-toggle').forEach(btn => {
            btn.innerHTML = `<span class="toggle-icon">${SUN_SVG}${MOON_SVG}</span>`;
            btn.setAttribute('aria-label', 'Toggle light/dark theme');
            btn.removeEventListener('click', toggleTheme);
            btn.addEventListener('click', toggleTheme);
        });
    }

    function init() {
        applyTheme(getSavedTheme());
        setupToggleButtons();
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }

    window.HyggshiTheme = {
        toggle: toggleTheme,
        set: function(theme) {
            localStorage.setItem(THEME_KEY, theme);
            applyTheme(theme);
        },
        get: getSavedTheme
    };
})();