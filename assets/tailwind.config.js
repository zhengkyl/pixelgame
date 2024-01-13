// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin");
const fs = require("fs");
const path = require("path");

module.exports = {
  content: ["./js/**/*.js", "../lib/*_web.ex", "../lib/*_web/**/*.*ex"],
  safelist: [
    "text-green-600",
    "[--pop-index:0]",
    "[--pop-index:1]",
    "[--pop-index:2]",
    "[--pop-index:3]",
    "[--pop-index:4]",
    "[--pop-index:5]",
    "[--pop-index:6]",
    "[--pop-index:7]",
    "[--pop-index:8]",
    "[--pop-index:9]",
    "[--pop-index:10]",
    "[--pop-index:11]",
    "[--pop-index:12]",
    "[--pop-index:13]",
    "[--pop-index:14]",
    "[--pop-index:15]",
    "[--pop-index:16]",
    "[--pop-index:17]",
    "[--pop-index:18]",
    "[--pop-index:19]",
    {
      pattern: /bg-(green|sky|purple|yellow|amber)-600/,
    },
    {
      pattern: /border-(green|sky|purple|yellow|amber)-600/,
    },
    {
      pattern: /bg-(green|sky|purple|yellow|amber)-500/,
      variants: ["hover"],
    },
    {
      pattern: /grid-cols-([3-9]|1\d|20)/,
    },
  ],
  theme: {
    extend: {
      borderColor: {
        DEFAULT: "#696969",
      },
      colors: {
        brand: "#FAD63F",
      },
      keyframes: {
        draw: {
          "0%": { strokeDashoffset: 30, strokeDasharray: "20 40" },
          "100%": { strokeDashoffset: 0 },
        },
        pop: {
          "0%": { transform: "scale(0)" },
          "60%": { transform: "scale(1.2)" },
          "100%": { transform: "scale(1)" },
        },
        delayedPop: {
          "0%": { transform: "scale(1)" },
          "60%": { transform: "scale(1.2)" },
          "100%": { transform: "scale(1)" },
        },
        dance: {
          "0%": { transform: "rotate3d(0, 0, 1, 0deg)" },
          "20%": { transform: "rotate3d(0, 0, 1, 0deg)" },
          "40%": { transform: "rotate3d(0, 0, 1, 180deg)" },
          "60%": { transform: "rotate3d(1, 0, 0, 180deg)" },
          "80%": { transform: "rotate3d(1, 2, 0, 180deg)" },
        },
      },
      animation: {
        pop: "pop 300ms ease-in-out",
        delayedPop:
          "delayedPop 300ms ease-in-out calc(var(--pop-index) * 100ms)",
        dance: "dance 20s infinite",
        draw: "draw 4s",
      },
      gridTemplateColumns: {
        13: "repeat(13, minmax(0, 1fr))",
        14: "repeat(14, minmax(0, 1fr))",
        15: "repeat(15, minmax(0, 1fr))",
        16: "repeat(16, minmax(0, 1fr))",
        17: "repeat(17, minmax(0, 1fr))",
        18: "repeat(18, minmax(0, 1fr))",
        19: "repeat(19, minmax(0, 1fr))",
        20: "repeat(20, minmax(0, 1fr))",
      },
      screens: {
        xs: "360px",
      },
    },
  },
  plugins: [
    require("@tailwindcss/forms"),
    // Allows prefixing tailwind classes with LiveView classes to add rules
    // only when LiveView classes are applied, for example:
    //
    //     <div class="phx-click-loading:animate-ping">
    //
    plugin(({ addVariant }) =>
      addVariant("phx-no-feedback", [".phx-no-feedback&", ".phx-no-feedback &"])
    ),
    plugin(({ addVariant }) =>
      addVariant("phx-click-loading", [
        ".phx-click-loading&",
        ".phx-click-loading &",
      ])
    ),
    plugin(({ addVariant }) =>
      addVariant("phx-submit-loading", [
        ".phx-submit-loading&",
        ".phx-submit-loading &",
      ])
    ),
    plugin(({ addVariant }) =>
      addVariant("phx-change-loading", [
        ".phx-change-loading&",
        ".phx-change-loading &",
      ])
    ),

    // Embeds Hero Icons (https://heroicons.com) into your app.css bundle
    // See your `CoreComponents.icon/1` for more information.
    //
    plugin(function ({ matchComponents, theme }) {
      let iconsDir = path.join(__dirname, "./vendor/heroicons/optimized");
      let values = {};
      let icons = [
        ["", "/24/solid"],
        ["-mini", "/20/solid"],
      ];
      icons.forEach(([suffix, dir]) => {
        fs.readdirSync(path.join(iconsDir, dir)).map((file) => {
          let name = path.basename(file, ".svg") + suffix;
          values[name] = { name, fullPath: path.join(iconsDir, dir, file) };
        });
      });
      matchComponents(
        {
          hero: ({ name, fullPath }) => {
            let content = fs
              .readFileSync(fullPath)
              .toString()
              .replace(/\r?\n|\r/g, "");
            return {
              [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
              "-webkit-mask": `var(--hero-${name})`,
              mask: `var(--hero-${name})`,
              "background-color": "currentColor",
              "vertical-align": "middle",
              display: "inline-block",
              width: theme("spacing.5"),
              height: theme("spacing.5"),
            };
          },
        },
        { values }
      );
    }),
  ],
};
