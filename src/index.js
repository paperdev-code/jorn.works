import initBackground from './gfx/background.js';

let mouse_pos_x = 0;
let mouse_pos_y = 0;

window.addEventListener('mousemove', function(evt) {
  mouse_pos_x = evt.clientX;
  mouse_pos_y = evt.clientY;
});

window.addEventListener('load', async function() {
  const elt = document.getElementById('background');
  const background = await initBackground(elt);
  let time_prev_millis = 0;
  function onFrame(time_curr_millis) {
    const time_delta_secs = (time_curr_millis - time_prev_millis) / 1000;
    time_prev_millis = time_curr_millis;
    background.step(time_delta_secs, mouse_pos_x, mouse_pos_y);
    background.render(elt);
    requestAnimationFrame(onFrame);
  }
  requestAnimationFrame(onFrame);
});
