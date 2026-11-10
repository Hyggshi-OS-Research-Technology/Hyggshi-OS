// Enhanced JavaScript with modern features
document.addEventListener('DOMContentLoaded', function () {
    // Initialize the application
    initApp();

    // Add smooth scrolling for navigation links
    addSmoothScrolling();

    // Add intersection observer for animations
    addScrollAnimations();

    // Add mobile menu functionality
    addMobileMenu();

    // Enable Remake mode if requested
    enableRemakeMode();
});

function initApp() {
    console.log('🚀 Modern Web Interface initialized!');

    // Add loading animation
    document.body.style.opacity = '0';
    setTimeout(() => {
        document.body.style.transition = 'opacity 0.5s ease-in';
        document.body.style.opacity = '1';
    }, 100);

    // Ensure a global theme toggle exists and load theme preference
    setupGlobalThemeToggle();
}

function displayMessage(event) {
    // Create a modern toast notification instead of alert
    showToast('🎉 Welcome to the Hyggshi-OS-project-center', 'success');

    // Add button animation
    const button = event ? event.target : null;
    if (button) {
        button.style.transform = 'scale(0.95)';
        setTimeout(() => {
            button.style.transform = 'scale(1)';
        }, 150);
    }
}

function showFeatures() {
    // Smooth scroll to features section
    const featuresSection = document.querySelector('.features');
    if (featuresSection) {
        featuresSection.scrollIntoView({
            behavior: 'smooth',
            block: 'start'
        });
    }

    // Show feature highlights
    showToast('✨ Discover our amazing features below!', 'info');
}

function addSmoothScrolling() {
    const navLinks = document.querySelectorAll('.nav-link');

    navLinks.forEach(link => {
        link.addEventListener('click', function (e) {
            const href = this.getAttribute('href');

            // If it's a page link (like History.html), don't prevent default
            if (href.includes('.html') || href.startsWith('http')) {
                return;
            }

            e.preventDefault();

            const targetId = href.substring(1);
            const targetSection = document.getElementById(targetId);

            if (targetSection) {
                targetSection.scrollIntoView({
                    behavior: 'smooth',
                    block: 'start'
                });
            }

            // Update active nav link
            navLinks.forEach(l => l.classList.remove('active'));
            this.classList.add('active');
        });
    });
}

function addScrollAnimations() {
    const observerOptions = {
        threshold: 0.1,
        rootMargin: '0px 0px -50px 0px'
    };

    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.style.opacity = '1';
                entry.target.style.transform = 'translateY(0)';
            }
        });
    }, observerOptions);

    // Observe feature cards
    const featureCards = document.querySelectorAll('.feature-card');
    featureCards.forEach(card => {
        card.style.opacity = '0';
        card.style.transform = 'translateY(30px)';
        card.style.transition = 'opacity 0.6s ease, transform 0.6s ease';
        observer.observe(card);
    });
}

function addMobileMenu() {
    try {
        // Check if nav element exists
        const nav = document.querySelector('.nav');
        if (!nav) {
            // Silently skip if nav is not found
            return;
        }

        // Check if mobile menu already exists
        if (document.querySelector('.mobile-menu-btn')) {
            return;
        }

        // Create mobile menu button
        const mobileMenuBtn = document.createElement('button');
        mobileMenuBtn.className = 'mobile-menu-btn';
        mobileMenuBtn.innerHTML = '☰';
        mobileMenuBtn.style.display = 'none';

        // Add mobile menu styles only if they don't exist
        if (!document.querySelector('#mobile-menu-styles')) {
            const style = document.createElement('style');
            style.id = 'mobile-menu-styles';
            style.textContent = `
                .mobile-menu-btn {
                    background: none;
                    border: none;
                    color: white;
                    font-size: 1.5rem;
                    cursor: pointer;
                    padding: 0.5rem;
                    border-radius: 8px;
                    transition: all 0.3s ease;
                }
                
                .mobile-menu-btn:hover {
                    background: rgba(255, 255, 255, 0.2);
                }
                
                @media (max-width: 768px) {
                    .mobile-menu-btn {
                        display: block !important;
                    }
                    
                    .nav-menu {
                        position: fixed;
                        top: 100%;
                        left: 0;
                        right: 0;
                        background: rgba(0, 0, 0, 0.9);
                        backdrop-filter: blur(20px);
                        flex-direction: column;
                        padding: 2rem;
                        transform: translateY(-100%);
                        transition: transform 0.3s ease;
                        z-index: 99;
                    }
                    
                    .nav-menu.active {
                        transform: translateY(0);
                    }
                }
            `;
            document.head.appendChild(style);
        }

        nav.appendChild(mobileMenuBtn);

        // Toggle mobile menu
        mobileMenuBtn.addEventListener('click', function () {
            const navMenu = document.querySelector('.nav-menu');
            if (navMenu) {
                navMenu.classList.toggle('active');
                this.innerHTML = navMenu.classList.contains('active') ? '✕' : '☰';
            }
        });

    } catch (error) {
        // Silently ignore errors
    }
}

