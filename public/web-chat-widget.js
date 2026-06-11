/* Dr Chalita le Roux — website booking widget.
 * Self-contained, CSS-isolated (Shadow DOM). Talks to the SAME AI booking brain as WhatsApp
 * via POST /api/v1/web_chat. Drop-in on any site:
 *   <script src="https://.../web-chat-widget.js" data-endpoint="https://.../api/v1/web_chat"></script>
 * Off unless the API has WEB_CHAT_ENABLED on (the flip-switch).
 */
(function () {
  if (window.__drcWidgetLoaded) return;
  window.__drcWidgetLoaded = true;

  var script = document.currentScript || {};
  var ENDPOINT = (script.getAttribute && script.getAttribute('data-endpoint')) || '/api/v1/web_chat';
  var PRACTICE = 'Dr Chalita le Roux';

  // --- brand (practice gold / cream) — tune to the website palette if needed ---
  var C = { gold: '#B58B2A', goldDark: '#8C6A1E', cream: '#FBF6EC', ink: '#2E2417', soft: '#F3E9D2', white: '#ffffff', muted: '#7a6b50' };

  // --- session id (anonymous, persistent) ---
  var SKEY = 'drc_web_chat_session';
  var sessionId = '';
  try { sessionId = localStorage.getItem(SKEY) || ''; } catch (e) {}
  if (!sessionId) {
    sessionId = 'web-' + (Date.now().toString(36)) + '-' + Math.random().toString(36).slice(2, 10);
    try { localStorage.setItem(SKEY, sessionId); } catch (e) {}
  }

  var contact = { name: '', phone: '', consent: false, captured: false };
  var openedOnce = false;

  // --- mount + shadow root ---
  var host = document.createElement('div');
  host.id = 'drc-web-chat';
  host.style.cssText = 'position:fixed;z-index:2147483000;bottom:0;right:0;';
  document.body.appendChild(host);
  var root = host.attachShadow ? host.attachShadow({ mode: 'open' }) : host;

  var css = '\
  :host,*{box-sizing:border-box;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif}\
  .bubble{position:fixed;bottom:20px;right:20px;width:62px;height:62px;border-radius:50%;background:' + C.gold + ';\
    box-shadow:0 8px 24px rgba(0,0,0,.28);cursor:pointer;display:flex;align-items:center;justify-content:center;border:3px solid ' + C.white + '}\
  .bubble svg{width:30px;height:30px;fill:' + C.white + '}\
  .teaser{position:fixed;bottom:30px;right:92px;max-width:250px;background:' + C.white + ';color:' + C.ink + ';\
    padding:12px 14px;border-radius:14px 14px 2px 14px;box-shadow:0 6px 20px rgba(0,0,0,.18);font-size:13.5px;line-height:1.4;cursor:pointer}\
  .teaser b{color:' + C.goldDark + '}\
  .panel{position:fixed;bottom:20px;right:20px;width:374px;max-width:calc(100vw - 24px);height:560px;max-height:calc(100vh - 40px);\
    background:' + C.cream + ';border-radius:18px;box-shadow:0 16px 48px rgba(0,0,0,.32);display:none;flex-direction:column;overflow:hidden}\
  .panel.open{display:flex}\
  .hd{background:' + C.gold + ';color:' + C.white + ';padding:14px 16px;display:flex;align-items:center;gap:10px}\
  .hd .av{width:40px;height:40px;border-radius:50%;background:' + C.white + ';display:flex;align-items:center;justify-content:center;font-weight:700;color:' + C.goldDark + ';font-size:17px}\
  .hd .t{flex:1;min-width:0}.hd .t .n{font-weight:700;font-size:14.5px}.hd .t .s{font-size:11.5px;opacity:.9;display:flex;align-items:center;gap:5px}\
  .hd .dot{width:7px;height:7px;border-radius:50%;background:#7CFC9A;display:inline-block}\
  .hd .x{cursor:pointer;opacity:.85;font-size:20px;line-height:1;padding:2px 4px}\
  .msgs{flex:1;overflow-y:auto;padding:14px;display:flex;flex-direction:column;gap:9px}\
  .m{max-width:84%;padding:9px 12px;border-radius:14px;font-size:13.7px;line-height:1.45;white-space:pre-wrap;word-wrap:break-word}\
  .m.bot{background:' + C.white + ';color:' + C.ink + ';align-self:flex-start;border-bottom-left-radius:3px;box-shadow:0 1px 3px rgba(0,0,0,.06)}\
  .m.me{background:' + C.gold + ';color:' + C.white + ';align-self:flex-end;border-bottom-right-radius:3px}\
  .m.bot a{color:' + C.goldDark + ';text-decoration:underline;word-break:break-word;font-weight:600}\
  .chips{display:flex;flex-wrap:wrap;gap:7px;padding:0 14px 6px}\
  .chip{background:' + C.white + ';border:1.5px solid ' + C.soft + ';color:' + C.goldDark + ';border-radius:18px;padding:7px 12px;font-size:12.7px;cursor:pointer;font-weight:600}\
  .chip:hover{background:' + C.soft + '}\
  .typing{align-self:flex-start;background:' + C.white + ';padding:10px 13px;border-radius:14px;border-bottom-left-radius:3px}\
  .typing span{display:inline-block;width:6px;height:6px;margin:0 1px;border-radius:50%;background:' + C.muted + ';animation:b 1.2s infinite}\
  .typing span:nth-child(2){animation-delay:.2s}.typing span:nth-child(3){animation-delay:.4s}\
  @keyframes b{0%,60%,100%{opacity:.3}30%{opacity:1}}\
  .form{padding:10px 14px;display:none;flex-direction:column;gap:7px;background:' + C.soft + '}\
  .form.show{display:flex}.form input{padding:8px 10px;border:1px solid #d9c79c;border-radius:9px;font-size:13px}\
  .form label{font-size:11.5px;color:' + C.ink + ';display:flex;gap:6px;align-items:flex-start;line-height:1.35}\
  .form button{background:' + C.gold + ';color:#fff;border:0;border-radius:9px;padding:9px;font-weight:700;cursor:pointer;font-size:13px}\
  .bar{display:flex;gap:8px;padding:10px;border-top:1px solid ' + C.soft + ';background:' + C.cream + '}\
  .bar input{flex:1;border:1px solid #d9c79c;border-radius:20px;padding:9px 13px;font-size:13.5px;outline:none}\
  .bar button{background:' + C.gold + ';border:0;border-radius:50%;width:38px;height:38px;cursor:pointer;display:flex;align-items:center;justify-content:center}\
  .bar button svg{width:18px;height:18px;fill:#fff}\
  .foot{text-align:center;font-size:10px;color:' + C.muted + ';padding:0 0 7px}\
  @media(max-width:480px){.panel{width:100vw;height:100vh;max-height:100vh;border-radius:0;bottom:0;right:0}}\
  ';

  var wrap = document.createElement('div');
  wrap.innerHTML =
    '<style>' + css + '</style>' +
    '<div class="teaser" id="teaser">👋 Looking for a dentist in Roodepoort or the West Rand? I can check live availability and book you in under a minute — even after hours.</div>' +
    '<div class="bubble" id="bubble" title="Chat & book"><svg viewBox="0 0 24 24"><path d="M12 3C6.5 3 2 6.8 2 11.5c0 2.3 1.1 4.4 2.9 5.9L4 21l4-1.6c1.2.4 2.6.6 4 .6 5.5 0 10-3.8 10-8.5S17.5 3 12 3z"/></svg></div>' +
    '<div class="panel" id="panel">' +
      '<div class="hd"><div class="av">CL</div><div class="t"><div class="n">' + PRACTICE + '</div><div class="s"><span class="dot"></span>Book-Now Assistant · replies instantly</div></div><div class="x" id="close">×</div></div>' +
      '<div class="msgs" id="msgs"></div>' +
      '<div class="chips" id="chips"></div>' +
      '<form class="form" id="form">' +
        '<input id="f-name" placeholder="Your full name" autocomplete="name"/>' +
        '<input id="f-phone" placeholder="WhatsApp number e.g. 082 123 4567" inputmode="tel" autocomplete="tel"/>' +
        '<label><input type="checkbox" id="f-consent"/> I agree to be contacted on WhatsApp about my appointment.</label>' +
        '<button type="submit">Confirm my booking</button>' +
      '</form>' +
      '<div class="bar"><input id="inp" placeholder="Type your message…" autocomplete="off"/><button id="send" title="Send"><svg viewBox="0 0 24 24"><path d="M3 20l18-8L3 4v6l12 2-12 2z"/></svg></button></div>' +
      '<div class="foot">Powered by Dr Chalita le Roux · 24/7</div>' +
    '</div>';
  root.appendChild(wrap);

  var $ = function (id) { return root.getElementById ? root.getElementById(id) : wrap.querySelector('#' + id); };
  var msgs = $('msgs'), panel = $('panel'), chips = $('chips'), form = $('form'), inp = $('inp');

  function scroll() { msgs.scrollTop = msgs.scrollHeight; }
  function esc(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
  function fmt(s) {
    s = esc(s);
    s = s.replace(/\[([^\]]+)\]\s*\((https?:\/\/[^\s)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>'); // [text](url) or [text] (url)
    s = s.replace(/(^|[\s>])(https?:\/\/[^\s<]+)/g, '$1<a href="$2" target="_blank" rel="noopener">$2</a>');        // bare URLs
    s = s.replace(/\*([^*\n]+)\*/g, '$1'); // strip * markers — plain text, no bold (Paul's preference)
    return s.replace(/\n/g, '<br>');
  }
  function addMsg(text, who) {
    var d = document.createElement('div'); d.className = 'm ' + who;
    if (who === 'bot') { d.innerHTML = fmt(text); } else { d.textContent = text; }
    msgs.appendChild(d); scroll();
  }
  function showTyping() { var t = document.createElement('div'); t.className = 'typing'; t.id = 'typing'; t.innerHTML = '<span></span><span></span><span></span>'; msgs.appendChild(t); scroll(); }
  function hideTyping() { var t = $('typing'); if (t) t.remove(); }
  function setChips(items) {
    chips.innerHTML = '';
    (items || []).forEach(function (label) {
      var c = document.createElement('div'); c.className = 'chip'; c.textContent = label;
      c.onclick = function () { chips.innerHTML = ''; send(label); };
      chips.appendChild(c);
    });
  }

  var OPENERS = ['Toothache / Emergency', 'Check-up & Cleaning', 'Whiter / Better Smile', 'Ask a question'];

  function openPanel() {
    panel.classList.add('open'); $('teaser').style.display = 'none';
    if (!openedOnce) {
      openedOnce = true;
      addMsg("Hi! I'm the Book-Now Assistant for " + PRACTICE + " — your friendly dental practice in Roodepoort, also caring for patients across Honeydew, Wilgeheuwel and the wider West Rand. I can check live availability and book your visit in under a minute — even after hours — and send the details to your WhatsApp. How can I help today?", 'bot');
      setChips(OPENERS);
    }
    setTimeout(function () { inp.focus(); }, 100);
  }

  function send(text) {
    text = (text || '').trim(); if (!text) return;
    addMsg(text, 'me'); inp.value=''; setChips([]); showTyping();
    var body = { session_id: sessionId, message: text };
    if (contact.captured) { body.visitor_name = contact.name; body.visitor_phone = contact.phone; body.consent = contact.consent; }
    fetch(ENDPOINT, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Widget-Session': sessionId }, body: JSON.stringify(body) })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (d) {
        hideTyping();
        addMsg(d.reply || 'Sorry, could you say that again?', 'bot');
        if (d.needs_contact && !contact.captured) { form.classList.add('show'); }
        if (d.booked) { form.classList.remove('show'); }
      })
      .catch(function () { hideTyping(); addMsg('Sorry — I had trouble there. Please try again, or WhatsApp us on +27 71 884 3204.', 'bot'); });
  }

  form.onsubmit = function (e) {
    e.preventDefault();
    var name = $('f-name').value.trim(), phone = $('f-phone').value.trim(), consent = $('f-consent').checked;
    if (!name || !phone) { addMsg('Please add your name and WhatsApp number so I can confirm.', 'bot'); return; }
    if (!consent) { addMsg('Please tick the consent box so I can message you on WhatsApp.', 'bot'); return; }
    contact = { name: name, phone: phone, consent: true, captured: true };
    form.classList.remove('show');
    send('My name is ' + name + ', my WhatsApp is ' + phone + '. Please confirm my booking.');
  };

  $('bubble').onclick = openPanel;
  $('teaser').onclick = openPanel;
  $('close').onclick = function () { panel.classList.remove('open'); };
  $('send').onclick = function () { send(inp.value); };
  inp.addEventListener('keydown', function (e) { if (e.key === 'Enter') { e.preventDefault(); send(inp.value); } });

  // Proactive teaser after 9s (once per session)
  var teased = false;
  try { teased = sessionStorage.getItem('drc_teased') === '1'; } catch (e) {}
  if (!teased) { setTimeout(function () { if (!panel.classList.contains('open')) { $('teaser').style.display = 'block'; try { sessionStorage.setItem('drc_teased', '1'); } catch (e) {} } }, 9000); }
  else { $('teaser').style.display = 'none'; }
})();
