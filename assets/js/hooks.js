// https://fly.io/phoenix-files/saving-and-restoring-liveview-state/

export const GameCodeStore = {
  mounted() {
    this.handleEvent("store", (obj) => {
      console.log("store", obj);
      window.history.replaceState(null, "", "game");
      sessionStorage.setItem(obj.key, obj.data);
    });
    this.handleEvent("restore", (obj) => {
      console.log("restore", obj);
      this.pushEvent(obj.event, sessionStorage.getItem(obj.key));
    });
    this.handleEvent("clear", (obj) => {
      console.log("clear", obj);
      sessionStorage.removeItem(obj.key);
    });
  },
};
