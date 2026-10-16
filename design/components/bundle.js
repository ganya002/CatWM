/* @ds-bundle: {"format":4,"namespace":"Ouch","components":[{"name":"Symbol"},{"name":"Kbd"},{"name":"Button"},{"name":"Switch"},{"name":"Slider"},{"name":"Segmented"},{"name":"Row"},{"name":"Surface"},{"name":"Menu"},{"name":"CommandMenu"},{"name":"Tooltip"},{"name":"CoachMark"},{"name":"HUD"},{"name":"LayoutThumb"},{"name":"LayoutPicker"},{"name":"WorkspaceStrip"}]} */
(function () {
  var React = window.React;
  var h = React.createElement;
  var useState = React.useState, useEffect = React.useEffect, useRef = React.useRef, useMemo = React.useMemo, useLayoutEffect = React.useLayoutEffect;

  function cx() {
    var out = [];
    for (var i = 0; i < arguments.length; i++) if (arguments[i]) out.push(arguments[i]);
    return out.join(' ');
  }

  /* ---------------- Symbol ----------------
     Web stand-ins for SF Symbols, keyed by the real SF Symbol name; in the app use Image(systemName:) with the
     matching .symbolEffect. */
  /* Icon outlines from Lucide (ISC), keyed by the SF Symbol each stands in for. */
  var ICONS = {
"key.cmd": "<path d=\"M15 6v12a3 3 0 1 0 3-3H6a3 3 0 1 0 3 3V6a3 3 0 1 0-3 3h12a3 3 0 1 0-3-3\" />",
"key.opt": "<path d=\"M3 3h6l6 18h6\" /><path d=\"M14 3h7\" />",
"key.shift": "<path d=\"M9 18v-6H5l7-7 7 7h-4v6H9z\" />",
"key.caps": "<path d=\"M9 19h6\" /><path d=\"M9 15v-3H5l7-7 7 7h-4v3H9z\" />",
"key.ctrl": "<path d=\"m18 15-6-6-6 6\" />",
"key.return": "<polyline points=\"9 10 4 15 9 20\" /><path d=\"M20 4v7a4 4 0 0 1-4 4H4\" />",
"key.tab": "<path d=\"M17 12H3\" /><path d=\"m11 18 6-6-6-6\" /><path d=\"M21 5v14\" />",
"key.delete": "<path d=\"M10 5a2 2 0 0 0-1.344.519l-6.328 5.74a1 1 0 0 0 0 1.481l6.328 5.741A2 2 0 0 0 10 19h10a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2z\" /><path d=\"m12 9 6 6\" /><path d=\"m18 9-6 6\" />",
"key.left": "<path d=\"m12 19-7-7 7-7\" /><path d=\"M19 12H5\" />",
"key.right": "<path d=\"M5 12h14\" /><path d=\"m12 5 7 7-7 7\" />",
"key.up": "<path d=\"m5 12 7-7 7 7\" /><path d=\"M12 19V5\" />",
"key.down": "<path d=\"M12 5v14\" /><path d=\"m19 12-7 7-7-7\" />",
"rectangle.split.3x1": "<rect data-layer=\"1\" x=\"2.5\" y=\"4\" width=\"5.4\" height=\"16\" rx=\"1.6\" /><rect data-layer=\"2\" x=\"9.3\" y=\"4\" width=\"5.4\" height=\"16\" rx=\"1.6\" /><rect data-layer=\"3\" x=\"16.1\" y=\"4\" width=\"5.4\" height=\"16\" rx=\"1.6\" />",
"rectangle.split.2x1": "<rect data-layer=\"1\" width=\"18\" height=\"18\" x=\"3\" y=\"3\" rx=\"2\" /><path data-layer=\"2\" d=\"M12 3v18\" />",
"square.grid.2x2": "<rect data-layer=\"1\" width=\"7\" height=\"7\" x=\"3\" y=\"3\" rx=\"1\" /><rect data-layer=\"2\" width=\"7\" height=\"7\" x=\"14\" y=\"3\" rx=\"1\" /><rect data-layer=\"3\" width=\"7\" height=\"7\" x=\"14\" y=\"14\" rx=\"1\" /><rect data-layer=\"4\" width=\"7\" height=\"7\" x=\"3\" y=\"14\" rx=\"1\" />",
"macwindow": "<rect data-layer=\"1\" x=\"2\" y=\"4\" width=\"20\" height=\"16\" rx=\"2\" /><path data-layer=\"2\" d=\"M10 4v4\" /><path data-layer=\"3\" d=\"M2 8h20\" /><path data-layer=\"4\" d=\"M6 4v4\" />",
"macwindow.on.rectangle": "<path data-layer=\"1\" d=\"m16.02 12 5.48 3.13a1 1 0 0 1 0 1.74L13 21.74a2 2 0 0 1-2 0l-8.5-4.87a1 1 0 0 1 0-1.74L7.98 12\" /><path data-layer=\"2\" d=\"M13 13.74a2 2 0 0 1-2 0L2.5 8.87a1 1 0 0 1 0-1.74L11 2.26a2 2 0 0 1 2 0l8.5 4.87a1 1 0 0 1 0 1.74Z\" />",
"rectangle.3.group": "<path data-layer=\"1\" d=\"M2 3v18\" /><rect data-layer=\"2\" width=\"12\" height=\"18\" x=\"6\" y=\"3\" rx=\"2\" /><path data-layer=\"3\" d=\"M22 3v18\" />",
"keyboard": "<path data-layer=\"1\" d=\"M10 8h.01\" /><path data-layer=\"2\" d=\"M12 12h.01\" /><path data-layer=\"3\" d=\"M14 8h.01\" /><path data-layer=\"4\" d=\"M16 12h.01\" /><path data-layer=\"5\" d=\"M18 8h.01\" /><path data-layer=\"6\" d=\"M6 8h.01\" /><path data-layer=\"7\" d=\"M7 16h10\" /><path data-layer=\"8\" d=\"M8 12h.01\" /><rect data-layer=\"9\" width=\"20\" height=\"16\" x=\"2\" y=\"4\" rx=\"2\" />",
"command": "<path data-layer=\"1\" d=\"M15 6v12a3 3 0 1 0 3-3H6a3 3 0 1 0 3 3V6a3 3 0 1 0-3 3h12a3 3 0 1 0-3-3\" />",
"option": "<path data-layer=\"1\" d=\"M3 3h6l6 18h6\" /><path data-layer=\"2\" d=\"M14 3h7\" />",
"shift": "<path data-layer=\"1\" d=\"M9 18v-6H5l7-7 7 7h-4v6H9z\" />",
"capslock": "<path data-layer=\"1\" d=\"M9 19h6\" /><path data-layer=\"2\" d=\"M9 15v-3H5l7-7 7 7h-4v3H9z\" />",
"gearshape": "<path data-layer=\"1\" d=\"M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z\" /><circle data-layer=\"2\" cx=\"12\" cy=\"12\" r=\"3\" />",
"arrow.triangle.2.circlepath": "<path data-layer=\"1\" d=\"M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8\" /><path data-layer=\"2\" d=\"M21 3v5h-5\" /><path data-layer=\"3\" d=\"M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16\" /><path data-layer=\"4\" d=\"M8 16H3v5\" />",
"chevron.right": "<path data-layer=\"1\" d=\"m9 18 6-6-6-6\" />",
"chevron.left": "<path data-layer=\"1\" d=\"m15 18-6-6 6-6\" />",
"chevron.down": "<path data-layer=\"1\" d=\"m6 9 6 6 6-6\" />",
"checkmark": "<path data-layer=\"1\" d=\"M20 6 9 17l-5-5\" />",
"magnifyingglass": "<circle data-layer=\"1\" cx=\"11\" cy=\"11\" r=\"8\" /><path data-layer=\"2\" d=\"m21 21-4.3-4.3\" />",
"wand.and.stars": "<path data-layer=\"1\" d=\"m21.64 3.64-1.28-1.28a1.21 1.21 0 0 0-1.72 0L2.36 18.64a1.21 1.21 0 0 0 0 1.72l1.28 1.28a1.2 1.2 0 0 0 1.72 0L21.64 5.36a1.2 1.2 0 0 0 0-1.72\" /><path data-layer=\"2\" d=\"m14 7 3 3\" /><path data-layer=\"3\" d=\"M5 6v4\" /><path data-layer=\"4\" d=\"M19 14v4\" /><path data-layer=\"5\" d=\"M10 2v2\" /><path data-layer=\"6\" d=\"M7 8H3\" /><path data-layer=\"7\" d=\"M21 16h-4\" /><path data-layer=\"8\" d=\"M11 3H9\" />",
"sparkles": "<path data-layer=\"1\" d=\"M9.937 15.5A2 2 0 0 0 8.5 14.063l-6.135-1.582a.5.5 0 0 1 0-.962L8.5 9.936A2 2 0 0 0 9.937 8.5l1.582-6.135a.5.5 0 0 1 .963 0L14.063 8.5A2 2 0 0 0 15.5 9.937l6.135 1.581a.5.5 0 0 1 0 .964L15.5 14.063a2 2 0 0 0-1.437 1.437l-1.582 6.135a.5.5 0 0 1-.963 0z\" /><path data-layer=\"2\" d=\"M20 3v4\" /><path data-layer=\"3\" d=\"M22 5h-4\" /><path data-layer=\"4\" d=\"M4 17v2\" /><path data-layer=\"5\" d=\"M5 18H3\" />",
"questionmark.circle": "<circle data-layer=\"1\" cx=\"12\" cy=\"12\" r=\"10\" /><path data-layer=\"2\" d=\"M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3\" /><path data-layer=\"3\" d=\"M12 17h.01\" />",
"arrow.down.circle": "<circle data-layer=\"1\" cx=\"12\" cy=\"12\" r=\"10\" /><path data-layer=\"2\" d=\"M12 8v8\" /><path data-layer=\"3\" d=\"m8 12 4 4 4-4\" />",
"power": "<path data-layer=\"1\" d=\"M12 2v10\" /><path data-layer=\"2\" d=\"M18.4 6.6a9 9 0 1 1-12.77.04\" />",
"lightbulb": "<path data-layer=\"1\" d=\"M15 14c.2-1 .7-1.7 1.5-2.5 1-.9 1.5-2.2 1.5-3.5A6 6 0 0 0 6 8c0 1 .2 2.2 1.5 3.5.7.7 1.3 1.5 1.5 2.5\" /><path data-layer=\"2\" d=\"M9 18h6\" /><path data-layer=\"3\" d=\"M10 22h4\" />",
"exclamationmark.triangle": "<path data-layer=\"1\" d=\"m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3\" /><path data-layer=\"2\" d=\"M12 9v4\" /><path data-layer=\"3\" d=\"M12 17h.01\" />",
"xmark": "<path data-layer=\"1\" d=\"M18 6 6 18\" /><path data-layer=\"2\" d=\"m6 6 12 12\" />",
"cursorarrow": "<path data-layer=\"1\" d=\"M4.037 4.688a.495.495 0 0 1 .651-.651l16 6.5a.5.5 0 0 1-.063.947l-6.124 1.58a2 2 0 0 0-1.438 1.435l-1.579 6.126a.5.5 0 0 1-.947.063z\" />",
"cursorarrow.rays": "<path data-layer=\"1\" d=\"M14 4.1 12 6\" /><path data-layer=\"2\" d=\"m5.1 8-2.9-.8\" /><path data-layer=\"3\" d=\"m6 12-1.9 2\" /><path data-layer=\"4\" d=\"M7.2 2.2 8 5.1\" /><path data-layer=\"5\" d=\"M9.037 9.69a.498.498 0 0 1 .653-.653l11 4.5a.5.5 0 0 1-.074.949l-4.349 1.041a1 1 0 0 0-.74.739l-1.04 4.35a.5.5 0 0 1-.95.074z\" />",
"square.dashed": "<path data-layer=\"1\" d=\"M5 3a2 2 0 0 0-2 2\" /><path data-layer=\"2\" d=\"M19 3a2 2 0 0 1 2 2\" /><path data-layer=\"3\" d=\"M21 19a2 2 0 0 1-2 2\" /><path data-layer=\"4\" d=\"M5 21a2 2 0 0 1-2-2\" /><path data-layer=\"5\" d=\"M9 3h1\" /><path data-layer=\"6\" d=\"M9 21h1\" /><path data-layer=\"7\" d=\"M14 3h1\" /><path data-layer=\"8\" d=\"M14 21h1\" /><path data-layer=\"9\" d=\"M3 9v1\" /><path data-layer=\"10\" d=\"M21 9v1\" /><path data-layer=\"11\" d=\"M3 14v1\" /><path data-layer=\"12\" d=\"M21 14v1\" />",
"pin": "<path data-layer=\"1\" d=\"M12 17v5\" /><path data-layer=\"2\" d=\"M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z\" />",
"slider.horizontal.3": "<line data-layer=\"1\" x1=\"21\" x2=\"14\" y1=\"4\" y2=\"4\" /><line data-layer=\"2\" x1=\"10\" x2=\"3\" y1=\"4\" y2=\"4\" /><line data-layer=\"3\" x1=\"21\" x2=\"12\" y1=\"12\" y2=\"12\" /><line data-layer=\"4\" x1=\"8\" x2=\"3\" y1=\"12\" y2=\"12\" /><line data-layer=\"5\" x1=\"21\" x2=\"16\" y1=\"20\" y2=\"20\" /><line data-layer=\"6\" x1=\"12\" x2=\"3\" y1=\"20\" y2=\"20\" /><line data-layer=\"7\" x1=\"14\" x2=\"14\" y1=\"2\" y2=\"6\" /><line data-layer=\"8\" x1=\"8\" x2=\"8\" y1=\"10\" y2=\"14\" /><line data-layer=\"9\" x1=\"16\" x2=\"16\" y1=\"18\" y2=\"22\" />",
"play.fill": "<polygon points=\"6 3 20 12 6 21 6 3\" class=\"fill\"/>",
"menubar.rectangle": "<rect data-layer=\"1\" width=\"18\" height=\"18\" x=\"3\" y=\"3\" rx=\"2\" /><path data-layer=\"2\" d=\"M3 9h18\" />",
"square.and.arrow.up": "<path data-layer=\"1\" d=\"M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4\" /><polyline data-layer=\"2\" points=\"17 8 12 3 7 8\" /><line data-layer=\"3\" x1=\"12\" x2=\"12\" y1=\"3\" y2=\"15\" />",
"square.and.arrow.down": "<path data-layer=\"1\" d=\"M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4\" /><polyline data-layer=\"2\" points=\"7 10 12 15 17 10\" /><line data-layer=\"3\" x1=\"12\" x2=\"12\" y1=\"15\" y2=\"3\" />",
"doc.text": "<path data-layer=\"1\" d=\"M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z\" /><path data-layer=\"2\" d=\"M14 2v4a2 2 0 0 0 2 2h4\" /><path data-layer=\"3\" d=\"M10 9H8\" /><path data-layer=\"4\" d=\"M16 13H8\" /><path data-layer=\"5\" d=\"M16 17H8\" />",
"arrow.up.left.and.arrow.down.right": "<polyline data-layer=\"1\" points=\"15 3 21 3 21 9\" /><polyline data-layer=\"2\" points=\"9 21 3 21 3 15\" /><line data-layer=\"3\" x1=\"21\" x2=\"14\" y1=\"3\" y2=\"10\" /><line data-layer=\"4\" x1=\"3\" x2=\"10\" y1=\"21\" y2=\"14\" />",
"arrow.uturn.backward": "<path data-layer=\"1\" d=\"M9 14 4 9l5-5\" /><path data-layer=\"2\" d=\"M4 9h10.5a5.5 5.5 0 0 1 5.5 5.5a5.5 5.5 0 0 1-5.5 5.5H11\" />",
"arrow.left.arrow.right": "<path data-layer=\"1\" d=\"M8 3 4 7l4 4\" /><path data-layer=\"2\" d=\"M4 7h16\" /><path data-layer=\"3\" d=\"m16 21 4-4-4-4\" /><path data-layer=\"4\" d=\"M20 17H4\" />",
"ellipsis": "<circle data-layer=\"1\" cx=\"12\" cy=\"12\" r=\"1\" /><circle data-layer=\"2\" cx=\"19\" cy=\"12\" r=\"1\" /><circle data-layer=\"3\" cx=\"5\" cy=\"12\" r=\"1\" />",
"circle.fill": "<circle cx=\"12\" cy=\"12\" r=\"6\" class=\"fill\"/>",
"book": "<path data-layer=\"1\" d=\"M12 7v14\" /><path data-layer=\"2\" d=\"M3 18a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h5a4 4 0 0 1 4 4 4 4 0 0 1 4-4h5a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1h-6a3 3 0 0 0-3 3 3 3 0 0 0-3-3z\" />",
"paintpalette": "<circle data-layer=\"1\" cx=\"13.5\" cy=\"6.5\" r=\".5\" fill=\"currentColor\" /><circle data-layer=\"2\" cx=\"17.5\" cy=\"10.5\" r=\".5\" fill=\"currentColor\" /><circle data-layer=\"3\" cx=\"8.5\" cy=\"7.5\" r=\".5\" fill=\"currentColor\" /><circle data-layer=\"4\" cx=\"6.5\" cy=\"12.5\" r=\".5\" fill=\"currentColor\" /><path data-layer=\"5\" d=\"M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10c.926 0 1.648-.746 1.648-1.688 0-.437-.18-.835-.437-1.125-.29-.289-.438-.652-.438-1.125a1.64 1.64 0 0 1 1.668-1.668h1.996c3.051 0 5.555-2.503 5.555-5.554C21.965 6.012 17.461 2 12 2z\" />",
"hand.raised": "<path data-layer=\"1\" d=\"M18 11V6a2 2 0 0 0-2-2a2 2 0 0 0-2 2\" /><path data-layer=\"2\" d=\"M14 10V4a2 2 0 0 0-2-2a2 2 0 0 0-2 2v2\" /><path data-layer=\"3\" d=\"M10 10.5V6a2 2 0 0 0-2-2a2 2 0 0 0-2 2v8\" /><path data-layer=\"4\" d=\"M18 8a2 2 0 1 1 4 0v6a8 8 0 0 1-8 8h-2c-2.8 0-4.5-.86-5.99-2.34l-3.6-3.6a2 2 0 0 1 2.83-2.82L7 15\" />",
"display": "<rect data-layer=\"1\" width=\"20\" height=\"14\" x=\"2\" y=\"3\" rx=\"2\" /><line data-layer=\"2\" x1=\"8\" x2=\"16\" y1=\"21\" y2=\"21\" /><line data-layer=\"3\" x1=\"12\" x2=\"12\" y1=\"17\" y2=\"21\" />",
"return": "<polyline data-layer=\"1\" points=\"9 10 4 15 9 20\" /><path data-layer=\"2\" d=\"M20 4v7a4 4 0 0 1-4 4H4\" />",
"checkmark.circle.fill": "<circle cx=\"12\" cy=\"12\" r=\"10\" class=\"fill\"/><path d=\"m8.5 12 2.5 2.5 4.5-5\" class=\"knock\"/>",
"exclamationmark.triangle.fill": "<path d=\"m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3\" class=\"fill\"/><path d=\"M12 9v4\" class=\"knock\"/><path d=\"M12 17h.01\" class=\"knock\"/>"
};
  var WEIGHTS = { ultralight: 1, light: 1.4, regular: 1.75, medium: 2, semibold: 2.25, bold: 2.5 };

  function Symbol(props) {
    var name = props.name, effect = props.effect, size = props.size || 16;
    var inner = ICONS[name] || ICONS['questionmark.circle'];
    var loop = props.repeat === 'loop';
    // discrete effects replay when `trigger` changes (remount); replace replays when the name changes
    var key = name + ':' + (props.trigger == null ? '' : props.trigger);
    return h('span', {
      className: cx('o-sym', effect && 'o-fx-' + effect, loop && 'o-fx-loop', props.className),
      style: Object.assign({ width: size, height: size, color: props.color }, props.style),
      role: props.label ? 'img' : undefined, 'aria-label': props.label, 'aria-hidden': props.label ? undefined : true,
      'data-sf': name
    }, h('svg', { key: key, viewBox: '0 0 24 24', strokeWidth: WEIGHTS[props.weight || 'regular'], dangerouslySetInnerHTML: { __html: inner } }));
  }
  Symbol.names = Object.keys(ICONS);

  /* ---------------- Kbd ---------------- */
  var GLYPH = { cmd: '⌘', command: '⌘', opt: '⌥', option: '⌥', alt: '⌥', shift: '⇧', ctrl: '⌃', control: '⌃', caps: '⇪', capslock: '⇪', enter: '↩', return: '↩', esc: 'esc', escape: 'esc', tab: '⇥', space: 'space', left: '←', right: '→', up: '↑', down: '↓', delete: '⌫' };
  function glyph(k) { var g = GLYPH[String(k).toLowerCase()]; return g || String(k).toUpperCase(); }
  // Modifiers and arrows draw as icons: the glyph characters fall back to mismatched system fonts.
  var KEY_ICON = { cmd: 'key.cmd', command: 'key.cmd', opt: 'key.opt', option: 'key.opt', alt: 'key.opt', shift: 'key.shift', ctrl: 'key.ctrl', control: 'key.ctrl', caps: 'key.caps', capslock: 'key.caps', enter: 'key.return', return: 'key.return', tab: 'key.tab', delete: 'key.delete', left: 'key.left', right: 'key.right', up: 'key.up', down: 'key.down' };
  function keyIcon(k) { return KEY_ICON[String(k).toLowerCase()]; }
  function Shortcut(props) {
    return h('span', { className: 'o-sc' }, (props.keys || []).map(function (k, i) {
      var icon = keyIcon(k);
      return icon ? h(Symbol, { key: i, name: icon, size: 12, weight: 'medium', label: glyph(k) }) : h('span', { key: i }, glyph(k));
    }));
  }

  function Kbd(props) {
    var keys = props.keys || [props.children];
    var then = props.then; // a second chord: [['cmd','caps'], ['n']] style sequence
    var lg = props.size === 'lg';
    function chord(ks, ci) {
      return h('span', { className: 'o-keys', key: ci }, ks.map(function (k, i) {
        var icon = keyIcon(k), g = glyph(k);
        return h('kbd', { key: i, 'aria-label': g, className: cx('o-kbd', lg && 'o-kbd--lg', lg && !icon && g.length > 1 && 'is-wide', props.pressed && 'is-down') },
          icon ? h(Symbol, { name: icon, size: lg ? 18 : 12, weight: lg ? 'regular' : 'medium' }) : g);
      }));
    }
    if (then) {
      var seq = [keys].concat(then);
      var out = [];
      seq.forEach(function (ks, i) { if (i) out.push(h('span', { className: 'o-keys__then', key: 't' + i }, 'then')); out.push(chord(ks, i)); });
      return h('span', { className: 'o-keys o-keys--seq' }, out);
    }
    return chord(keys, 0);
  }
  Kbd.glyph = glyph;

  /* ---------------- Button ---------------- */
  function Button(props) {
    var v = props.variant || 'secondary';
    return h('button', {
      type: 'button', className: cx('o-btn', 'o-btn--' + v, props.size && 'o-btn--' + props.size, props.icon && !props.children && 'o-btn--icon', props.className),
      onClick: props.onClick, disabled: props.disabled, 'aria-label': props.label, title: props.title
    },
      props.icon ? h(Symbol, { name: props.icon, effect: props.iconEffect, trigger: props.iconTrigger, size: props.size === 'sm' ? 14 : 16 }) : null,
      props.children,
      props.shortcut ? h(Kbd, { keys: props.shortcut }) : null);
  }

  /* ---------------- Switch ---------------- */
  // Click or Space toggles; dragging the thumb follows the pointer and settles on the nearer side.
  var SWITCH_TRAVEL = 14;
  function Switch(props) {
    var s = useState(!!props.defaultChecked); var on = props.checked != null ? props.checked : s[0];
    var drag = useRef(null); var dx = useState(null), x = dx[0];
    function set(v) { if (v !== on) { s[1](v); props.onChange && props.onChange(v); } }
    function end(e, cancelled) {
      var d = drag.current; drag.current = null;
      if (!d) return;
      if (!cancelled) set(d.moved ? d.x > SWITCH_TRAVEL / 2 : !on);
      d.handled = true; dx[1](null);
    }
    var shown = x != null ? x > SWITCH_TRAVEL / 2 : on;
    return h('button', {
      type: 'button', role: 'switch', 'aria-checked': on, 'aria-label': props.label,
      className: cx('o-switch', shown && 'is-on', x != null && 'is-dragging'),
      style: x != null ? { '--x': x + 'px' } : null,
      onPointerDown: function (e) {
        if (e.button !== 0) return;
        e.stopPropagation();
        drag.current = { x0: e.clientX, start: on ? SWITCH_TRAVEL : 0, x: on ? SWITCH_TRAVEL : 0, moved: false };
        e.currentTarget.setPointerCapture(e.pointerId);
      },
      onPointerMove: function (e) {
        var d = drag.current; if (!d) return;
        var delta = e.clientX - d.x0;
        if (Math.abs(delta) > 3) d.moved = true;
        if (d.moved) { d.x = Math.max(0, Math.min(SWITCH_TRAVEL, d.start + delta)); dx[1](d.x); }
      },
      onPointerUp: function (e) { e.stopPropagation(); end(e, false); },
      onPointerCancel: function (e) { end(e, true); },
      // pointer interactions are settled in pointerup; a click with detail 0 is the keyboard (Space / Return)
      onClick: function (e) { e.stopPropagation(); if (e.detail === 0) set(!on); }
    });
  }

  /* ---------------- Slider ----------------
     Two shapes, one behaviour. `line`: a thin track with a thumb and a value bubble while dragging.
     `bar`: a Control Center style pill, the fill is the indicator, label and value sit inside it.
     Press without moving: the value jumps to the press point and springs there. Drag: a line follows the
     pointer, a bar drags relative to where you grabbed it. While dragging the fill follows the pointer
     continuously (the value still rounds to `step`), hold ⌥ for fine control, past an end the control
     stretches like rubber, ticks are detents, double-click resets, arrows step (⇧ ×10), Home / End jump.
     Pointer presses never draw a focus ring; keyboard focus does. */
  function Slider(props) {
    var min = props.min != null ? props.min : 0, max = props.max != null ? props.max : 100, step = props.step || 1;
    var variant = props.variant || 'line';
    var initial = props.defaultValue != null ? props.defaultValue : min;
    var s = useState(initial); var value = props.value != null ? props.value : s[0];
    var dragS = useState(false), dragging = dragS[0];
    var visS = useState(null), vis = visS[0];
    var stretchS = useState(0), stretch = stretchS[0];
    var bumpS = useState(0), edgeS = useState(0);
    var kbS = useState(false);
    var ref = useRef(null), d = useRef(null);
    var range = max - min;
    var ticks = Array.isArray(props.ticks) ? props.ticks : props.ticks ? Array.from({ length: Math.floor(range / props.ticks) + 1 }, function (_, i) { return min + i * props.ticks; }) : [];
    var fmt = props.format || function (v) { return String(v); };
    function clamp(v) { return Math.max(min, Math.min(max, v)); }
    function round(v) { var r = Math.round((v - min) / step) * step + min; return clamp(+r.toFixed(6)); }
    function snap(v) {
      for (var i = 0; i < ticks.length; i++) if (Math.abs(v - ticks[i]) <= range * 0.025) return ticks[i];
      return v;
    }
    function commit(v) {
      if (v === value) return;
      if (ticks.indexOf(v) >= 0) bumpS[1](function (n) { return n + 1; });
      if ((v === min || v === max) && value !== v) edgeS[1](function (n) { return n + 1; });
      s[1](v); props.onChange && props.onChange(v);
    }
    function frac(v) { return range ? (v - min) / range : 0; }
    function fromX(clientX, rect) { return min + ((clientX - rect.left) / rect.width) * range; }

    function onDown(e) {
      if (e.button !== 0) return;
      e.preventDefault(); e.stopPropagation();
      var rect = ref.current.getBoundingClientRect();
      var start = value;
      // a line follows the pointer from the press point; a bar waits to see whether this is a tap or a drag
      if (variant === 'line' && !e.altKey) { start = round(snap(fromX(e.clientX, rect))); commit(start); }
      d.current = { x0: e.clientX, start: start, rect: rect, moved: false };
      e.currentTarget.setPointerCapture(e.pointerId);
      dragS[1](true); kbS[1](false);
      try { ref.current.focus({ preventScroll: true, focusVisible: false }); } catch (err) { ref.current.focus(); }
    }
    function onMove(e) {
      var g = d.current; if (!g) return;
      if (!g.moved && Math.abs(e.clientX - g.x0) <= 3) return;
      g.moved = true;
      var raw = g.start + ((e.clientX - g.x0) / g.rect.width) * range * (e.altKey ? 0.1 : 1);
      var over = raw < min ? (raw - min) / range * g.rect.width : raw > max ? (raw - max) / range * g.rect.width : 0;
      var st = over ? Math.sign(over) * Math.min(12, Math.sqrt(Math.abs(over)) * 1.8) : 0;
      var c = clamp(raw), v = round(snap(c));
      g.f = ticks.indexOf(v) >= 0 ? frac(v) : frac(c); // continuous fill, except while held in a detent
      g.stretch = st;
      // paint this frame directly, without a React render
      var el = ref.current, sx = 1 + Math.abs(st) / g.rect.width;
      el.style.setProperty('--f', g.f);
      el.style.setProperty('--sx', sx);
      el.style.setProperty('--sy', 1 - Math.abs(st) / g.rect.width * 0.9);
      el.style.transformOrigin = st < 0 ? 'right center' : 'left center';
      commit(v);
    }
    function onUp(e) {
      var g = d.current; d.current = null;
      if (g && !g.moved && variant === 'bar' && e && e.type === 'pointerup') commit(round(snap(fromX(g.x0, g.rect))));
      dragS[1](false); stretchS[1](0); visS[1](null);
      var el = ref.current; if (el) { el.style.setProperty('--sx', 1); el.style.setProperty('--sy', 1); }
    }
    function onKey(e) {
      var big = e.shiftKey ? 10 : 1, v = null;
      if (e.key === 'ArrowRight' || e.key === 'ArrowUp') v = value + step * big;
      else if (e.key === 'ArrowLeft' || e.key === 'ArrowDown') v = value - step * big;
      else if (e.key === 'PageUp') v = value + range / 10;
      else if (e.key === 'PageDown') v = value - range / 10;
      else if (e.key === 'Home') v = min;
      else if (e.key === 'End') v = max;
      if (e.key === 'Tab') kbS[1](true);
      if (v == null) return;
      kbS[1](true);
      e.preventDefault(); e.stopPropagation(); commit(round(v));
    }
    var reset = props.resetValue != null ? props.resetValue : initial;
    var f = d.current && d.current.f != null ? d.current.f : vis != null ? vis : frac(value);
    var w = d.current ? d.current.rect.width : 240;
    var common = {
      ref: ref, role: 'slider', tabIndex: 0, 'aria-label': props.label, 'aria-valuemin': min, 'aria-valuemax': max, 'aria-valuenow': value, 'aria-valuetext': fmt(value),
      'data-kb': kbS[0] ? 'true' : null,
      onPointerDown: onDown, onPointerMove: onMove, onPointerUp: onUp, onPointerCancel: onUp, onKeyDown: onKey,
      onKeyUp: function (e) { if (e.key === 'Tab') kbS[1](true); },
      onFocus: function () { if (!d.current) kbS[1](true); }, onBlur: function () { kbS[1](false); },
      onDoubleClick: function () { commit(reset); },
      title: props.title || 'Double-click to reset · hold ⌥ for fine control'
    };
    var st = d.current && d.current.stretch != null ? d.current.stretch : stretch;
    var sx = 1 + Math.abs(st) / w, sy = 1 - Math.abs(st) / w * 0.9;
    var vars = { '--f': f, '--sx': sx, '--sy': sy, transformOrigin: st < 0 ? 'right center' : 'left center' };

    if (variant === 'bar') {
      var inner = function (cls) {
        return h('span', { className: 'o-bar__content ' + cls, 'aria-hidden': cls === 'is-on' },
          props.symbol ? h(Symbol, { name: props.symbol, size: 16, effect: edgeS[0] ? 'bounce' : null, trigger: edgeS[0] }) : null,
          h('span', { className: 'o-bar__label' }, props.label),
          h('span', { className: 'o-bar__value', key: 'v' + bumpS[0] }, fmt(value)));
      };
      return h('div', Object.assign({}, common, {
        className: cx('o-bar', dragging && 'is-dragging', !dragging && ticks.indexOf(value) >= 0 && 'is-exact', props.className),
        style: Object.assign({ width: props.width }, vars, props.style)
      }),
        h('span', { className: 'o-bar__fill' }),
        ticks.filter(function (t) { return t > min && t < max; }).map(function (t) { return h('i', { key: t, className: cx('o-bar__tick', t <= value && 'is-passed'), style: { left: (frac(t) * 100) + '%' } }); }),
        inner('is-off'), inner('is-on'));
    }

    return h('div', { className: cx('o-slider', props.bare && 'o-slider--inline', dragging && 'is-dragging', ticks.indexOf(value) >= 0 && 'is-exact', props.className), style: Object.assign({ width: props.width }, props.style) },
      props.label && !props.bare ? h('div', { className: 'o-slider__head' },
        h('span', { className: 'o-slider__label' }, props.label),
        h('span', { className: 'o-slider__value' }, fmt(value))) : null,
      h('div', Object.assign({}, common, { className: 'o-slider__track', style: vars }),
        h('span', { className: 'o-slider__rail' }),
        h('span', { className: 'o-slider__fill' }),
        ticks.filter(function (t) { return t > min && t < max; }).map(function (t) { return h('i', { key: t, className: cx('o-slider__tick', t <= value && 'is-passed'), style: { left: (frac(t) * 100) + '%' } }); }),
        h('span', { className: 'o-slider__thumb', key: 'b' + bumpS[0] },
          h('span', { className: 'o-slider__bubble' }, fmt(value)))),
      props.bare && props.showValue !== false ? h('span', { className: 'o-slider__value' }, fmt(value)) : null);
  }

  /* ---------------- Segmented ---------------- */
  function Segmented(props) {
    var opts = props.options || [];
    var s = useState(props.defaultValue != null ? props.defaultValue : (opts[0] && (opts[0].value || opts[0])));
    var value = props.value != null ? props.value : s[0];
    var refs = useRef([]); var t = useState(null);
    useLayoutEffect(function () {
      var idx = opts.findIndex(function (o) { return (o.value || o) === value; });
      var el = refs.current[idx];
      if (el) t[1]({ left: el.offsetLeft, width: el.offsetWidth });
    }, [value]);
    return h('div', { className: 'o-seg', role: 'radiogroup', 'aria-label': props.label },
      t[0] ? h('span', { className: 'o-seg__thumb', style: t[0] }) : null,
      opts.map(function (o, i) {
        var val = o.value || o, on = val === value;
        return h('button', {
          key: val, type: 'button', role: 'radio', 'aria-checked': on, ref: function (el) { refs.current[i] = el; },
          className: cx('o-seg__item', on && 'is-on'),
          onClick: function () { s[1](val); props.onChange && props.onChange(val); }
        }, o.symbol ? h(Symbol, { name: o.symbol, size: 14 }) : null, o.label || o);
      }));
  }

  /* ---------------- Row / Group ---------------- */
  function Row(props) {
    return h('div', { className: 'o-row' },
      props.symbol ? h('span', { className: 'o-row__lead' }, h(Symbol, { name: props.symbol, size: 18 })) : null,
      h('div', { className: 'o-row__text' },
        h('div', { className: 'o-row__label' }, props.label),
        props.description ? h('div', { className: 'o-row__desc' }, props.description) : null),
      h('div', { className: 'o-row__ctl' }, props.control || props.children));
  }
  function Group(props) {
    return h('section', { className: 'o-group', style: props.style },
      props.title ? h('h3', { className: 'o-group__title' }, props.title) : null,
      h('div', { className: 'o-group__box' }, props.children),
      props.footer ? h('p', { className: 'o-group__foot' }, props.footer) : null);
  }

  /* ---------------- Surface: the one floating pattern ----------------
     density: xs tooltip · sm HUD/toast · md menu · lg coach mark · xl welcome.
     Slots, top to bottom: head (lead symbol, kicker, close) · title · body · keys · children · actions · progress. */
  function Caret(props) {
    if (!props.side || props.side === 'none') return null;
    var st = {};
    if (props.side === 'top' || props.side === 'bottom') st.left = props.at != null ? props.at : 24;
    if (props.side === 'left') st.top = props.at != null ? props.at : 20;
    // the window is 20 wide (or tall): centre it on `at`, or keep the old 14px square's position for a number
    if (props.side === 'left') st.marginTop = typeof props.at === 'string' ? -10 : -3; else st.marginLeft = typeof props.at === 'string' ? -10 : -3;
    return h('i', { className: 'o-caret o-caret--' + props.side, style: st, 'aria-hidden': true });
  }
  function Surface(props) {
    var d = props.density || 'md';
    var hasHead = props.lead || props.kicker || props.onClose || props.headEnd;
    return h('div', {
      className: cx('o-surface', 'o-surface--' + d, props.tone && 'o-surface--' + props.tone, props.glass && 'o-surface--glass', props.enter && 'is-enter', props.className),
      style: props.style, role: props.role
    },
      h(Caret, { side: props.caret, at: props.caretAt }),
      hasHead ? h('div', { className: 'o-surface__head' },
        props.lead ? h('span', { className: 'o-surface__lead' }, typeof props.lead === 'string' ? h(Symbol, { name: props.lead, effect: props.leadEffect, trigger: props.leadTrigger, size: 18 }) : props.lead) : null,
        props.kicker ? h('span', { className: cx('o-surface__kicker', props.done && 'is-done') }, props.kicker) : null,
        props.headEnd ? h('span', { style: { marginLeft: 'auto' } }, props.headEnd) : null,
        props.onClose ? h(Button, { variant: 'ghost', size: 'sm', icon: 'xmark', label: 'Close', className: 'o-surface__close', onClick: props.onClose }) : null) : null,
      props.title ? h('div', { className: 'o-surface__title' }, props.title) : null,
      props.body ? h('div', { className: 'o-surface__body' }, props.body) : null,
      props.keys ? h('div', { className: 'o-surface__keys' }, props.keys) : null,
      props.children,
      props.actions ? h('div', { className: 'o-surface__actions' }, props.actions) : null,
      props.progress != null ? h('div', { className: 'o-surface__progress' }, h('i', { style: { width: Math.round(props.progress * 100) + '%' } })) : null);
  }

  /* ---------------- Menu ----------------
     items: {type:'item'|'check'|'radio'|'switch'|'sub'|'label'|'sep'|'custom', id, label, symbol, shortcut, value,
             keywords, group (radio), checked, danger, disabled, items (sub), render (custom), effect}
     Hover opens a submenu after --sub-delay; → opens and focuses it, ← closes; ↑↓ move; ↩ selects; typing filters
     every level at once (results flattened with a breadcrumb). */
  function actionable(it) { return it && !it.disabled && /^(item|check|radio|switch|sub)$/.test(it.type || 'item'); }
  function flatten(items, trail, out) {
    (items || []).forEach(function (it) {
      var t = it.type || 'item';
      if (t === 'sub') flatten(it.items, trail.concat(it.label), out);
      else if (actionable(it)) out.push(Object.assign({}, it, { crumb: trail }));
    });
    return out;
  }
  function seedState(items, st) {
    (items || []).forEach(function (it) {
      var t = it.type || 'item';
      if ((t === 'check' || t === 'switch') && it.id) st.checks[it.id] = !!it.checked;
      if (t === 'radio' && it.checked) st.radios[it.group] = it.id;
      if (t === 'sub') seedState(it.items, st);
    });
    return st;
  }

  function MenuList(props) {
    var items = props.items, ctx = props.ctx, depth = props.depth || 0;
    var hiS = useState(props.initialHi != null ? props.initialHi : -1), hi = hiS[0], setHi = hiS[1];
    var openS = useState(props.initialOpen != null ? props.initialOpen : -1), open = openS[0], setOpen = openS[1];
    var timer = useRef(null);
    var ref = useRef(null);
    var queryS = useState(props.query || ''), query = queryS[0], setQuery = queryS[1];
    var hasSearch = depth === 0 && items.some(function (i) { return i.type === 'search'; });
    var searchItem = items.find(function (i) { return i.type === 'search'; });

    var shown = useMemo(function () {
      if (!query) return items.filter(function (i) { return i.type !== 'search' && !i.hidden; });
      var q = query.toLowerCase().split(/\s+/).filter(Boolean);
      var res = flatten(items, [], []).filter(function (it) {
        var hay = (it.label + ' ' + (it.crumb || []).join(' ') + ' ' + (it.keywords || '')).toLowerCase();
        return q.every(function (w) { return hay.indexOf(w) >= 0; });
      });
      var groups = {}, order = [];
      res.forEach(function (r) { var g = r.crumb[0] || 'Commands'; if (!groups[g]) { groups[g] = []; order.push(g); } groups[g].push(r); });
      var out = [];
      order.forEach(function (g, i) { if (i) out.push({ type: 'sep' }); out.push({ type: 'label', label: g }); groups[g].forEach(function (r) { out.push(r); }); });
      return out;
    }, [query, items]);

    useEffect(function () { if (query) { var first = shown.findIndex(actionable); setHi(first); setOpen(-1); } }, [query]);
    useEffect(function () { if (props.autoFocus && ref.current) { var inp = ref.current.querySelector('input'); (inp || ref.current).focus({ preventScroll: true }); } }, []);

    function move(dir) {
      var n = shown.length, i = hi;
      for (var k = 0; k < n; k++) { i = (i + dir + n) % n; if (actionable(shown[i])) { setHi(i); return; } }
    }
    function select(it, i) {
      var t = it.type || 'item';
      if (t === 'sub') { setOpen(i); return; }
      if (t === 'check' || t === 'switch') ctx.toggle(it.id);
      else if (t === 'radio') ctx.pick(it.group, it.id);
      ctx.fire(it);
    }
    function onKey(e) {
      if (props.childOpenRef && props.childOpenRef.current && open >= 0 && e.target === ref.current) return;
      if (e.key === 'ArrowDown') { e.preventDefault(); move(1); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); move(-1); }
      else if (e.key === 'ArrowRight' && shown[hi] && shown[hi].type === 'sub') { e.preventDefault(); setOpen(hi); }
      else if (e.key === 'ArrowLeft' && depth > 0) { e.preventDefault(); props.onBack && props.onBack(); }
      else if (e.key === 'Escape') { e.preventDefault(); if (query) setQuery(''); else if (depth > 0) props.onBack && props.onBack(); }
      else if (e.key === 'Enter' && shown[hi]) { e.preventDefault(); select(shown[hi], hi); }
      else if (hasSearch && e.key.length === 1 && !e.metaKey && e.target.tagName !== 'INPUT') {
        var inp = ref.current.querySelector('input'); if (inp) inp.focus();
      }
      e.stopPropagation();
    }
    function enter(i, it) {
      setHi(i);
      clearTimeout(timer.current);
      if (it.type === 'sub') timer.current = setTimeout(function () { setOpen(i); }, 100);
      else if (open >= 0) timer.current = setTimeout(function () { setOpen(-1); }, 180); // grace period: diagonal moves into an open submenu
    }

    function trail(it) {
      var t = it.type || 'item';
      if (t === 'sub') return h('span', { className: 'o-menu__chev' }, h(Symbol, { name: 'chevron.right', size: 12, weight: 'medium' }));
      if (t === 'switch') return h('span', { style: { marginLeft: 'auto', display: 'inline-flex', gap: 8, alignItems: 'center' } },
        it.shortcut ? h('span', { className: 'o-menu__sc' }, h(Shortcut, { keys: it.shortcut })) : null,
        h(Switch, { checked: !!ctx.checks[it.id], label: it.label, onChange: function () { ctx.toggle(it.id); ctx.fire(it); } }));
      if (it.shortcut) return h('span', { className: 'o-menu__sc' }, h(Shortcut, { keys: it.shortcut }));
      return null;
    }
    function lead(it) {
      var t = it.type || 'item';
      if (t === 'check') return ctx.checks[it.id] ? h(Symbol, { name: 'checkmark', size: 14, weight: 'semibold', className: 'o-menu__check', effect: 'draw', trigger: String(ctx.checks[it.id]) }) : null;
      if (t === 'radio') return ctx.radios[it.group] === it.id ? h('i', { className: 'o-menu__radio' }) : null;
      return it.symbol ? h(Symbol, { name: it.symbol, size: 15, effect: it.id && ctx.fx[it.id] ? it.effect || 'bounce' : null, trigger: it.id ? ctx.fx[it.id] : null }) : null;
    }

    return h('div', {
      ref: ref, tabIndex: -1, role: 'menu', onKeyDown: onKey,
      className: cx('o-surface o-surface--md o-menu', depth > 0 && 'o-menu--sub', props.glass && 'o-surface--glass', props.className),
      style: props.style, onMouseLeave: function () { if (open < 0) setHi(-1); }
    },
      hasSearch ? h('div', { className: 'o-menu__search' },
        h(Symbol, { name: 'magnifyingglass', size: 15 }),
        h('input', { value: query, placeholder: searchItem.placeholder || 'Search commands…', onChange: function (e) { setQuery(e.target.value); }, onKeyDown: onKey, 'aria-label': 'Search commands' }),
        searchItem.shortcut ? h(Kbd, { keys: searchItem.shortcut }) : null) : null,
      query && !shown.length ? h('div', { className: 'o-menu__empty' }, 'No command matches “' + query + '”') : null,
      shown.map(function (it, i) {
        var t = it.type || 'item';
        if (t === 'sep') return h('div', { key: 's' + i, className: 'o-menu__sep', role: 'separator' });
        if (t === 'label') return h('div', { key: 'l' + i, className: 'o-menu__label' }, it.label, it.shortcut ? h(Kbd, { keys: it.shortcut }) : null);
        if (t === 'custom') return h('div', { key: 'c' + i, className: 'o-menu__custom' }, it.render(ctx));
        if (t === 'footer') return h('div', { key: 'f' + i, className: 'o-menu__foot' }, it.render(ctx));
        var isOpen = open === i && t === 'sub';
        return h('div', { key: (it.id || it.label) + i, className: 'o-menu__slot' },
          h('div', {
            role: t === 'check' ? 'menuitemcheckbox' : t === 'radio' ? 'menuitemradio' : 'menuitem',
            'aria-haspopup': t === 'sub' ? 'menu' : undefined, 'aria-expanded': t === 'sub' ? isOpen : undefined,
            'aria-disabled': it.disabled || undefined,
            className: cx('o-menu__item', hi === i && 'is-hi', isOpen && 'is-open', it.danger && 'is-danger', it.disabled && 'is-disabled'),
            onMouseEnter: function () { if (!it.disabled) enter(i, it); },
            onClick: function () { if (!it.disabled) select(it, i); }
          },
            h('span', { className: 'o-menu__lead' }, lead(it)),
            h('span', { className: 'o-menu__text' }, it.label,
              it.value ? h('span', { className: 'o-menu__value' }, it.value) : null,
              it.crumb && it.crumb.length ? h('span', { className: 'o-menu__crumb' }, it.crumb[it.crumb.length - 1]) : null),
            trail(it)),
          isOpen ? h(MenuList, {
            items: it.items, ctx: ctx, depth: depth + 1, glass: props.glass, autoFocus: !props.staticOpen, initialHi: props.subHi,
            className: it.wide ? 'o-menu--wide' : null, style: it.width ? { width: it.width } : null,
            onBack: function () { setOpen(-1); if (ref.current) ref.current.focus({ preventScroll: true }); }
          }) : null);
      }));
  }

  function Menu(props) {
    var st = useState(function () { return seedState(props.items, { checks: {}, radios: {} }); });
    var fx = useState({});
    var ctx = {
      checks: st[0].checks, radios: st[0].radios, fx: fx[0],
      toggle: function (id) { st[1](function (s) { var c = Object.assign({}, s.checks); c[id] = !c[id]; return { checks: c, radios: s.radios }; }); },
      pick: function (g, id) { st[1](function (s) { var r = Object.assign({}, s.radios); r[g] = id; return { checks: s.checks, radios: r }; }); },
      fire: function (it) {
        if (it.id) fx[1](function (f) { var n = Object.assign({}, f); n[it.id] = (n[it.id] || 0) + 1; return n; });
        props.onSelect && props.onSelect(it);
      }
    };
    return h('div', { className: 'o-root', style: { position: 'relative', display: 'inline-block' } },
      h(MenuList, { items: props.items, ctx: ctx, glass: props.glass, initialOpen: props.openIndex, initialHi: props.highlight, subHi: props.subHighlight, staticOpen: props.openIndex != null, query: props.query, autoFocus: props.autoFocus, style: props.style, className: props.className }));
  }

  function CommandMenu(props) {
    var items = [{ type: 'search', placeholder: props.placeholder || 'Type a command or search…', shortcut: props.shortcut || ['cmd', 'k'] }].concat(props.items || []);
    return h(Menu, Object.assign({}, props, { items: items, style: Object.assign({ width: props.width || 360 }, props.style) }));
  }

  /* ---------------- Tooltip (Surface xs, inverted) ---------------- */
  function Tooltip(props) {
    var s = useState(!!props.open); var show = props.open != null ? props.open : s[0];
    var t = useRef(null);
    var side = props.side || 'bottom';
    var tip = h(Surface, { density: 'xs', className: 'o-tip', role: 'tooltip', caret: side === 'bottom' ? 'top' : side === 'top' ? 'bottom' : 'left', caretAt: '50%' },
      props.label, props.keys ? h(Kbd, { keys: props.keys, then: props.then }) : null);
    if (!props.children) return h('span', { className: 'o-root' }, tip);
    return h('span', {
      className: 'o-root o-tip-anchor',
      onMouseEnter: function () { clearTimeout(t.current); t.current = setTimeout(function () { s[1](true); }, props.delay != null ? props.delay : 500); },
      onMouseLeave: function () { clearTimeout(t.current); s[1](false); }
    }, props.children, show ? h('span', { className: 'o-tip-pop o-tip-pop--' + side }, tip) : null);
  }

  /* ---------------- CoachMark (Surface lg) ---------------- */
  function CoachMark(props) {
    var total = props.total, step = props.step;
    var dots = total ? h('span', { className: 'o-surface__dots', 'aria-hidden': true },
      Array.from({ length: total }, function (_, i) { return h('i', { key: i, className: cx(i + 1 === step && 'is-on', i + 1 < step && 'is-past') }); })) : null;
    var keys = props.keys ? h(React.Fragment, null,
      h(Kbd, { keys: props.keys, size: 'lg', pressed: props.pressed }),
      props.done ? h('span', { className: 'o-surface__done' }, h(Symbol, { name: 'checkmark.circle.fill', effect: 'appear', size: 18 }), props.doneText || 'Nice') : h('span', { className: 'o-surface__hint' }, h(Symbol, { name: 'cursorarrow.rays', effect: 'pulse', size: 16 }), props.hint || 'Press it now')) : null;
    return h('div', { className: 'o-root', style: { display: 'inline-block' } },
      h(Surface, {
        density: 'lg', tone: props.tone === 'plain' ? null : 'accent', glass: props.tone === 'plain' && props.glass, caret: props.caret, caretAt: props.caretAt, enter: props.enter, style: props.style,
        kicker: props.kicker || (total ? 'Step ' + step + ' of ' + total : null), done: props.done,
        headEnd: props.onSkip ? h(Button, { variant: 'ghost', size: 'sm', onClick: props.onSkip }, 'Skip tour') : null,
        title: props.title, body: props.body, keys: keys,
        actions: (props.onNext || props.onBack || dots) ? h(React.Fragment, null,
          dots, h('span', { className: 'o-spacer' }),
          props.onBack ? h(Button, { variant: 'ghost', size: 'sm', onClick: props.onBack }, 'Back') : null,
          props.onNext ? h(Button, { variant: 'primary', size: 'sm', onClick: props.onNext, shortcut: ['return'] }, props.nextLabel || 'Next') : null) : null
      }, props.children));
  }

  /* ---------------- LayoutThumb ---------------- */
  var LAYOUTS = {
    'tall': { title: 'Tall', panes: [[0, 0, .56, 1], [.56, 0, .44, .5], [.56, .5, .44, .5]], desc: 'Main on the left, the rest stacked on the right' },
    'tall-right': { title: 'Tall Right', panes: [[.44, 0, .56, 1], [0, 0, .44, .5], [0, .5, .44, .5]], desc: 'Main on the right, the rest stacked on the left' },
    'wide': { title: 'Wide', panes: [[0, 0, 1, .56], [0, .56, .5, .44], [.5, .56, .5, .44]], desc: 'Main on top, the rest side by side below' },
    'middle-wide': { title: 'Middle Wide', panes: [[.25, 0, .5, 1], [0, 0, .25, .5], [0, .5, .25, .5], [.75, 0, .25, 1]], desc: 'Main in the middle, the rest split left and right' },
    'fullscreen': { title: 'Fullscreen', panes: [[0, 0, 1, 1]], desc: 'Every window fills the screen' },
    'column': { title: 'Column', panes: [[0, 0, .3333, 1], [.3333, 0, .3334, 1], [.6667, 0, .3333, 1]], desc: 'Equal-width columns' },
    'row': { title: 'Row', panes: [[0, 0, 1, .3333], [0, .3333, 1, .3334], [0, .6667, 1, .3333]], desc: 'Equal-height rows' },
    'floating': { title: 'Floating', panes: [[.06, .1, .52, .56], [.4, .34, .54, .56]], desc: 'Leave windows where you put them' },
    'bsp': { title: 'BSP', panes: [[0, 0, .5, 1], [.5, 0, .5, .5], [.5, .5, .25, .5], [.75, .5, .25, .5]], desc: 'Each window splits the space of the previous one' },
    'three-column-left': { title: '3 Column Left', panes: [[0, 0, .5, 1], [.5, 0, .25, 1], [.75, 0, .25, 1]], desc: 'Main on the left, two columns to its right' },
    'three-column-middle': { title: '3 Column Middle', panes: [[.25, 0, .5, 1], [0, 0, .25, 1], [.75, 0, .25, 1]], desc: 'Main in the middle column' },
    'three-column-right': { title: '3 Column Right', panes: [[.5, 0, .5, 1], [0, 0, .25, 1], [.25, 0, .25, 1]], desc: 'Main on the right, two columns to its left' },
    'two-pane': { title: 'Two Pane', panes: [[0, 0, .5, 1], [.5, 0, .5, 1]], desc: 'Main on the left, one other window on the right' }
  };
  function LayoutThumb(props) {
    var L = LAYOUTS[props.layout] || LAYOUTS.tall;
    var w = props.width || 48, hh = props.height || Math.round(w * 0.625);
    var W = 160, H = 100, g = 4;
    return h('span', { className: cx('o-thumb', props.selected && 'is-selected'), style: { width: w, height: hh }, title: props.title ? L.title : undefined },
      h('svg', { viewBox: '0 0 ' + W + ' ' + H, 'aria-hidden': true }, L.panes.map(function (p, i) {
        return h('rect', { key: i, className: cx('pane', i === 0 && 'main'), x: p[0] * W + g / 2, y: p[1] * H + g / 2, width: p[2] * W - g, height: p[3] * H - g, rx: 6 });
      })));
  }
  LayoutThumb.layouts = LAYOUTS;

  function LayoutPicker(props) {
    var keys = Object.keys(LAYOUTS);
    var s = useState(props.defaultValue || 'tall'); var value = props.value != null ? props.value : s[0];
    var hov = useState(null); var shown = LAYOUTS[hov[0] || value];
    var cols = props.columns || 5;
    return h('div', { className: 'o-picker' },
      h('div', { className: 'o-picker__grid', style: { gridTemplateColumns: 'repeat(' + cols + ', minmax(0, 1fr))' }, onMouseLeave: function () { hov[1](null); } }, keys.map(function (k) {
        var on = value === k;
        return h('button', { key: k, type: 'button', 'aria-label': LAYOUTS[k].title, 'aria-pressed': on,
          className: cx('o-picker__cell', on && 'is-on'), onMouseEnter: function () { hov[1](k); },
          onClick: function (e) { e.stopPropagation(); s[1](k); props.onChange && props.onChange(k); } },
          h(LayoutThumb, { layout: k, selected: on, width: props.thumb || 40 }));
      })),
      h('div', { className: 'o-picker__info' }, h('span', { className: 'o-picker__name' }, shown.title), h('span', { className: 'o-picker__desc' }, shown.desc)));
  }

  /* ---------------- HUD (Surface sm, glass) ---------------- */
  function HUD(props) {
    var L = props.layout && LAYOUTS[props.layout];
    if (props.warning) return h('div', { className: 'o-root', style: { display: 'inline-block' } },
      h('div', { className: 'o-surface o-surface--glass o-hud o-hud--warn' + (props.pop ? ' is-pop' : ''), key: props.pop, role: 'status' },
        h(Symbol, { name: 'exclamationmark.triangle.fill', effect: 'wiggle', trigger: props.pop, size: 18 }),
        h('span', { className: 'o-hud__label' }, props.label)));
    return h('div', { className: 'o-root', style: { display: 'inline-block' } },
      h('div', { className: 'o-surface o-surface--glass o-hud' + (props.pop ? ' is-pop' : ''), key: props.pop, role: 'status' },
        L ? h(LayoutThumb, { layout: props.layout, width: 120, height: 75 }) : null,
        h('span', { className: 'o-hud__label' }, props.label || (L && L.title)),
        props.keys ? h('span', { className: 'o-caption', style: { display: 'inline-flex', gap: 6, alignItems: 'center' } }, props.hint || 'Next', h(Kbd, { keys: props.keys })) : null));
  }

  /* ---------------- WorkspaceStrip ---------------- */
  function WorkspaceStrip(props) {
    var n = props.count || 9;
    var s = useState(props.current || 1); var cur = props.onPick && props.current != null ? props.current : s[0];
    var occ = props.occupied || [];
    return h('div', { className: 'o-ws', role: 'radiogroup', 'aria-label': 'Workspaces' },
      Array.from({ length: n }, function (_, i) {
        var k = i + 1;
        return h('button', {
          key: k, type: 'button', role: 'radio', 'aria-checked': cur === k, title: 'Workspace ' + k,
          className: cx('o-ws__pill', cur === k && 'is-current', occ.indexOf(k) >= 0 && 'has-windows'),
          onClick: function (e) { e.stopPropagation(); s[1](k); props.onPick && props.onPick(k); }
        }, k === 10 ? 0 : k);
      }));
  }

  /* ---------------- The real Ouch menu, as data (shared by previews) ---------------- */
  function ouchMenu(opts) {
    opts = opts || {};
    var layoutItems = Object.keys(LAYOUTS).map(function (k) { return { type: 'radio', group: 'layout', id: 'layout-' + k, label: LAYOUTS[k].title, checked: k === 'tall', keywords: 'layout ' + LAYOUTS[k].desc }; });
    return [
      { type: 'search', placeholder: 'Search commands…', shortcut: ['cmd', 'k'] },
      { type: 'label', label: 'Workspace 2 · Tall', shortcut: ['cmd', 'caps'] },
      { type: 'custom', render: function () { return h(WorkspaceStrip, { current: 2, occupied: [1, 2, 3, 5] }); } },
      { type: 'switch', id: 'tiling', label: 'Tiling', checked: true, shortcut: ['shift', 'T'], keywords: 'enable disable toggle', hidden: true },
      { type: 'sep' },
      { type: 'sub', label: 'Layout', value: 'Tall', symbol: 'square.grid.2x2', width: 260, items: [
        { type: 'label', label: 'Layouts', shortcut: ['N'] },
        { type: 'custom', render: function (ctx) {
          return h(LayoutPicker, { columns: 4, thumb: 44, value: (ctx.radios.layout || 'layout-tall').slice(7), onChange: function (k) { ctx.pick('layout', 'layout-' + k); } });
        } },
        { type: 'sep' },
        { id: 'prev-layout', label: 'Previous Layout', symbol: 'chevron.left', shortcut: ['P'] }
      ].concat(layoutItems.map(function (it) { return Object.assign({ hidden: true }, it); })) },
      { type: 'sub', label: 'Window', symbol: 'macwindow', items: [
        { id: 'retile', label: 'Retile', symbol: 'arrow.triangle.2.circlepath', effect: 'rotate', shortcut: ['Z'] },
        { id: 'swap', label: 'Swap with Main', symbol: 'arrow.left.arrow.right', shortcut: ['M'] },
        { type: 'check', id: 'float', label: 'Float Window', shortcut: ['V'], keywords: 'floating' },
        { id: 'full', label: 'Fullscreen', symbol: 'arrow.up.left.and.arrow.down.right', shortcut: ['F'] },
        { type: 'sep' },
        { type: 'sub', label: 'Send to Workspace', symbol: 'rectangle.3.group', items: [1, 2, 3, 4, 5, 6, 7, 8, 9].map(function (k) { return { id: 'send-' + k, label: 'Workspace ' + k, shortcut: ['shift', String(k)], keywords: 'move send' }; }) },
        { label: 'Next Display', symbol: 'menubar.rectangle', shortcut: ['shift', 'W'], id: 'mon' }
      ] },
      { type: 'sub', label: 'Configs', symbol: 'slider.horizontal.3', items: [
        { type: 'label', label: 'Keyboard' },
        { type: 'radio', group: 'kb', id: 'kb-vim', label: 'VIM', checked: true },
        { type: 'radio', group: 'kb', id: 'kb-wasd', label: 'WASD' },
        { type: 'sep' },
        { type: 'label', label: 'Animation' },
        { type: 'radio', group: 'anim', id: 'an-spring', label: 'Spring', checked: true },
        { type: 'radio', group: 'anim', id: 'an-ease', label: 'Ease Out' },
        { type: 'radio', group: 'anim', id: 'an-off', label: 'Off' },
        { type: 'sep' },
        { id: 'import', label: 'Import…', symbol: 'square.and.arrow.down' },
        { id: 'export', label: 'Export…', symbol: 'square.and.arrow.up' }
      ] },
      { type: 'sep' },
      { id: 'settings', label: 'Settings…', symbol: 'gearshape', effect: 'rotate', shortcut: ['cmd', ','] },
      { id: 'tour', label: 'Keyboard Tour…', symbol: 'keyboard', effect: 'bounce' },
      { type: 'sub', label: 'Help', symbol: 'questionmark.circle', items: [
        { id: 'map', label: 'Shortcut Map', symbol: 'keyboard', shortcut: ['cmd', '/'] },
        { id: 'conf', label: 'Open Config File', symbol: 'doc.text' },
        { id: 'reload', label: 'Reload Config', symbol: 'arrow.triangle.2.circlepath', effect: 'rotate', shortcut: ['shift', 'R'] },
        { type: 'sep' },
        { id: 'updates', label: 'Check for Updates…', symbol: 'arrow.down.circle', effect: 'bounce' },
        { type: 'check', id: 'beta', label: 'Include Beta Releases' }
      ] },
      { type: 'sep' },
      { type: 'footer', render: function () { return h(React.Fragment, null, h('span', null, 'Ouch 0.4'), h('span', { className: 'o-badge' }, h(Symbol, { name: 'arrow.down.circle', size: 12 }), '0.5 ready'), h('span', { className: 'o-menu__sc' }, h(Shortcut, { keys: ['cmd', 'Q'] }))); } }
    ];
  }

  window.Ouch = {
    Symbol: Symbol, Kbd: Kbd, Button: Button, Switch: Switch, Slider: Slider, Segmented: Segmented, Row: Row, Group: Group,
    Surface: Surface, Menu: Menu, CommandMenu: CommandMenu, Tooltip: Tooltip, CoachMark: CoachMark, HUD: HUD,
    LayoutThumb: LayoutThumb, LayoutPicker: LayoutPicker, WorkspaceStrip: WorkspaceStrip, ouchMenu: ouchMenu,
    palettes: [
      { id: 'ouch', name: 'Ouch', light: 'ouch-light', dark: 'ouch-dark' }
    ]
  };
})();
