(function (global) {
  'use strict';

  function localized(manifest, map) {
    if (!map) return '';
    if (map[manifest.locale]) return map[manifest.locale];
    if (map[manifest.fallbackLocale]) return map[manifest.fallbackLocale];
    var keys = Object.keys(map);
    return keys.length ? map[keys[0]] : '';
  }

  function stateLabel(manifest, stateId) {
    var states = (manifest.labels || {}).states || {};
    return localized(manifest, states[stateId]) || stateId;
  }

  function label(manifest, key) {
    return localized(manifest, (manifest.labels || {})[key]);
  }

  function isTalkingState(stateId) {
    return stateId.indexOf('talk_') === 0;
  }

  function collectStates(manifest) {
    var order = [];
    var seen = {};
    var outfitsMap = manifest.outfits || {};
    var ids = Object.keys(outfitsMap);
    if (manifest.defaultOutfit && outfitsMap[manifest.defaultOutfit]) {
      ids = [manifest.defaultOutfit].concat(ids.filter(function (id) { return id !== manifest.defaultOutfit; }));
    }
    ids.forEach(function (id) {
      Object.keys(outfitsMap[id].states || {}).forEach(function (stateId) {
        if (!seen[stateId]) {
          seen[stateId] = true;
          order.push(stateId);
        }
      });
    });
    return order;
  }

  function createAvatarCore(manifest, deps) {
    var outfits = Object.keys(manifest.outfits || {});
    var defaultOutfit = outfits.indexOf(manifest.defaultOutfit) !== -1 ? manifest.defaultOutfit : (outfits[0] || null);
    var states = collectStates(manifest);
    var defaultDef = (manifest.outfits || {})[defaultOutfit] || {};
    var state = states.indexOf(defaultDef.defaultIdle) !== -1 ? defaultDef.defaultIdle : (states[0] || 'idle_01');
    var outfit = defaultOutfit;

    function resolveState(stateId, outfitId) {
      var target = (manifest.outfits || {})[outfitId];
      var base = (manifest.outfits || {})[defaultOutfit] || {};
      if (target) {
        if (target.states && target.states[stateId]) return target.states[stateId];
        if (isTalkingState(stateId) && target.fallbackTalking && target.states && target.states[target.fallbackTalking]) {
          return target.states[target.fallbackTalking];
        }
        if (target.defaultIdle && target.states && target.states[target.defaultIdle]) return target.states[target.defaultIdle];
      }
      if (base.states && base.states[stateId]) return base.states[stateId];
      if (base.defaultIdle && base.states && base.states[base.defaultIdle]) return base.states[base.defaultIdle];
      return null;
    }

    function emit() {
      if (deps && deps.onChange) deps.onChange(state, outfit, resolveState(state, outfit));
    }

    function setState(next) {
      if (states.indexOf(next) === -1) return state;
      state = next;
      emit();
      return state;
    }

    function selectOutfit(next) {
      if (outfits.indexOf(next) === -1) return outfit;
      outfit = next;
      emit();
      return outfit;
    }

    function getState() { return state; }
    function getOutfit() { return outfit; }
    function getResolvedState() { return resolveState(state, outfit); }
    function getClip() { var d = resolveState(state, outfit); return d ? d.src : null; }
    function getStates() { return states.slice(); }
    function getOutfits() { return outfits.slice(); }

    return {
      setState: setState,
      selectOutfit: selectOutfit,
      getState: getState,
      getOutfit: getOutfit,
      getResolvedState: getResolvedState,
      getClip: getClip,
      getStates: getStates,
      getOutfits: getOutfits
    };
  }

  function boot(manifest) {
    if (!manifest) return;

    var stage = document.getElementById('stage');
    var subtitleEl = document.getElementById('subtitle');
    var userLineEl = document.getElementById('user-line');
    var fallbackEl = document.getElementById('stage-fallback');
    var fallbackLabel = document.getElementById('fallback-label');
    var statusChip = document.getElementById('status-chip');
    var textInput = document.getElementById('text-input');
    var sendBtn = document.getElementById('send-btn');
    var micBtn = document.getElementById('mic-btn');
    var wardrobeBtn = document.getElementById('wardrobe-btn');
    var wardrobePanel = document.getElementById('wardrobe-panel');
    var wardrobeOptions = document.getElementById('wardrobe-options');
    var demoBtn = document.getElementById('demo-btn');

    var layerA = document.getElementById('avatar-video-a');
    var layerB = document.getElementById('avatar-video-b');
    var currentLayer = layerA;
    var flowToken = 0;

    function playVideo(video) {
      var p = video.play();
      if (p && typeof p.catch === 'function') p.catch(function () {});
    }

    function showClip(def) {
      if (!def || !def.src) { setFallback(true); return; }
      var next = currentLayer === layerA ? layerB : layerA;
      next.src = def.src;
      next.loop = def.mode === 'loop';
      next.muted = true;
      next.removeEventListener('ended', next._onEnded);
      if (def.mode === 'once' && def.fallback) {
        next._onEnded = function () { setState(def.fallback); };
        next.addEventListener('ended', next._onEnded);
      }
      next.load();
      var settled = false;
      function onReady() {
        if (settled) return;
        settled = true;
        next.removeEventListener('loadeddata', onReady);
        next.removeEventListener('error', onError);
        playVideo(next);
        if (currentLayer) currentLayer.classList.remove('active');
        next.classList.add('active');
        currentLayer = next;
        setFallback(false);
      }
      function onError() {
        if (settled) return;
        settled = true;
        next.removeEventListener('loadeddata', onReady);
        next.removeEventListener('error', onError);
        if (currentLayer) currentLayer.classList.remove('active');
        setFallback(true);
      }
      next.addEventListener('loadeddata', onReady);
      next.addEventListener('error', onError);
      window.setTimeout(function () {
        if (!settled && next.readyState >= 2) onReady();
      }, 0);
      window.setTimeout(function () {
        if (!settled) { settled = true; next.removeEventListener('loadeddata', onReady); next.removeEventListener('error', onError); setFallback(true); }
      }, 1500);
    }

    function setFallback(visible) {
      if (!fallbackEl || !fallbackLabel) return;
      fallbackEl.hidden = !visible;
      if (visible) fallbackLabel.textContent = label(manifest, 'fallbackClip');
    }

    function applyState() {
      document.body.setAttribute('data-state', core.getState());
      if (statusChip) statusChip.textContent = stateLabel(manifest, core.getState());
      showClip(core.getResolvedState());
    }

    function applyOutfit() {
      document.body.setAttribute('data-outfit', core.getOutfit());
      var outfitDef = (manifest.outfits || {})[core.getOutfit()];
      document.documentElement.style.setProperty('--accent', (outfitDef && outfitDef.accent) || '#8b6cff');
      renderWardrobe();
    }

    function setSubtitle(text) {
      if (!subtitleEl) return;
      subtitleEl.textContent = text || '';
      subtitleEl.hidden = !text;
    }

    function clearSubtitle() { setSubtitle(''); }

    function estimateMs(text) {
      var base = Math.max(1400, text.length * 240);
      return Math.min(base, 8000);
    }

    function cancelFlow() { flowToken += 1; }

    function runDemoFlow() {
      cancelFlow();
      var token = flowToken;
      setState('thinking');
      setSubtitle(stateLabel(manifest, 'thinking'));
      window.setTimeout(function () {
        if (token !== flowToken) return;
        setState('talk_soft');
        setSubtitle(label(manifest, 'cannedReply'));
      }, 900);
      window.setTimeout(function () {
        if (token !== flowToken) return;
        clearSubtitle();
        setState('idle_01');
      }, 900 + estimateMs(label(manifest, 'cannedReply')));
    }

    // Native SoulNest keeps all chat/session/credential work on-device. A
    // standalone PWA has no native bridge and retains the local visual demo.
    function postNative(type, value) {
      var handler = global.webkit && global.webkit.messageHandlers && global.webkit.messageHandlers.soulNestAvatar;
      if (!handler || typeof handler.postMessage !== 'function') return false;
      var payload = { type: type };
      if (value) payload.text = value;
      handler.postMessage(payload);
      return true;
    }

    function sendMessage(text) {
      var trimmed = (text || '').trim();
      if (!trimmed) return;
      textInput.value = '';
      textInput.blur();
      cancelFlow();
      var token = flowToken;
      if (userLineEl) {
        userLineEl.textContent = trimmed;
        userLineEl.hidden = false;
      }
      setState('thinking');
      setSubtitle(stateLabel(manifest, 'thinking'));
      if (postNative('send', trimmed)) {
        // The native stream bridge supplies the real subtitle and final state.
        return;
      }
      window.setTimeout(function () {
        if (token !== flowToken) return;
        if (userLineEl) userLineEl.hidden = true;
        setState('talk_soft');
        setSubtitle(label(manifest, 'cannedReply'));
      }, 1100);
      window.setTimeout(function () {
        if (token !== flowToken) return;
        clearSubtitle();
        setState('idle_01');
      }, 1100 + estimateMs(label(manifest, 'cannedReply')));
    }

    function renderWardrobe() {
      if (!wardrobeOptions) return;
      wardrobeOptions.innerHTML = '';
      core.getOutfits().forEach(function (id) {
        var outfitDef = (manifest.outfits || {})[id] || {};
        var btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'outfit-option' + (id === core.getOutfit() ? ' selected' : '');
        btn.textContent = localized(manifest, outfitDef.name) || id;
        btn.style.setProperty('--outfit-accent', outfitDef.accent || '#8b6cff');
        btn.addEventListener('click', function () { selectOutfit(id); });
        wardrobeOptions.appendChild(btn);
      });
    }

    function setState(next) {
      core.setState(next);
      applyState();
      return core.getState();
    }

    function selectOutfit(id) {
      core.selectOutfit(id);
      applyOutfit();
      applyState();
      return core.getOutfit();
    }

    if (demoBtn) demoBtn.addEventListener('click', runDemoFlow);
    if (micBtn) micBtn.addEventListener('click', function () {
      if (postNative('mic')) {
        setState('thinking');
        setSubtitle(label(manifest, 'thinking'));
      } else {
        setSubtitle(label(manifest, 'micComingSoon'));
      }
    });
    if (sendBtn) sendBtn.addEventListener('click', function () { sendMessage(textInput ? textInput.value : ''); });
    if (textInput) textInput.addEventListener('keydown', function (e) {
      if (e.key === 'Enter') { e.preventDefault(); sendMessage(textInput.value); }
    });
    if (wardrobeBtn) wardrobeBtn.addEventListener('click', function () {
      if (wardrobePanel) wardrobePanel.hidden = !wardrobePanel.hidden;
    });
    if (stage) stage.addEventListener('click', function () {
      document.body.classList.toggle('ui-hidden');
    });
    Array.prototype.forEach.call(document.querySelectorAll('[data-state]'), function (btn) {
      btn.textContent = stateLabel(manifest, btn.getAttribute('data-state'));
      btn.addEventListener('click', function () {
        setState(btn.getAttribute('data-state'));
      });
    });

    applyOutfit();
    applyState();
    setFallback(true);

    global.SoulNestAvatar.setState = setState;
    global.SoulNestAvatar.selectOutfit = selectOutfit;
    global.SoulNestAvatar.getState = function () { return core.getState(); };
    global.SoulNestAvatar.getOutfit = function () { return core.getOutfit(); };
    global.SoulNestAvatar.setSubtitle = setSubtitle;
    global.SoulNestAvatar.clearSubtitle = clearSubtitle;
    global.SoulNestAvatar.say = function (text) {
      cancelFlow();
      setState('talk_soft');
      setSubtitle(text);
      var token = flowToken;
      window.setTimeout(function () {
        if (token !== flowToken) return;
        clearSubtitle();
        setState('idle_01');
      }, estimateMs(text));
    };
    global.SoulNestAvatar.demo = runDemoFlow;
    global.SoulNestAvatar.send = sendMessage;
  }

  var core = createAvatarCore(global.SOULNEST_MANIFEST || {}, null);

  global.SoulNestAvatar = global.SoulNestAvatar || {};
  global.SoulNestAvatar.createAvatarCore = createAvatarCore;
  global.SoulNestAvatar._manifest = global.SOULNEST_MANIFEST || {};
  global.SoulNestAvatar._core = core;

  if (typeof document !== 'undefined' && document.getElementById) {
    boot(global.SOULNEST_MANIFEST);
  }
})(typeof window !== 'undefined' ? window : globalThis);
