// Public OHLC data only. This document has no network, session or order access.
(() => {
  const L = LightweightCharts;
  const root = document.getElementById('chart');
  const legend = document.getElementById('legend');
  const chart = L.createChart(root, {
    autoSize: true,
    layout: { background: { type: L.ColorType.Solid, color: '#191c23' }, textColor: '#c6c9d1', fontSize: 10,
      attributionLogo: true, panes: { enableResize: false, separatorColor: '#343a49' } },
    grid: { vertLines: { color: '#292e39' }, horzLines: { color: '#292e39' } },
    rightPriceScale: { autoScale: true, borderColor: '#343a49' },
    timeScale: { timeVisible: true, secondsVisible: false, barSpacing: 7, borderColor: '#343a49', shiftVisibleRangeOnNewBar: true },
    handleScroll: { vertTouchDrag: false, horzTouchDrag: true },
    handleScale: { pinch: true, axisPressedMouseMove: true },
    localization: { timeFormatter: time => new Date(Number(time) * 1000).toLocaleString(undefined, { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false }) },
  });
  const prices = chart.addSeries(L.CandlestickSeries, { upColor: '#55df9a', downColor: '#ff7d86', borderUpColor: '#55df9a', borderDownColor: '#ff7d86', wickUpColor: 'rgba(85,223,154,.62)', wickDownColor: 'rgba(255,125,134,.62)' });
  chart.addPane();
  const volumes = chart.addSeries(L.HistogramSeries, { priceFormat: { type: 'volume' }, priceScaleId: 'right' }, 1);
  chart.panes()[0].setStretchFactor(.76);
  chart.panes()[1].setStretchFactor(.24);
  prices.priceScale().applyOptions({ scaleMargins: { top: .08, bottom: .08 }, tickMarkDensity: 2 });
  volumes.priceScale().applyOptions({ scaleMargins: { top: .22, bottom: .02 }, visible: true });
  let current = null, market = '', hovered = null;
  function showLegend(bar) {
    if (!bar || !current) { legend.textContent = ''; return; }
    const format = value => Number(value).toLocaleString('en-US', { minimumFractionDigits: current.precision, maximumFractionDigits: current.precision });
    legend.replaceChildren();
    for (const [name, value] of [['开', format(bar.open)], ['高', format(bar.high)], ['低', format(bar.low)], ['收', format(bar.close)], ['量', Number(bar.volume).toLocaleString('en-US', { maximumFractionDigits: 6 }) + ' ' + current.volumeUnit]]) {
      const span = document.createElement('span'); span.textContent = name + ' ' + value; legend.appendChild(span);
    }
  }
  chart.subscribeCrosshairMove(event => {
    hovered = typeof event.time === 'number' ? event.time : null;
    const bars = current ? current.bars : [];
    showLegend(bars.find(bar => bar.time === hovered) || bars[bars.length - 1]);
  });
  window.renderChart = payload => {
    const changed = market !== payload.market;
    const visible = changed ? null : chart.timeScale().getVisibleRange();
    const follow = chart.timeScale().scrollPosition() < 2;
    current = payload;
    market = payload.market;
    const theme = payload.theme;
    document.body.style.background = theme.background;
    legend.style.color = theme.ink;
    chart.applyOptions({ layout: { background: { type: L.ColorType.Solid, color: theme.background }, textColor: theme.ink, panes: { separatorColor: theme.border } }, grid: { vertLines: { color: theme.grid }, horzLines: { color: theme.grid } }, rightPriceScale: { borderColor: theme.border }, timeScale: { borderColor: theme.border } });
    prices.applyOptions({ upColor: theme.up, downColor: theme.down, borderUpColor: theme.up, borderDownColor: theme.down, wickUpColor: theme.wickUp, wickDownColor: theme.wickDown, priceFormat: { type: 'price', precision: payload.precision, minMove: payload.minMove } });
    prices.setData(payload.bars.map(({ time, open, high, low, close }) => ({ time, open, high, low, close })));
    volumes.setData(payload.bars.map(bar => ({ time: bar.time, value: bar.volume, color: bar.close >= bar.open ? theme.up : theme.down })));
    if (payload.bars.length) {
      if (changed || !visible) chart.timeScale().setVisibleLogicalRange({ from: Math.max(0, payload.bars.length - 60), to: payload.bars.length + 3 });
      else if (!follow) chart.timeScale().setVisibleRange(visible);
      else chart.timeScale().scrollToRealTime();
    }
    showLegend(payload.bars.find(bar => bar.time === hovered) || payload.bars[payload.bars.length - 1]);
  };
  document.addEventListener('click', event => {
    const link = event.target.closest('a');
    if (link) { event.preventDefault(); window.ChartLink.postMessage(link.href); }
  });
  window.ChartReady.postMessage('ready');
})();
