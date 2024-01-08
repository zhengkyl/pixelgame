import JSConfetti from "js-confetti";

export const GameHooks = {
  // https://fly.io/phoenix-files/saving-and-restoring-liveview-state/
  mounted() {
    this.handleEvent("set", ({ key, data }) => {
      sessionStorage.setItem(key, data);
    });
    this.handleEvent("get", ({ key, event }) => {
      this.pushEvent(event, sessionStorage.getItem(key));
    });
    this.handleEvent("clear", ({ key }) => {
      sessionStorage.removeItem(key);
    });
    this.handleEvent("replaceHistory", ({ state, url }) => {
      window.history.replaceState(state, "", url);
    });
  },
};

export const CapitalizeInput = {
  mounted() {
    this.el.addEventListener("input", () => {
      this.el.value = this.el.value.toUpperCase();
    });
  },
};

export const Countdown = {
  mounted() {
    let count = 4;

    const nextNum = () => {
      this.el.textContent = count;

      this.el.style = "font-size: min(100vw, 50svh)";
      this.el.offsetHeight; // trigger reflow -> transition runs
      this.el.style =
        "font-size: min(50vw, 25svh);transition: font-size 0.5s ease-in-out";

      count--;
      if (count) setTimeout(nextNum, 800);
    };

    nextNum();
  },
};

export const Timer = {
  mounted() {
    let timeout;
    this.handleEvent("startTimer", ({ s }) => {
      clearTimeout(timeout);
      let seconds = s;

      const run = () => {
        this.el.textContent =
          `${Math.floor(seconds / 60)}:` + `${seconds % 60}`.padStart(2, "0");
        if (seconds) timeout = setTimeout(run, 1000);
        seconds--;
      };
      run();
    });
    this.handleEvent("stopTimer", () => {
      clearTimeout(timeout);
    });
  },
};

const winEmojis = ["👑", "🥇", "⭐", "🎉", "🥳"];

const loseEmojis = ["💀", "🗿", "🪦", "🥀", "😵"];

export const Announcement = {
  mounted() {
    const jsConfetti = new JSConfetti();

    this.handleEvent("announce", ({ msg, win }) => {
      // gross but delay feels better
      setTimeout(() => {
        const audio = new Audio(
          win ? "/sounds/victory.ogg" : "/sounds/defeat.ogg"
        );
        audio.play();
        jsConfetti.addConfetti({
          emojis: win ? winEmojis : loseEmojis,
        });
        this.el.textContent = msg;
        this.el.style.display = "block";
        this.el.offsetHeight; // trigger reflow -> transition runs
        this.el.style.opacity = 0;
        setTimeout(() => {
          this.el.style = "";
        }, 5000);
      }, 500);
    });
  },
};

const sounds = ["pop1.ogg", "pop2.ogg", "pop3.ogg"];

export const GameTile = {
  mounted() {
    const sound = sounds[Math.floor(Math.random() * sounds.length)];
    const audio = new Audio(`/sounds/${sound}`);
    audio.play();
  },
};