/* SITE-WIDE THEME TOGGLE: creates a toggle in nav if missing and persists preference */
function setupGlobalThemeToggle() {
    try {
        const body = document.body;
        const nav = document.querySelector('.nav') || document.querySelector('.nav-container') || document.querySelector('.navbar');
        if (!nav) return;

        // Find existing toggle
        let toggle = document.getElementById('global-theme-toggle');
        if (!toggle) {
            toggle = document.createElement('button');
            toggle.id = 'global-theme-toggle';
            toggle.className = 'theme-toggle';
            // Icon/text will be set by applyTheme
            toggle.title = 'Toggle light / dark';
            // Insert into nav (prefer right side)
            // If nav is a container with .nav-menu or .nav-links, append to that; otherwise append to nav itself
            const menu = nav.querySelector('.nav-menu, .nav-links');
            (menu || nav).appendChild(toggle);
        }

        function applyThemeFromStorage() {
            const saved = localStorage.getItem('hyggshi_theme');
            const prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
            if (saved === 'light') {
                body.classList.add('light-mode');
                toggle.textContent = '☀️';
            } else if (saved === 'dark') {
                body.classList.remove('light-mode');
                toggle.textContent = '🌙';
            } else {
                // no saved preference → use system
                if (prefersDark) {
                    body.classList.remove('light-mode');
                    toggle.textContent = '🌙';
                } else {
                    body.classList.add('light-mode');
                    toggle.textContent = '☀️';
                }
            }
        }

        applyThemeFromStorage();

        // Toggle handler
        toggle.addEventListener('click', () => {
            const isLight = body.classList.toggle('light-mode');
            localStorage.setItem('hyggshi_theme', isLight ? 'light' : 'dark');
            toggle.textContent = isLight ? '☀️' : '🌙';
        });

        // React to system changes only if user hasn't chosen
        if (window.matchMedia) {
            window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', e => {
                if (!localStorage.getItem('hyggshi_theme')) {
                    if (e.matches) {
                        body.classList.remove('light-mode');
                        toggle.textContent = '🌙';
                    } else {
                        body.classList.add('light-mode');
                        toggle.textContent = '☀️';
                    }
                }
            });
        }
    } catch (e) {
        // no-op
    }
}

