import wasm from '../wasm.js';

function waitForReflow() {
  return new Promise(function (resolve) {
    requestAnimationFrame(resolve);
  });
}

async function determineDotsDimensions(elt) {
  elt.innerText = '\u2800';
  await waitForReflow();
  const glyph = elt.getBoundingClientRect();
  const cols = Math.ceil(window.innerWidth / glyph.width);
  const rows = Math.ceil(window.innerHeight / glyph.height);
  elt.innerText = '';
  return { width: cols * 2, height: rows * 4 };
}

async function initBackground(elt) {
  const instance = await wasm.load('/gfx/background.wasm');
  const boat_stl = await fetch('/gfx/boat.stl');
  const face_stl = await fetch('/gfx/face.stl');
  const { width, height } = await determineDotsDimensions(elt);
  wasm.setup(
    instance,
    `.{
    .dots = .{
      .width  = ${width},
      .height = ${height},
    },
    .boat_stl = ${wasm.writeSlice(instance, await boat_stl.bytes())},
    .face_stl = ${wasm.writeSlice(instance, await face_stl.bytes())},
  }`,
  );

  return {
    step: function (time_delta_secs, mouse_pos_x, mouse_pos_y) {
      instance.exports.step(
        time_delta_secs,
        (mouse_pos_x / window.innerWidth) * 2.0 - 1.0,
        (mouse_pos_y / window.innerHeight) * 2.0 - 1.0,
      );
    },
    render: function (elt) {
      const result = instance.exports.render();
      const buffer = wasm.readSlice(instance, result);
      const output = new TextDecoder().decode(buffer);
      elt.innerText = output;
    },
  };
}

export default initBackground;
