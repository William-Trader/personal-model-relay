/* Personal Model Relay · 历史最高面板
 * 由 nginx sub_filter 注入到上游首页 </body> 之前。
 * 依赖同源接口 /hist/max（可关闭面板时一并移除）。
 */
(function () {
  if (document.getElementById('histMaxWrap')) return;

  function el(id) { return document.getElementById(id); }
  function num(v) { return (v === null || v === undefined) ? '—' : (Math.round(v * 10) / 10); }
  function pad(x) { return String(x).padStart(2, '0'); }
  function when(ms) {
    if (!ms) return '尚未出现';
    var d = new Date(ms);
    return pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + ' ' +
           pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds());
  }
  function dur(sec) {
    if (sec === null || sec === undefined) return '—';
    sec = Math.round(sec);
    return Math.floor(sec / 3600) + ' 小时 ' + Math.floor(sec % 3600 / 60) + ' 分';
  }

  var wrap = document.createElement('div');
  wrap.className = 'grid';
  wrap.id = 'histMaxWrap';
  wrap.style.marginTop = '12px';
  wrap.innerHTML =
    '<div class="card full">' +
      '<h2>历史最高（自 <span id="hmSince">—</span> 起记录）</h2>' +
      '<div class="sub" id="hmMeta">—</div>' +
      '<div class="grid" style="margin-top:10px">' +
        '<div class="card"><h2>历史最高输出速度（实时）</h2><div class="big"><span id="hmDec">—</span><span class="unit">tok/s</span></div><div class="sub" id="hmDecAt">—</div></div>' +
        '<div class="card"><h2>历史最高预填充速度（实时）</h2><div class="big"><span id="hmPf">—</span><span class="unit">tok/s</span></div><div class="sub" id="hmPfAt">—</div></div>' +
        '<div class="card"><h2>最高单轮解码速度</h2><div class="big"><span id="hmRd">—</span><span class="unit">tok/s</span></div><div class="sub" id="hmRdAt">—</div></div>' +
        '<div class="card"><h2>最高单轮预填充速度</h2><div class="big"><span id="hmRp">—</span><span class="unit">tok/s</span></div><div class="sub" id="hmRpAt">—</div></div>' +
        '<div class="card"><h2>最高 GPU 利用率</h2><div class="big"><span id="hmGpu">—</span><span class="unit">%</span></div><div class="sub" id="hmGpuAt">—</div></div>' +
      '</div>' +
    '</div>';
  document.body.appendChild(wrap);

  function tick() {
    fetch('/hist/max?t=' + Date.now(), { cache: 'no-store' })
      .then(function (r) { return r.json(); })
      .then(function (d) {
        var st = (d.upstream === false)
          ? ' · <span style="color:#f85149">上游断开，显示最后一次记录</span>'
          : ' · 上游正常';
        el('hmMeta').innerHTML = '采样 ' + d.samples + ' 次 · 最近更新 ' + when(d.updated) +
          ' · 引擎已运行 ' + dur(d.engineUptimeSec) + st;
        var since = el('hmSince');
        if (since.dataset.set !== '1' && d.since) {
          since.textContent = when(d.since);
          since.dataset.set = '1';
        }
        el('hmDec').textContent = num(d.decode && d.decode.v);
        el('hmDecAt').textContent = '出现于 ' + when(d.decode && d.decode.at);
        el('hmPf').textContent = num(d.prefill && d.prefill.v);
        el('hmPfAt').textContent = '出现于 ' + when(d.prefill && d.prefill.at);
        el('hmRd').textContent = num(d.roundDecode && d.roundDecode.v);
        el('hmRdAt').textContent = '出现于 ' + when(d.roundDecode && d.roundDecode.at);
        el('hmRp').textContent = num(d.roundPrefill && d.roundPrefill.v);
        el('hmRpAt').textContent = '出现于 ' + when(d.roundPrefill && d.roundPrefill.at);
        el('hmGpu').textContent = (d.gpu && d.gpu.v === null) ? '—' : (d.gpu ? Math.round(d.gpu.v) : '—');
        el('hmGpuAt').textContent = '出现于 ' + when(d.gpu && d.gpu.at);
      })
      .catch(function () {
        el('hmMeta').textContent = '历史记录服务未启动（/hist/max 不可达）';
      });
  }

  tick();
  setInterval(tick, 5000);
})();
