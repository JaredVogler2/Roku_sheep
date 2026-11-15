// The web game's 64-bit structural state hash (src/engine/StateHash.ts),
// re-implemented so the Roku repository can verify engine parity on its own.
export class Hasher {
  a = 0x811c9dc5;
  b = 0x9747b28c;

  int(v) {
    v |= 0;
    let a = this.a;
    a = Math.imul(a ^ (v & 0xff), 0x01000193);
    a = Math.imul(a ^ ((v >>> 8) & 0xff), 0x01000193);
    a = Math.imul(a ^ ((v >>> 16) & 0xff), 0x01000193);
    a = Math.imul(a ^ ((v >>> 24) & 0xff), 0x01000193);
    this.a = a;
    let k = Math.imul(v, 0xcc9e2d51);
    k = (k << 15) | (k >>> 17);
    k = Math.imul(k, 0x1b873593);
    let b = this.b ^ k;
    b = (b << 13) | (b >>> 19);
    this.b = (Math.imul(b, 5) + 0xe6546b64) | 0;
    return this;
  }

  bytes(arr) {
    const n = arr.length;
    let i = 0;
    for (; i + 4 <= n; i += 4) this.int(arr[i] | (arr[i + 1] << 8) | (arr[i + 2] << 16) | (arr[i + 3] << 24));
    for (; i < n; i++) this.int(arr[i]);
    return this.int(n);
  }

  str(s) {
    for (let i = 0; i < s.length; i++) this.int(s.charCodeAt(i));
    return this.int(s.length);
  }

  hex() {
    let b = this.b ^ (this.b >>> 16);
    b = Math.imul(b, 0x85ebca6b);
    b ^= b >>> 13;
    b = Math.imul(b, 0xc2b2ae35);
    b ^= b >>> 16;
    return (this.a >>> 0).toString(16).padStart(8, '0') + (b >>> 0).toString(16).padStart(8, '0');
  }
}

/**
 * Hash a state dump in the field order of hashSimulation().
 * state = { tick, phase, endReason, saved, lost, waiting, active, releaseRate, timeLeft, lastSpawnTick,
 *           hatchCursor, nuking, stock[8], hatchSpawned[], sheep[{id,x,y,dir,state,canClimb,canFloat,
 *           bomberTicks,fallDistance,stateTicks,bricks,fate}], cells: Uint8Array }
 */
export function hashState(st) {
  const h = new Hasher();
  h.int(st.tick).str(st.phase).str(st.endReason ?? '').int(st.saved).int(st.lost).int(st.waiting).int(st.active);
  h.int(st.releaseRate).int(st.timeLeft).int(st.lastSpawnTick).int(st.hatchCursor).int(st.nuking ? 1 : 0);
  for (const n of st.stock) h.int(n);
  for (const n of st.hatchSpawned) h.int(n);
  h.int(st.sheep.length);
  for (const s of st.sheep) {
    h.int(s.id).int(s.x).int(s.y).int(s.dir).str(s.state).int(s.canClimb ? 1 : 0).int(s.canFloat ? 1 : 0);
    h.int(s.bomberTicks).int(s.fallDistance).int(s.stateTicks).int(s.bricks).str(s.fate);
  }
  h.bytes(st.cells);
  return h.hex();
}