function showToast(message, type = 'info') {
    // Remove existing toasts
    const existingToasts = document.querySelectorAll('.toast');
    existingToasts.forEach(toast => toast.remove());

    // Create toast element
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.innerHTML = `
        <div class="toast-content">
            <span class="toast-message">${message}</span>
            <button class="toast-close">✕</button>
        </div>
    `;

    // Add toast styles
    if (!document.querySelector('#toast-styles')) {
        const toastStyles = document.createElement('style');
        toastStyles.id = 'toast-styles';
        toastStyles.textContent = `
            .toast {
                position: fixed;
                top: 20px;
                right: 20px;
                background: rgba(255, 255, 255, 0.95);
                backdrop-filter: blur(20px);
                border: 1px solid rgba(255, 255, 255, 0.2);
                border-radius: 12px;
                padding: 1rem 1.5rem;
                color: #333;
                font-weight: 500;
                box-shadow: 0 10px 30px rgba(0, 0, 0, 0.2);
                z-index: 1000;
                transform: translateX(100%);
                transition: transform 0.3s ease;
                max-width: 300px;
            }
            
            .toast.show {
                transform: translateX(0);
            }
            
            .toast-content {
                display: flex;
                align-items: center;
                gap: 1rem;
            }
            
            .toast-close {
                background: none;
                border: none;
                color: #666;
                cursor: pointer;
                font-size: 1.2rem;
                padding: 0;
                width: 20px;
                height: 20px;
                display: flex;
                align-items: center;
                justify-content: center;
                border-radius: 50%;
                transition: all 0.3s ease;
            }
            
            .toast-close:hover {
                background: rgba(0, 0, 0, 0.1);
                color: #333;
            }
            
            .toast-success {
                border-left: 4px solid #4CAF50;
            }
            
            .toast-info {
                border-left: 4px solid #2196F3;
            }
            
            .toast-warning {
                border-left: 4px solid #FF9800;
            }
            
            .toast-error {
                border-left: 4px solid #F44336;
            }
        `;
        document.head.appendChild(toastStyles);
    }

    document.body.appendChild(toast);

    // Show toast
    setTimeout(() => {
        toast.classList.add('show');
    }, 100);

    // Auto hide after 5 seconds
    setTimeout(() => {
        hideToast(toast);
    }, 5000);

    // Close button functionality
    const closeBtn = toast.querySelector('.toast-close');
    closeBtn.addEventListener('click', () => {
        hideToast(toast);
    });
}

function hideToast(toast) {
    toast.classList.remove('show');
    setTimeout(() => {
        if (toast.parentNode) {
            toast.parentNode.removeChild(toast);
        }
    }, 300);
}

// Add parallax effect to hero section
window.addEventListener('scroll', function () {
    const scrolled = window.pageYOffset;
    const hero = document.querySelector('.hero');
    const floatingCard = document.querySelector('.floating-card');

    if (hero && floatingCard) {
        const rate = scrolled * -0.5;
        floatingCard.style.transform = `translateY(${rate}px)`;
    }
});

// Add keyboard navigation
document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') {
        // Close mobile menu if open
        const navMenu = document.querySelector('.nav-menu');
        if (navMenu && navMenu.classList.contains('active')) {
            navMenu.classList.remove('active');
            const mobileBtn = document.querySelector('.mobile-menu-btn');
            if (mobileBtn) mobileBtn.innerHTML = '☰';
        }
    }
});

function enableRemakeMode() {
    try {
        const url = new URL(window.location.href);
        const queryWantsRemake = url.searchParams.get('remake') === '1';
        const hashWantsRemake = (url.hash || '').toLowerCase().includes('remake');

        if (!(queryWantsRemake || hashWantsRemake)) {
            // Also respect persisted choice
            const persisted = localStorage.getItem('hyggshi_remake') === '1';
            if (!persisted) return;
        }

        document.body.classList.add('remake');
        localStorage.setItem('hyggshi_remake', '1');

        // Insert a subtle badge
        if (!document.querySelector('.remake-badge')) {
            const badge = document.createElement('div');
            badge.className = 'remake-badge';
            badge.textContent = 'Remake Preview ON';
            document.body.appendChild(badge);
        }

        // Add toggle link to nav if missing
        const navMenu = document.querySelector('.nav-menu');
        if (navMenu && !navMenu.querySelector('.remake-toggle')) {
            const li = document.createElement('li');
            const a = document.createElement('a');
            a.href = '#';
            a.className = 'nav-link remake-toggle';
            a.textContent = 'Remake: ON';
            a.title = 'Toggle Remake theme';
            a.addEventListener('click', (e) => {
                e.preventDefault();
                const isOn = document.body.classList.toggle('remake');
                localStorage.setItem('hyggshi_remake', isOn ? '1' : '0');
                a.textContent = isOn ? 'Remake: ON' : 'Remake: OFF';
                const badge = document.querySelector('.remake-badge');
                if (isOn) {
                    if (!badge) {
                        const b = document.createElement('div');
                        b.className = 'remake-badge';
                        b.textContent = 'Remake Preview ON';
                        document.body.appendChild(b);
                    }
                } else if (badge) {
                    badge.remove();
                }
            });
            li.appendChild(a);
            navMenu.appendChild(li);
        }
    } catch (e) {
        // no-op
    }
}