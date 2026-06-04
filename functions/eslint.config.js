module.exports = [
  {
    files: ["**/*.js"],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "commonjs",
      globals: {
        exports: "readonly",
        require: "readonly",
      },
    },
    rules: {
      "max-len": ["error", {code: 80}],
      "object-curly-spacing": ["error", "never"],
      quotes: ["error", "double"],
      semi: ["error", "always"],
    },
  },
];
