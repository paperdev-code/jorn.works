import initBackground from './gfx/background.js';

let mouse_pos_x = 0;
let mouse_pos_y = 0;

window.addEventListener('mousemove', function (evt) {
  mouse_pos_x = evt.clientX;
  mouse_pos_y = evt.clientY;
});

window.addEventListener('load', async function () {
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

class Mutex {
  constructor() {
    this.locked = false;
    this.priorityQueue = [];
  }

  async lock() {
    while (this.locked) {
      await new Promise((res) => {
        this.priorityQueue.push(res);
      });
    }
    this.locked = true;
  }

  unlock() {
    this.locked = false;
    if (this.priorityQueue.length > 0) {
      const res = this.priorityQueue.shift();
      res();
    }
  }
}

(() => {
  const stdin = document.getElementById('stdin');
  const stdout = document.getElementById('stdout');
  const prefix = document.getElementById('prefix');

  async function writeStdin(text) {
    for (let idx = 0; idx < text.length; ++idx) {
      stdin.innerText += text[idx];
      await sleep(40);
    }
  }

  function dupeElementIntoStdout(elt) {
    const stdin_line = document.createElement('span');
    stdin_line.innerText = `${prefix.innerText}${stdin.innerText}`;
    const copy = elt.cloneNode(true);
    copy.id = '';
    stdout.insertBefore(stdin_line, stdout.lastElementChild);
    stdout.insertBefore(copy, stdout.lastElementChild);
  }

  const actions = (function () {
    const result = new Map();
    document
      .querySelectorAll('#terminal-actions > div')
      .forEach(function (elt) {
        result.set(elt.id, {
          stdinText: elt.dataset.stdin,
          stdoutElt: elt,
        });
      });
    return result;
  })();

  const terminal_mutex = new Mutex();

  async function sleep(ms) {
    await new Promise(function (res) {
      setTimeout(res, ms);
    });
  }

  async function performAction(action) {
    await terminal_mutex.lock();
    await writeStdin(action.stdinText);
    dupeElementIntoStdout(action.stdoutElt);
    stdin.innerText = '';
    stdout.scrollTop = stdout.scrollHeight;
    terminal_mutex.unlock();
  }

  function performActionFromUrlIfAvailable(url) {
    const parsed = new URL(url);
    const action = actions.get(parsed.hash.substring(1));
    action && performAction(action);
  }

  window.addEventListener('hashchange', function (evt) {
    performActionFromUrlIfAvailable(evt.newURL);
  });

  window.addEventListener('load', async function () {
    performActionFromUrlIfAvailable('a:#help');
    await terminal_mutex.lock();
    prefix.innerText = '[guest@jorn.works:~]$ ';
    terminal_mutex.unlock();
    performActionFromUrlIfAvailable(window.location.href);
  });
})();
