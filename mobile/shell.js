/* ============ shell.js — sólo en la app de Android (Capacitor) ============
 * Lo que una web no puede hacer (la web normal no carga este archivo):
 *  - Botón Atrás: en partida pausa; en una pantalla, la cierra (como Esc);
 *    en el menú principal, la app pasa a segundo plano (como en cualquier juego).
 *  - Vibración corta al recibir un golpe.
 * Los plugins nativos (@capacitor/app y @capacitor/haptics) los pone el puente
 * de Capacitor en window.Capacitor.Plugins: no hace falta empaquetar nada.
 */
(function () {
  const Cap = window.Capacitor;
  if (!Cap || !Cap.isNativePlatform || !Cap.isNativePlatform()) return;
  const P = Cap.Plugins || {};

  function esc() {
    for (const type of ['keydown', 'keyup']) {
      dispatchEvent(new KeyboardEvent(type, { key: 'Escape', code: 'Escape', bubbles: true }));
    }
  }

  // ¿Sólo está el menú principal a la vista (nada que cerrar)?
  function onMainMenu() {
    if (!G.Game || G.Game.state !== 'ui' || !G.UI.isOpen('scr-menu')) return false;
    if (G.SettingsUI && G.SettingsUI.isOpen) return false;
    const open = [...document.querySelectorAll('section.scr')].filter(s => !s.classList.contains('hidden'));
    return open.every(s => s.id === 'scr-menu');
  }

  if (P.App) {
    P.App.addListener('backButton', () => {
      if (onMainMenu()) P.App.minimizeApp();
      else esc();
    });
  }

  if (P.Haptics && G.Player) {
    const hurt = G.Player.prototype.hurt;
    G.Player.prototype.hurt = function (...args) {
      const before = this.hp;
      const r = hurt.apply(this, args);
      if (this.hp < before && this === G.Game.player) P.Haptics.impact({ style: 'LIGHT' }).catch(() => {});
      return r;
    };
  }
})();
