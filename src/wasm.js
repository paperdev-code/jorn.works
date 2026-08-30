function readSlice(instance, slice) {
  const ptr = Number(slice & 0xffffffffn);
  const len = Number((slice >> 32n) & 0xffffffffn);
  return new Uint8Array(instance.exports.memory.buffer, ptr, len);
}

function writeSlice(instance, bytes) {
  const slice = instance.exports.alloc(bytes.length);
  const dest = readSlice(instance, slice);
  dest.set(bytes);
  return slice;
}

function freeSlice(instance, slice) {
  instance.exports.free(slice);
}

async function load(path) {
  const wasm = await WebAssembly.instantiateStreaming(fetch(path), {
    env: {
      console: function (level, ptr, len) {
        const text = new TextDecoder().decode(
          new Uint8Array(wasm.instance.exports.memory.buffer, ptr, len),
        );
        [console.error, console.warn, console.info, console.debug][level](text);
      },
    },
  });
  return wasm.instance;
}

function setup(instance, config_zon) {
  const slice = writeSlice(instance, new TextEncoder().encode(config_zon));
  const ec = instance.exports.setup(slice);
  freeSlice(instance, slice);
  if (ec) throw new Error('setup failed');
}

export default { load, setup, readSlice, writeSlice, freeSlice };
