export default async function initWebTerminal() {
	const container = document.querySelector('.js-web-terminal');
	if (!container) {
		return;
	}

	const Terminal = await loadXterm();
	const FitAddon = await loadFitAddon();
	const terminal = new Terminal();
	const fitAddon = new FitAddon();
	terminal.loadAddon(fitAddon);

	// The WebGL renderer is a performance optimisation only; xterm falls back to
	// its default renderer when it is unavailable.
	if (typeof WebGL2RenderingContext !== 'undefined') {
		try {
			const WebglAddon = await loadWebGLAddon();
			terminal.loadAddon(new WebglAddon());
		} catch {
			// Ignore and keep the default renderer.
		}
	}

	terminal.open(container);

	const socket = new WebSocket(`wss://${window.location.host}/_shell/`);
	const resizeTerminal = () => {
		try {
			fitAddon.fit();
		} catch {
			// The container is not measurable yet (e.g. mid-layout).
			return;
		}
		// Keep the browser grid and the server PTY in sync so full-screen
		// editors such as nano/vim wrap at the visible width.
		if (socket.readyState === WebSocket.OPEN) {
			socket.send(
				JSON.stringify({
					type: 'resize',
					cols: terminal.cols,
					rows: terminal.rows,
				}),
			);
		}
	};
	new ResizeObserver(resizeTerminal).observe(container);

	socket.addEventListener('open', (_) => {
		resizeTerminal();
		terminal.onData((data) => socket.send(data));
		socket.addEventListener('message', (evt) => terminal.write(evt.data));
	});
	socket.addEventListener('error', (_) => {
		terminal.reset();
		terminal.writeln('Connection error.');
	});
	socket.addEventListener('close', (evt) => {
		if (evt.wasClean) {
			terminal.reset();
			terminal.writeln(evt.reason ?? 'Connection closed.');
		}
	});
}

/** @returns {Promise<typeof import("@xterm/xterm").Terminal>} */
async function loadXterm() {
	// NOTE: String expression used to prevent ESBuild from resolving
	// the import on build (xterm is a separate bundle)
	const xtermBundlePath = '/js/dist/xterm.min.js';
	const xtermModule = await import(`${xtermBundlePath}`);
	return xtermModule.default.Terminal;
}

/** @returns {Promise<typeof import("@xterm/addon-webgl").WebglAddon>} */
async function loadWebGLAddon() {
	// NOTE: String expression used to prevent ESBuild from resolving
	// the import on build (xterm-addon-webgl is a separate bundle)
	const xtermBundlePath = '/js/dist/xterm-addon-webgl.min.js';
	const xtermModule = await import(`${xtermBundlePath}`);
	return xtermModule.default.WebglAddon;
}

/** @returns {Promise<typeof import("@xterm/addon-fit").FitAddon>} */
async function loadFitAddon() {
	// NOTE: String expression used to prevent ESBuild from resolving
	// the import on build (xterm is a separate bundle)
	const xtermBundlePath = '/js/dist/xterm-addon-fit.min.js';
	const xtermModule = await import(`${xtermBundlePath}`);
	return xtermModule.default.FitAddon;
}
