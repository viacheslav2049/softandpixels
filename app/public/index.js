// Header scroll effect
(function() {
  const header = document.getElementById('header');
  if (!header) return;
  window.addEventListener('scroll', function() {
    if (window.scrollY > 50) {
      header.classList.add('scrolled');
    } else {
      header.classList.remove('scrolled');
    }
  });
})();

// Smooth scroll for anchor links
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
  anchor.addEventListener('click', function(e) {
    const target = document.querySelector(this.getAttribute('href'));
    if (target) {
      e.preventDefault();
      target.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
  });
});

// Hero v3 mobile menu
(function() {
  const toggle = document.getElementById('hero-v3-menu-toggle');
  const overlay = document.getElementById('hero-v3-mobile-overlay');
  const sheet = document.getElementById('hero-v3-mobile-sheet');
  let isOpen = false;

  if (toggle && overlay) {
    toggle.addEventListener('click', function() {
      isOpen = !isOpen;
      if (isOpen) {
        overlay.classList.add('open');
        toggle.classList.add('active');
        document.body.style.overflow = 'hidden';
      } else {
        overlay.classList.remove('open');
        toggle.classList.remove('active');
        document.body.style.overflow = '';
      }
    });
  }

  // Close menu on link click
  if (sheet) {
    sheet.querySelectorAll('a').forEach(link => {
      link.addEventListener('click', function() {
        isOpen = false;
        overlay.classList.remove('open');
        toggle.classList.remove('active');
        document.body.style.overflow = '';
      });
    });
  }
})();

// London time
(function() {
  function updateLondonTime() {
    const now = new Date();
    const londonTime = now.toLocaleTimeString('en-GB', {
      timeZone: 'Europe/London',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false
    });
    const display = londonTime + ' in London';
    const el1 = document.getElementById('hero-v3-london-time');
    const el2 = document.getElementById('hero-v3-london-time-mobile');
    if (el1) el1.textContent = display;
    if (el2) el2.textContent = display;
  }
  updateLondonTime();
  setInterval(updateLondonTime, 60000);
})();
