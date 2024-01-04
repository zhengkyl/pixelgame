// https://fly.io/phoenix-files/saving-and-restoring-liveview-state/

export const GameHooks = {
  mounted() {
    this.handleEvent("set", (obj) => {
      console.log("set", obj);
      sessionStorage.setItem(obj.key, obj.data);
    });
    this.handleEvent("get", (obj) => {
      console.log("get", obj);
      this.pushEvent(obj.event, sessionStorage.getItem(obj.key));
    });
    this.handleEvent("clear", (obj) => {
      console.log("clear", obj);
      sessionStorage.removeItem(obj.key);
    });
    this.handleEvent("replaceHistory", (obj) => {
      console.log("replace state", obj);
      window.history.replaceState(obj.state, "", obj.url);
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
    this.handleEvent("startTimer", (obj) => {
      clearTimeout(timeout);
      let seconds = obj.s;

      const run = () => {
        this.el.textContent =
          `${Math.floor(seconds / 60)}:` + `${seconds % 60}`.padStart(2, "0");
        seconds--;
        if (seconds) timeout = setTimeout(run, 1000);
      };
      run();
    });
    this.handleEvent("stopTimer", () => {
      clearTimeout(timeout);
    });
  },
};
