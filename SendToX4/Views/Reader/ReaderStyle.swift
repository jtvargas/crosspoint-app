import Foundation

/// CSS and JS injected into the reader's combined document.
/// Apple News-style typography: centered measure, serif body, generous
/// line height, automatic light/dark support.
enum ReaderStyle {

    static let css = """
    :root {
      color-scheme: light dark;
      --font-scale: 1.0;
    }
    * { box-sizing: border-box; }
    html { -webkit-text-size-adjust: 100%; scroll-behavior: smooth; }
    body {
      font-family: ui-serif, Georgia, 'Times New Roman', serif;
      font-size: calc(19px * var(--font-scale));
      line-height: 1.6;
      max-width: 42em;
      margin: 0 auto;
      padding: 1.25em 1.25em 6em;
      text-rendering: optimizeLegibility;
      word-wrap: break-word;
      background: #FFFFFF;
      color: #1D1D1F;
    }
    h1 {
      font-size: 1.7em;
      line-height: 1.2;
      font-weight: 800;
      letter-spacing: -0.015em;
      margin: 1.2em 0 0.5em;
    }
    h2 { font-size: 1.3em; line-height: 1.25; font-weight: 700; margin: 1.4em 0 0.4em; }
    h3 { font-size: 1.1em; font-weight: 700; margin: 1.2em 0 0.3em; }
    p { margin: 0 0 0.9em; }
    blockquote {
      margin: 1.2em 0;
      padding: 0.1em 1.2em;
      border-left: 3px solid rgba(0, 128, 128, 0.55);
      font-style: italic;
      opacity: 0.9;
    }
    pre, code { font-family: ui-monospace, Menlo, monospace; font-size: 0.85em; }
    pre { overflow-x: auto; padding: 0.8em; border-radius: 10px; background: rgba(127,127,127,0.12); }
    img { max-width: 100%; height: auto; border-radius: 10px; display: block; margin: 1em auto; }
    figure { margin: 1.2em 0; text-align: center; }
    figcaption { font-size: 0.82em; font-style: italic; opacity: 0.7; margin-top: 0.4em; }
    hr { border: none; border-top: 1px solid rgba(127,127,127,0.35); margin: 2em 20%; }
    section + section { margin-top: 2.5em; padding-top: 1.5em; border-top: 1px solid rgba(127,127,127,0.25); }
    ul, ol { padding-left: 1.4em; margin: 0 0 0.9em; }
    li { margin-bottom: 0.35em; }
    @media (prefers-color-scheme: dark) {
      body { background: #000000; color: #E8E8ED; }
      pre { background: rgba(255,255,255,0.08); }
    }
    """

    /// Reports scroll progress (0...1) to the native side via the "reader"
    /// message handler, throttled to animation frames.
    static let progressScript = """
    (function() {
      var ticking = false;
      function report() {
        var el = document.documentElement;
        var max = el.scrollHeight - el.clientHeight;
        var progress = max > 0 ? (el.scrollTop || document.body.scrollTop) / max : 0;
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.reader) {
          window.webkit.messageHandlers.reader.postMessage({ progress: Math.max(0, Math.min(1, progress)) });
        }
        ticking = false;
      }
      window.addEventListener('scroll', function() {
        if (!ticking) { window.requestAnimationFrame(report); ticking = true; }
      }, { passive: true });

      window.crossxSetFontScale = function(scale) {
        document.documentElement.style.setProperty('--font-scale', scale);
      };
      window.crossxRestoreProgress = function(progress) {
        var el = document.documentElement;
        var max = el.scrollHeight - el.clientHeight;
        if (max > 0 && progress > 0) { window.scrollTo(0, max * progress); }
      };
      window.crossxJumpToAnchor = function(anchor) {
        var target = document.getElementById(anchor);
        if (target) { target.scrollIntoView({ behavior: 'smooth', block: 'start' }); }
      };
    })();
    """
}
