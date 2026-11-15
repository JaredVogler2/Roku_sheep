// Minimal DOM stand-ins so the web game's Canvas 2D drawing modules run under
// Node with node-canvas. Only what those modules touch is provided.
import { createCanvas } from 'canvas';

export function installDomShim() {
  if (globalThis.document) return;
  globalThis.document = {
    createElement(tag) {
      if (tag !== 'canvas') throw new Error(`dom-shim: cannot create <${tag}>`);
      return createCanvas(1, 1);
    },
  };
  globalThis.devicePixelRatio = 1;
}
