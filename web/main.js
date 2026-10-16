const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

function rollCounts() {
  document.querySelectorAll(".num").forEach((node) => {
    const target = Number(node.dataset.count);
    if (reduceMotion || !Number.isFinite(target)) {
      node.textContent = String(target);
      return;
    }
    const start = performance.now();
    const duration = 700;
    function frame(now) {
      const t = Math.min(1, (now - start) / duration);
      const eased = 1 - Math.pow(1 - t, 5);
      node.textContent = String(Math.round(target * eased));
      if (t < 1) requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
  });
}

function drawRadar(angle) {
  const canvas = document.getElementById("radar");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  const scale = 2;
  if (canvas.width !== 168 * scale) {
    canvas.width = 168 * scale;
    canvas.height = 168 * scale;
  }
  const size = canvas.width;
  const center = size / 2;
  const radius = center - 2;
  ctx.clearRect(0, 0, size, size);
  ctx.lineWidth = scale;

  for (let ring = 1; ring <= 4; ring += 1) {
    const r = (radius * ring) / 4;
    ctx.beginPath();
    ctx.arc(center, center, r, 0, Math.PI * 2);
    ctx.strokeStyle = ring === 4 ? "rgba(255,255,255,0.12)" : "rgba(255,255,255,0.06)";
    ctx.stroke();
  }

  ctx.strokeStyle = "rgba(255,255,255,0.05)";
  ctx.beginPath();
  ctx.moveTo(center - radius, center);
  ctx.lineTo(center + radius, center);
  ctx.moveTo(center, center - radius);
  ctx.lineTo(center, center + radius);
  ctx.stroke();

  for (let i = 0; i < 72; i += 1) {
    const a = (i / 72) * Math.PI * 2;
    const inner = radius - (i % 6 === 0 ? 7 * scale : 3 * scale);
    ctx.beginPath();
    ctx.moveTo(center + Math.cos(a) * inner, center + Math.sin(a) * inner);
    ctx.lineTo(center + Math.cos(a) * radius, center + Math.sin(a) * radius);
    ctx.strokeStyle = i % 6 === 0 ? "rgba(255,255,255,0.18)" : "rgba(255,255,255,0.08)";
    ctx.stroke();
  }

  const trail = 1.1;
  const slices = 28;
  for (let i = slices - 1; i >= 0; i -= 1) {
    const from = angle - (trail * (i + 1)) / slices;
    const to = angle - (trail * i) / slices;
    ctx.beginPath();
    ctx.moveTo(center, center);
    ctx.arc(center, center, radius * 0.92, from, to);
    ctx.closePath();
    ctx.fillStyle = `rgba(244,169,59,${(0.22 * (slices - i)) / slices})`;
    ctx.fill();
  }
  ctx.strokeStyle = "#f4a93b";
  ctx.beginPath();
  ctx.moveTo(center, center);
  ctx.lineTo(center + Math.cos(angle) * radius * 0.92, center + Math.sin(angle) * radius * 0.92);
  ctx.stroke();
}

function startRadar() {
  const fixed = -Math.PI / 4;
  if (reduceMotion) {
    drawRadar(fixed);
    return;
  }
  const origin = performance.now();
  function frame(now) {
    drawRadar(fixed + ((now - origin) / 1000) * 0.5);
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
}

function platformNote() {
  const mac = /Macintosh/.test(navigator.userAgent) && navigator.maxTouchPoints < 2;
  const download = document.getElementById("download");
  const note = document.getElementById("other-os");
  if (!download || !note) return;
  download.hidden = !mac;
  note.hidden = mac;
}

function copyCommand() {
  const button = document.getElementById("copy");
  const command = document.getElementById("brew-command");
  if (!button || !command) return;
  button.addEventListener("click", async () => {
    const text = command.textContent.trim();
    try {
      await navigator.clipboard.writeText(text);
    } catch {
      const range = document.createRange();
      range.selectNodeContents(command);
      const selection = getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
    }
    const previous = button.textContent;
    button.textContent = "Copied";
    window.setTimeout(() => { button.textContent = previous; }, 1600);
  });
}

function loadVersion() {
  const slot = document.getElementById("version");
  if (!slot) return;
  fetch("/appcast.xml")
    .then((response) => (response.ok ? response.text() : ""))
    .then((xml) => {
      const match = xml.match(/sparkle:shortVersionString>([^<]+)/);
      if (match) slot.textContent = match[1];
    })
    .catch(() => {});
}

rollCounts();
startRadar();
platformNote();
copyCommand();
loadVersion();
