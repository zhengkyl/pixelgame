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
